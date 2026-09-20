#!/bin/sh
# Runs `swift test`. With only the Command Line Tools installed (no Xcode), Swift
# Testing's framework ships at a path SwiftPM doesn't search by default, so it is
# passed explicitly. With full Xcode selected, plain `swift test` already works.
set -eu
cd "$(dirname "$0")/.."

DEV_DIR="$(xcode-select -p)"
case "$DEV_DIR" in
    */CommandLineTools)
        F="$DEV_DIR/Library/Developer/Frameworks"
        L="$DEV_DIR/Library/Developer/usr/lib"
        exec swift test \
            -Xswiftc -F -Xswiftc "$F" \
            -Xlinker -F -Xlinker "$F" \
            -Xlinker -rpath -Xlinker "$F" \
            -Xlinker -rpath -Xlinker "$L" \
            "$@"
        ;;
    *)
        exec swift test "$@"
        ;;
esac
