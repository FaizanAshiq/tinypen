#!/usr/bin/env bash
# swift test, with the Swift Testing macro plugin wired in by hand.
#
# With Command Line Tools and no Xcode, SwiftPM's swiftbuild backend never resolves
# the TestingMacros plugin, so every @Test fails to expand with "external macro
# implementation type could not be found". Pointing swiftc straight at the dylib
# fixes it. On a machine with Xcode the path below does not exist, the flag is
# skipped, and plain swift test already works.
set -euo pipefail

PLUGIN="$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"

if [ -f "$PLUGIN" ]; then
    exec swift test -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN" "$@"
fi

exec swift test "$@"
