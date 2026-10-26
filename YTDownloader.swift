import SwiftUI
import AppKit

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct YTDownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("YT Downloader") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
    }
}

// MARK: - Formats

enum DownloadFormat: String, CaseIterable, Identifiable {
    case best = "Best quality video"
    case mp4  = "MP4 video (plays everywhere)"
    case mp3  = "Audio only (MP3)"
    case m4a  = "Audio only (M4A)"
    case flac = "Audio only (FLAC, lossless)"
    case wav  = "Audio only (WAV)"
    case opus = "Audio only (Opus)"

    var id: String { rawValue }

    var isAudio: Bool { self == .mp3 || self == .m4a || self == .flac || self == .wav || self == .opus }

    var arguments: [String] {
        switch self {
        case .best: return ["-f", "bv*+ba/b"]
        case .mp4:  return ["-f", "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b",
                            "--merge-output-format", "mp4"]
        case .mp3:  return ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
        case .m4a:  return ["-x", "--audio-format", "m4a"]
        case .flac: return ["-x", "--audio-format", "flac"]
        case .wav:  return ["-x", "--audio-format", "wav"]
        case .opus: return ["-x", "--audio-format", "opus"]
        }
    }
}

// MARK: - Downloader (runs yt-dlp)

final class Downloader: ObservableObject {
    @Published var log = ""
    @Published var progress: Double = 0
    @Published var status = "Paste a link and press Download."
    @Published var isRunning = false
    @Published var urlText = ""
    @Published var showLog = false

    private var process: Process?
    private var lineBuffer = ""

    static let searchPaths = [
        "/opt/homebrew/bin",              // Homebrew on Apple Silicon
        "/usr/local/bin",                 // Homebrew on Intel
        NSHomeDirectory() + "/.local/bin", // pip --user
        "/usr/bin"
    ]

    static func find(_ name: String) -> String? {
        for dir in searchPaths {
            let path = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    func start(urls: [String], format: DownloadFormat, folder: String, playlist: Bool) {
        guard let ytdlp = Self.find("yt-dlp") else {
            status = "yt-dlp isn’t installed."
            log = "Install it in Terminal, then try again:\n\n    brew install yt-dlp ffmpeg\n"
            return
        }

        log = ""
        lineBuffer = ""
        progress = 0
        status = "Starting…"
        isRunning = true

        var args = [
            "--newline",
            "-P", folder,
            "-o", "%(title)s [%(id)s].%(ext)s",
            playlist ? "--yes-playlist" : "--no-playlist"
        ]
        args += format.arguments
        if let ffmpeg = Self.find("ffmpeg") {
            args += ["--ffmpeg-location", ffmpeg]
        } else {
            appendLog("Note: ffmpeg not found. Merging and audio conversion may fail.\n" +
                      "Install it with: brew install ffmpeg\n\n")
        }
        args += urls

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ytdlp)
        proc.arguments = args

        // Apps launched from Finder get a minimal PATH; add Homebrew so yt-dlp finds its tools.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (Self.searchPaths + [env["PATH"] ?? ""]).joined(separator: ":")
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.consume(text) }
        }

