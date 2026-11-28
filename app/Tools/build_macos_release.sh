#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: mise run build-release -- <version>, for example 0.1.0" >&2
    exit 2
fi

VERSION="$1"
BUILD_NUMBER="${ARGENTIC_BUILD_NUMBER:-1}"
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "ARGENTIC_BUILD_NUMBER must be a positive integer." >&2
    exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVED_DATA="$ROOT/app/.build/DerivedData-Release"
APP="$DERIVED_DATA/Build/Products/Release/Argentic.app"

# Local previews are unsigned. The release workflow requires a Developer ID identity before
# invoking this task, and Xcode signs embedded code as well as the app with hardened runtime.
SIGNING=(CODE_SIGNING_ALLOWED=NO)
if [[ -n "${MACOS_SIGNING_IDENTITY:-}" ]]; then
    : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required when signing a release}"
    SIGNING=(
        CODE_SIGNING_ALLOWED=YES
        CODE_SIGN_STYLE=Manual
        "CODE_SIGN_IDENTITY=$MACOS_SIGNING_IDENTITY"
        "DEVELOPMENT_TEAM=$APPLE_TEAM_ID"
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
        OTHER_CODE_SIGN_FLAGS=--timestamp
    )
fi

xcodebuild \
    -project "$ROOT/app/Argentic.xcodeproj" \
    -scheme Argentic \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    'ARCHS=arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    MACOSX_DEPLOYMENT_TARGET=14.0 \
    ENABLE_HARDENED_RUNTIME=YES \
    "MARKETING_VERSION=$VERSION" \
    "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
    "${SIGNING[@]}" \
    build

for ARCH in arm64 x86_64; do
    xcrun lipo "$APP/Contents/MacOS/Argentic" -verify_arch "$ARCH"
done
ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ACTUAL_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
if [[ "$ACTUAL_VERSION" != "$VERSION" || "$ACTUAL_BUILD" != "$BUILD_NUMBER" ]]; then
    echo "Release bundle version does not match the requested version/build." >&2
    exit 1
fi
echo "Universal macOS app: $APP (version $ACTUAL_VERSION, build $ACTUAL_BUILD)"
