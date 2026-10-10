#!/usr/bin/env bash
# update.sh <Tinypen-mac.zip> <next>: the downloaded Mac app updating itself, as a person's would.
# Unpacked into an Applications folder it can write to and started with a newer build waiting in
# <next> (its Tinypen-mac.zip and version), it downloads it, checks it is signed exactly as itself,
# quits, and starts again as the new version. Run on CI's Mac: it writes Tinypen's settings.
set -euo pipefail

[ -n "${CI:-}" ] || { echo "update.sh runs on CI's Mac only: it writes Tinypen's settings." >&2; exit 1; }
apps="$HOME/Applications"
app="$apps/Tinypen.app"
next="$(cd "$2" && pwd)"
version="$(cat "$next/version")"
failed=0
check() {
    if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; failed=1; fi
}
shown() { plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist"; }

# Settings saved already, so the first start does not open them, which would hold the update.
settings="$HOME/Library/Application Support/Tinypen/preferences.json"
mkdir -p "$(dirname "$settings")"
[ -f "$settings" ] || echo '{}' > "$settings"

mkdir -p "$apps"
ditto -x -k "$1" "$apps"
before="$(shown)"
cat > "$next/latest.json" <<JSON
{"tag_name": "v$version", "assets": [{"name": "Tinypen-mac.zip", "browser_download_url": "file://$next/Tinypen-mac.zip"}]}
JSON
echo "     $before installed, $version waiting"

TINYPEN_UPDATE_FEED="$next" "$app/Contents/MacOS/Tinypen" > app.log 2>&1 &
first=$!
start=$(date +%s)
for _ in $(seq 1 120); do
    if [ "$(shown 2>/dev/null)" = "$version" ] && ! kill -0 "$first" 2>/dev/null \
        && pgrep -f "$app/Contents/MacOS/Tinypen" >/dev/null; then break; fi
    sleep 1
done
echo "     after $(($(date +%s) - start)) s"
sleep 3

check "the copy that downloaded the update quit for it" '! kill -0 "$first" 2>/dev/null'
check "the app in Applications is $version" '[ "$(shown)" = "$version" ]'
check "the new version is running" 'pgrep -f "$app/Contents/MacOS/Tinypen" >/dev/null'
check "nothing is left beside it" '[ ! -e "$app.replaced" ]'
check "its menu says it was updated today" '[ "$(defaults read com.faizanashiq.tinypen TinypenUpdated 2>/dev/null)" = "$version $(date +%F)" ]'

pkill -f "$app/Contents/MacOS/Tinypen" || true
exit $failed