        proc.terminationHandler = { [weak self] p in
            pipe.fileHandleForReading.readabilityHandler = nil
            let code = p.terminationStatus
            let signalled = p.terminationReason == .uncaughtSignal
            DispatchQueue.main.async { self?.finish(code: code, cancelled: signalled) }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            isRunning = false
            status = "Couldn’t start yt-dlp."
            appendLog(error.localizedDescription + "\n")
        }
    }

    func cancel() {
        process?.terminate()
    }

    // MARK: Output handling

    private func consume(_ text: String) {
        lineBuffer += text
        var lines = lineBuffer.components(separatedBy: CharacterSet.newlines)
        lineBuffer = lines.removeLast() // keep partial line for next chunk
        for line in lines where !line.isEmpty {
            handle(line: line)
        }
    }

    private func handle(line: String) {
        appendLog(line + "\n")
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("[download]"),
           let range = trimmed.range(of: #"\d+(\.\d+)?%"#, options: .regularExpression),
           let pct = Double(trimmed[range].dropLast()) {
            progress = min(max(pct / 100, 0), 1)
            status = trimmed.replacingOccurrences(of: "[download]", with: "")
                            .trimmingCharacters(in: .whitespaces)
        } else if trimmed.hasPrefix("[Merger]") || trimmed.hasPrefix("[ExtractAudio]")
                    || trimmed.hasPrefix("[VideoConvertor]") {
            status = "Processing with ffmpeg…"
        } else if trimmed.hasPrefix("ERROR:") {
            status = trimmed
        }
    }

    private func finish(code: Int32, cancelled: Bool) {
        if !lineBuffer.isEmpty { handle(line: lineBuffer); lineBuffer = "" }
        isRunning = false
        process = nil
        if cancelled {
            status = "Cancelled."
        } else if code == 0 {
            progress = 1
            status = "Done."
        } else if !status.hasPrefix("ERROR:") {
            status = "Failed (exit code \(code)). See the log below."
        }
    }

    private func appendLog(_ s: String) {
        log += s
        if log.count > 40_000 { log = String(log.suffix(30_000)) }
    }
}

// MARK: - UI

struct ContentView: View {
    @StateObject private var dl = Downloader()
    @AppStorage("folder") private var folder =
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
        ?? NSHomeDirectory()
    @AppStorage("format") private var formatRaw = DownloadFormat.best.rawValue
    @AppStorage("playlist") private var playlist = false

    private var format: DownloadFormat { DownloadFormat(rawValue: formatRaw) ?? .best }
    private var urls: [String] {
        dl.urlText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
    private var failed: Bool { dl.status.hasPrefix("ERROR") || dl.status.hasPrefix("Failed") }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        TextField("Video or playlist links", text: $dl.urlText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...4)
                            .onSubmit(startDownload)
                        Button {
                            if let s = NSPasteboard.general.string(forType: .string) {
                                dl.urlText = s.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .help("Paste from clipboard")
                    }
                } footer: {
                    Text("Separate several links with a space or a new line.")
                }

                Section {
                    Picker("Format", selection: $formatRaw) {
                        Section("Video") {
                            ForEach(DownloadFormat.allCases.filter { !$0.isAudio }) { f in
                                Text(f.rawValue).tag(f.rawValue)
                            }
                        }
                        Section("Audio") {
                            ForEach(DownloadFormat.allCases.filter { $0.isAudio }) { f in
                                Text(f.rawValue).tag(f.rawValue)
                            }
                        }
                    }
                    Toggle("Download whole playlist", isOn: $playlist)
                    LabeledContent("Save to") {
                        HStack(spacing: 6) {
                            Text((folder as NSString).abbreviatingWithTildeInPath)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Choose\u{2026}", action: chooseFolder)
                            Button {
                                NSWorkspace.shared.open(URL(fileURLWithPath: folder))
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .help("Show in Finder")
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: dl.progress)
                            .opacity(dl.isRunning || dl.progress > 0 ? 1 : 0.35)
                        HStack(spacing: 6) {
                            if dl.status == "Done." {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else if failed {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            }
                            Text(dl.status)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .padding(.vertical, 2)

                    DisclosureGroup("Details", isExpanded: $dl.showLog) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(dl.log.isEmpty ? " " : dl.log)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Color.clear.frame(height: 1).id("end")
                                }
                                .padding(8)
                            }
                            .frame(height: 150)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onChange(of: dl.log) { _ in proxy.scrollTo("end", anchor: .bottom) }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                if dl.isRunning {
                    Button("Cancel", role: .cancel) { dl.cancel() }
                        .controlSize(.large)
                }
                Button(action: startDownload) {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .padding(.horizontal, 6)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(urls.isEmpty || dl.isRunning)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 4)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 440)
    }

    private func startDownload() {
        guard !urls.isEmpty, !dl.isRunning else { return }
        dl.start(urls: urls, format: format, folder: folder, playlist: playlist)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: folder)
        if panel.runModal() == .OK, let url = panel.url {
            folder = url.path
        }
    }
}
