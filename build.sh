#!/bin/zsh
# Builds a universal ORBT.app without Xcode (Command Line Tools are enough).
set -e
cd "$(dirname "$0")"
APP=build/ORBT.app
rm -rf build && mkdir -p $APP/Contents/MacOS
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos14.2 Sources/*.swift -o build/ORBT-$arch
done
lipo -create build/ORBT-arm64 build/ORBT-x86_64 -output $APP/Contents/MacOS/ORBT
rm build/ORBT-arm64 build/ORBT-x86_64
mkdir -p $APP/Contents/Resources && cp Resources/AppIcon.icns $APP/Contents/Resources/
# optional clock fonts (COOPBL.TTF, Zapfino.ttf, Blackmoor.ttf): kept out of git for their licences, bundled when present
for f in Resources/*.(ttf|TTF)(N); do cp $f $APP/Contents/Resources/; done
cp Resources/Info.plist $APP/Contents/Info.plist
codesign --force --sign - --entitlements Resources/ORBT.entitlements $APP
echo "Built $APP"
