#!/bin/bash
set -euo pipefail
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
device=$(xcrun simctl list -j devices available | python3 -c 'import json, sys
for runtime, devices in reversed(sorted(json.load(sys.stdin)["devices"].items())):
    matches=[d["udid"] for d in devices if ".iOS-" in runtime and d["name"].startswith("iPhone")]
    if matches:
        print(matches[0]); break
else:
    sys.exit("No iPhone simulator runtime is installed")')
xcrun simctl bootstatus "$device" -b > "$workdir/boot.log" &
boot=$!
flags=(-target "$(uname -m)-apple-ios16.0-simulator" -isysroot "$sdk" -fobjc-arc -fblocks)
xcrun clang "${flags[@]}" -DCP26AppForView=CP26FixtureAppForView -c CommunicationLists.m -o "$workdir/lists.o"
xcrun clang "${flags[@]}" tests/CommunicationRegression.m "$workdir/lists.o" CommunicationUI.m CommunicationAppearance.m SpotifyReference.m \
  -framework UIKit -framework Foundation -framework CoreFoundation -framework CoreGraphics -framework QuartzCore -o "$workdir/CommunicationRegression"
wait "$boot"
xcrun simctl spawn "$device" "$workdir/CommunicationRegression"
