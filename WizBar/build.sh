#!/bin/sh
# Build WizBar.app. Pass --install to copy it into ~/Applications.
set -e
cd "$(dirname "$0")"

APP=WizBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 Sources/*.swift -o "$APP/Contents/MacOS/WizBar"
codesign --force -s - "$APP"
echo "Built $(pwd)/$APP"

if [ "$1" = "--install" ]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/"$APP"
  cp -R "$APP" ~/Applications/
  echo "Installed to ~/Applications/$APP"
fi
