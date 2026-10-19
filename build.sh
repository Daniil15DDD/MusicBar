#!/bin/zsh
# Builds a universal MusicBar.app without Xcode (Command Line Tools are enough).
set -e
cd "$(dirname "$0")"
APP=build/MusicBar.app
rm -rf build && mkdir -p $APP/Contents/MacOS
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos14.2 Sources/*.swift -o build/MusicBar-$arch
done
lipo -create build/MusicBar-arm64 build/MusicBar-x86_64 -output $APP/Contents/MacOS/MusicBar
rm build/MusicBar-arm64 build/MusicBar-x86_64
cp Resources/Info.plist $APP/Contents/Info.plist
codesign --force --sign - --entitlements Resources/MusicBar.entitlements $APP
echo "Built $APP"
