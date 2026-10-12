#!/bin/bash
# Existing Spotify-layout mocks, built against the real Kit. No IPA, account or signing data.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p out/ui-checks
LOGS="$PWD/out/ui-checks"
bash scripts/check-layers.sh
for part in album playlist artist library player lyrics tabbar; do
    bash "harness/$part/build.sh" > "out/ui-checks/$part-build.log" 2>&1 || {
        tail -80 "out/ui-checks/$part-build.log"
        exit 1
    }
    echo "$part harness: compiled"
done

# The recorded harnesses use an iOS 26 app lifecycle. Do not claim a runtime pass on iOS 27.
xcrun simctl list devices available -j > out/ui-checks/devices.json
DEVICE=$(python3 - <<'PY'
import json
with open('out/ui-checks/devices.json') as file:
    devices = json.load(file)['devices']
for runtime, candidates in devices.items():
    if 'iOS-26-' not in runtime:
        continue
    for device in candidates:
        if device.get('isAvailable') and 'iPhone' in device['name']:
            print(device['udid'])
            raise SystemExit
PY
)
if [ -z "$DEVICE" ]; then
    echo "All seven harnesses compiled. Runtime screenshots skipped: no iOS 26 iPhone simulator installed." | tee out/ui-checks/runtime.txt
    exit 0
fi
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl status_bar "$DEVICE" override --time '9:41' --batteryState charged --batteryLevel 100

capture() {
    local part=$1 bundle=$2 shot=$3
    shift 3
    local app
    app=$(find "harness/$part/build" -name '*.app' -type d | head -1)
    xcrun simctl install "$DEVICE" "$app"
    xcrun simctl launch --stdout="$LOGS/$shot-stdout.log" --stderr="$LOGS/$shot-stderr.log" "$DEVICE" "$bundle" "$@"
    sleep 5
    xcrun simctl io "$DEVICE" screenshot "out/ui-checks/$shot.png"
    xcrun simctl terminate "$DEVICE" "$bundle"
}
capture album com.vojta.albumharness album late
capture playlist com.vojta.playlistharness playlist other late
capture playlist com.vojta.playlistharness liked liked
capture artist com.vojta.artistharness artist
capture library com.vojta.libraryharness library
capture player com.vojta.playerharness player
SIMCTL_CHILD_HARNESS_SCENARIO=artwork xcrun simctl launch \
    --stdout="$LOGS/artwork-stdout.log" --stderr="$LOGS/artwork-stderr.log" \
    "$DEVICE" com.vojta.playerharness
sleep 17
grep -q 'artwork checks: 4 of 4 right -- PASS' out/ui-checks/artwork-stderr.log
grep -q 'scroll checks:.*PASS' out/ui-checks/artwork-stderr.log
xcrun simctl terminate "$DEVICE" com.vojta.playerharness
capture lyrics com.vojta.lyricsharness.new lyrics -song both -at 40000
capture tabbar com.vojta.tabbarharness tabbar
echo "Eight portrait screenshots captured from the recorded-layout harnesses. Real Spotify/device QA is still required." | tee out/ui-checks/runtime.txt
