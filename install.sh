#!/bin/bash
#
# Builds Journal in Release configuration and installs it to /Applications.
#
#   ./install.sh
#
# Signing is worked out automatically:
#
#   * If you've signed in to Xcode with an Apple ID (Xcode → Settings →
#     Accounts), the script finds your Team ID and signs with it. This is the
#     better outcome: a real team identity lets macOS hold the Touch ID key
#     under a Secure Enclave-backed lock, and makes daily reminders reliable.
#
#   * Otherwise it falls back to ad-hoc signing. The app still runs, and your
#     entries are still encrypted with the same AES-GCM and the same passcode
#     — but Touch ID becomes a check the app performs rather than one macOS
#     enforces. Settings tells you which mode you're in.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="Journal"
DESTINATION="/Applications/$APP_NAME.app"

cd "$PROJECT_DIR"

# --- Work out how to sign -----------------------------------------------

TEAM_ID="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | tr ',/' '\n\n' \
    | grep -o 'OU *= *[A-Z0-9]*' \
    | head -1 \
    | sed 's/.*= *//' || true)"

if [ -n "$TEAM_ID" ]; then
    echo "==> Signing with development team $TEAM_ID"
    SIGN_ARGS=(
        CODE_SIGN_STYLE=Automatic
        "DEVELOPMENT_TEAM=$TEAM_ID"
        -allowProvisioningUpdates
    )
else
    echo "==> No development certificate found; signing ad-hoc."
    echo "    For stronger Touch ID protection, open Xcode → Settings → Accounts,"
    echo "    add your Apple ID (free), then run this script again."
    SIGN_ARGS=(
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY=-
        DEVELOPMENT_TEAM=
    )
fi

# --- Build ---------------------------------------------------------------

echo "==> Building $APP_NAME (Release)"
xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    "${SIGN_ARGS[@]}" \
    build \
    | grep -E "^(===|\*\*|error:|warning: [A-Z])" || true

BUILT_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"

if [ ! -d "$BUILT_APP" ]; then
    echo "Build failed: $BUILT_APP not found." >&2
    exit 1
fi

# --- Verify the privacy guarantee before shipping it anywhere -----------

echo "==> Checking entitlements"
ENTITLEMENTS="$(codesign -d --entitlements - --xml "$BUILT_APP" 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null || true)"

if echo "$ENTITLEMENTS" | grep -q "network"; then
    echo "REFUSING TO INSTALL: a network entitlement is present." >&2
    echo "$ENTITLEMENTS" | grep network >&2
    exit 1
fi

if ! echo "$ENTITLEMENTS" | grep -q "app-sandbox"; then
    echo "REFUSING TO INSTALL: the app sandbox is not enabled." >&2
    exit 1
fi

# get-task-allow lets any process attach a debugger and read the decrypted
# key out of memory. Fine in Debug, never in something you actually use.
if echo "$ENTITLEMENTS" | grep -q "get-task-allow"; then
    echo "REFUSING TO INSTALL: get-task-allow is present in a release build." >&2
    exit 1
fi

echo "    Sandbox on, no network entitlement, no debug entitlement. Good."

# --- Install -------------------------------------------------------------

if [ -d "$DESTINATION" ]; then
    echo "==> Replacing existing $DESTINATION"
    rm -rf "$DESTINATION"
fi

echo "==> Installing to $DESTINATION"
cp -R "$BUILT_APP" "$DESTINATION"

echo ""
echo "Done. $APP_NAME is in your Applications folder."
echo ""
echo "Your journal data lives in:"
echo "  ~/Library/Containers/com.karthikvishal.Journal/Data/Library/Application Support/Journal/"
echo "(Settings → Data → Reveal in Finder opens it.)"
