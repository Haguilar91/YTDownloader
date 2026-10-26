# YT Downloader

A small native macOS app (SwiftUI) that wraps the `yt-dlp` command line tool.

- Paste one or more links, pick a format (video, MP4, or audio as MP3, M4A, FLAC, WAV, Opus)
- Optional whole-playlist download, choose the output folder
- Progress bar, cancel button, and a details log

## Requirements

- macOS 13 or later
- Command Line Tools (`xcode-select --install`), no full Xcode needed
- `brew install yt-dlp ffmpeg`

## Build

    ./build.sh
    open "YT Downloader.app"

The app avoids SwiftUI macros (`@State`, `@Observable`, `#Preview`) because their
plugins ship only with full Xcode.

The icon is drawn by `make-icon.swift`; the generated `AppIcon.icns` is committed.
