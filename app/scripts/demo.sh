#!/bin/sh
# Builds the debug app and runs it in demo mode: accounts come from a file of
# otpauth:// URLs (app/scripts/demo-data.txt unless MENU_OTP_DEMO_FILE is set), data
# goes to a temp directory under a throwaway key, and the real accounts, the
# Keychain and the login item are never touched. Extra arguments pass through:
#   app/scripts/demo.sh --self-test          scripted UI checks, exit status = result
#   app/scripts/demo.sh --snapshot <dir>     window screenshots into <dir>
# The app is exec'd directly (not via `open`) so the environment variable and the
# arguments reach it and stdout stays attached.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_FILE="${MENU_OTP_DEMO_FILE:-$ROOT/scripts/demo-data.txt}"
if ! BUILD_LOG="$("$ROOT/scripts/bundle.sh" debug 2>&1)"; then
    echo "$BUILD_LOG" >&2
    exit 1
fi
# Test runs get their own demo data directory (and instance lock), so they work
# while an interactive demo copy is open
case " $* " in
    *" --self-test "* | *" --snapshot "*)
        export MENU_OTP_DEMO_DATA_DIR="${MENU_OTP_DEMO_DATA_DIR:-${TMPDIR:-/tmp}/menu-otp-demo-test}"
        ;;
esac
MENU_OTP_DEMO_FILE="$DEMO_FILE" exec "$ROOT/build/Menu OTP.app/Contents/MacOS/MenuOTP" "$@"
