#!/bin/bash
# Builds "YT Downloader.app" from YTDownloader.swift - no Xcode project needed.
set -euo pipefail
cd "$(dirname "$0")"

APP="YT Downloader.app"
EXE="YTDownloader"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found. Install the Command Line Tools first:"
  echo "    xcode-select --install"
  exit 1
fi

echo "Building ${APP}..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library \
  -target "$(uname -m)-apple-macos13.0" \
  YTDownloader.swift \
  -o "$APP/Contents/MacOS/$EXE"

# App icon (regenerate with: swiftc make-icon.swift -o /tmp/mkicon && /tmp/mkicon /tmp/AppIcon.iconset && iconutil -c icns /tmp/AppIcon.iconset)
if [ -f AppIcon.icns ]; then
  cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$EXE</string>
  <key>CFBundleIdentifier</key><string>com.haguilar.ytdownloader</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleName</key><string>YT Downloader</string>
  <key>CFBundleDisplayName</key><string>YT Downloader</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# Ad-hoc signature so macOS will launch it locally.
codesign --force --sign - "$APP" >/dev/null

echo "Done."
echo "Run it:      open \"$APP\""
echo "Install it:  mv \"$APP\" /Applications/"
