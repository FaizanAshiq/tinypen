#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
APP="dist/Tinypen.app"

# TINYPEN_UNIVERSAL=1 builds for Apple silicon and Intel at once, as a download would be.
ARCHS=()
[ "${TINYPEN_UNIVERSAL:-}" = 1 ] && ARCHS=(--arch arm64 --arch x86_64)

# --disable-sandbox: Swift Package Manager sandboxes the manifest compile, which cannot nest
# inside another sandbox, as under Homebrew. The package has no dependencies to isolate.
swift build -c "$CONFIG" --disable-sandbox ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c "$CONFIG" --disable-sandbox ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Kept out of Spotlight, so macOS never takes a test build for an installed copy.
touch dist/.metadata_never_index

cp "$BIN/TinypenApp" "$APP/Contents/MacOS/Tinypen"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Signed with a stable identity when there is one: an ad hoc signature is a hash of the binary,
# so every rebuild would be a new app to macOS and Screen Recording would have to be granted
# again. TINYPEN_REQUIRE_IDENTITY=1 fails the build rather than ship an ad hoc download.
IDENTITY="${TINYPEN_SIGN_IDENTITY:-Tinysnap Local Signing}"

if ! security find-identity -p codesigning | grep -qF "$IDENTITY" \
    || ! codesign --force --sign "$IDENTITY" "$APP" 2>/dev/null; then
    if [ "${TINYPEN_REQUIRE_IDENTITY:-}" = 1 ]; then
        echo "Could not sign with \"$IDENTITY\"." >&2
        exit 1
    fi
    codesign --force --sign - "$APP"
fi

echo "Built $APP"
