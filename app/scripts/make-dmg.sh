#!/bin/sh
# Universal release build packaged as "build/Menu OTP-<version>.dmg", version from
# app/Resources/Info.plist's CFBundleShortVersionString.
set -eu
cd "$(dirname "$0")/.."

scripts/bundle.sh release
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
STAGE=build/dmg
DMG="build/Menu OTP-$VERSION.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "build/Menu OTP.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Menu OTP" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "$DMG"
