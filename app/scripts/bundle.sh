#!/bin/sh
# Builds "build/Menu OTP.app". Usage: app/scripts/bundle.sh [debug|release]
# release is a universal (arm64 + x86_64) binary. Needs app/Resources/AppIcon.icns and
# the StatusIcon PNGs (committed; regenerate with app/scripts/make-icons.sh).
set -eu
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP="build/Menu OTP.app"

case "$CONFIG" in
    release)
        case "$(xcode-select -p)" in
            */CommandLineTools)
                # The CLT's SwiftPM can't build two architectures at once (that
                # needs xcbuild), so build each triple and lipo them together
                ARM=arm64-apple-macosx14.0
                X86=x86_64-apple-macosx14.0
                swift build -c release --triple "$ARM"
                swift build -c release --triple "$X86"
                mkdir -p build
                lipo -create -output build/MenuOTP \
                    "$(swift build -c release --triple "$ARM" --show-bin-path)/MenuOTP" \
                    "$(swift build -c release --triple "$X86" --show-bin-path)/MenuOTP"
                BIN=build/MenuOTP
                ;;
            *)
                # Xcode's SwiftPM (the swift-build build system) builds a universal
                # binary directly. Its per-triple builds would share one output
                # directory and overwrite each other, so don't use the CLT route.
                # It warns that x86_64 is deprecated "for macOS 27.0"; that's its
                # default ARCHS talking — the binary's minimum is still 14.0.
                swift build -c release --arch arm64 --arch x86_64
                BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MenuOTP"
                ;;
        esac
        case "$(lipo -archs "$BIN")" in
            *arm64*x86_64* | *x86_64*arm64*) ;;
            *)
                echo "expected a universal binary, got: $(lipo -archs "$BIN")" >&2
                exit 1
                ;;
        esac
        ;;
    debug)
        swift build -c debug
        BIN="$(swift build -c debug --show-bin-path)/MenuOTP"
        ;;
    *)
        echo "usage: $0 [debug|release]" >&2
        exit 2
        ;;
esac

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MenuOTP"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Build number = commit count, stamped into the bundle's copy only, so each build from
# a later commit sorts after the ones before it and nobody has to bump it. The source
# plist's CFBundleVersion is just the fallback for a tree with no git history (a
# source tarball). A shallow clone would count 1, so CI checks out full history.
if BUILD="$(git rev-list --count HEAD 2>/dev/null)"; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns Resources/StatusIcon.png Resources/StatusIcon@2x.png "$APP/Contents/Resources/"

# Ad-hoc signature: not a Developer ID and not notarized. Gatekeeper still blocks
# the first launch of a downloaded copy (right-click -> Open, or strip quarantine).
codesign --force --sign - "$APP"
echo "$APP"
