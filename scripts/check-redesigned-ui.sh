#!/bin/bash
# Existing Spotify-layout mocks, built against the real Kit. No IPA, account or signing data.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p out/ui-checks
LOGS="$PWD/out/ui-checks"
bash scripts/check-layers.sh
bash harness/lockart/build.sh > "$LOGS/lockart-build.log" 2>&1 || { tail -80 "$LOGS/lockart-build.log"; exit 1; }
python3 harness/lockart/server.py "$LOGS/download-count.json" > "$LOGS/download-server.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
for ((attempt=0; attempt<60; attempt++)); do
    if grep -q ready "$LOGS/download-server.log"; then break; fi
    sleep 1
done
grep -q ready "$LOGS/download-server.log" || { cat "$LOGS/download-server.log"; exit 1; }
SG_ARTWORK_TEST_SERVER=http://127.0.0.1:9124 harness/lockart/build/lockart 2>&1 | tee "$LOGS/lockart.log"
python3 - "$LOGS/download-count.json" <<'PY'
import json, sys
with open(sys.argv[1]) as file:
    counts = json.load(file)
assert counts == {'/shared': 1, '/failure': 1}, counts
PY
kill "$SERVER_PID" 2>/dev/null || true
trap - EXIT
echo 'Shared artwork cache, crop and source checks: passed'
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

# Wait for main-queue completion instead of assuming the simulator has rendered after launch.
wait_for_result() {
    local log=$1 pattern=$2
    for ((attempt=0; attempt<60; attempt++)); do
        if grep -q "$pattern" "$log"; then return 0; fi
        sleep 1
    done
    echo "Timed out waiting for $pattern"
    tail -60 "$log"
    return 1
}

capture() {
    local part=$1 bundle=$2 shot=$3
    shift 3
    local app
    app=$(find "harness/$part/build" -name '*.app' -type d | head -1)
    xcrun simctl install "$DEVICE" "$app"
    xcrun simctl launch --stdout="$LOGS/$shot-stdout.log" --stderr="$LOGS/$shot-stderr.log" "$DEVICE" "$bundle" "$@"
    case "$shot" in
        album) wait_for_result "$LOGS/$shot-stderr.log" 'late: Play.s right shows' ;;
        playlist) wait_for_result "$LOGS/$shot-stderr.log" 'playlist snapshot ready' ;;
        liked) wait_for_result "$LOGS/$shot-stderr.log" 'liked: after the shuffle.s parent laid out' ;;
        artist) wait_for_result "$LOGS/$shot-stderr.log" 'pinned more:' ;;
        library) wait_for_result "$LOGS/$shot-stderr.log" 'library snapshot ready' ;;
        player) wait_for_result "$LOGS/$shot-stderr.log" 'footer glyphs end at' ;;
        lyrics) wait_for_result "$LOGS/$shot-stderr.log" 'lyrics snapshot ready' ;;
        tabbar) wait_for_result "$LOGS/$shot-stderr.log" 'none screen' ;;
    esac
    # Let the completed layout reach the compositor and transient system banners expire.
    sleep 3
    xcrun simctl io "$DEVICE" screenshot "out/ui-checks/$shot.png"
    xcrun simctl terminate "$DEVICE" "$bundle"
}
# Each player scenario is selected at launch. Wait for its actual result; shared runners
# can take longer than the scheduled animation delay to deliver the main-queue work.
player_checks() {
    local scenario=$1 pattern=$2
    SIMCTL_CHILD_HARNESS_SCENARIO="$scenario" xcrun simctl launch \
        --stdout="$LOGS/$scenario-stdout.log" --stderr="$LOGS/$scenario-stderr.log" \
        "$DEVICE" com.vojta.playerharness
    if [ "$scenario" = animation ]; then
        wait_for_result "$LOGS/$scenario-stderr.log" 'first frame revealed over the still -- PASS'
        python3 harness/player/record.py "$DEVICE" "$LOGS/animated-cover.mp4"
    fi
    wait_for_result "$LOGS/$scenario-stderr.log" "$pattern"
    if [ "$scenario" = layout ]; then
        xcrun simctl io "$DEVICE" screenshot "out/ui-checks/player-small-cover.png"
    fi
    xcrun simctl terminate "$DEVICE" com.vojta.playerharness
    echo "$scenario scenario: passed"
}
xcrun simctl install "$DEVICE" harness/player/build/PlayerHarness.app
player_checks animation 'animated cover checks:.*PASS'

capture album com.vojta.albumharness album late
capture playlist com.vojta.playlistharness playlist other late snapshot
capture playlist com.vojta.playlistharness liked liked
capture artist com.vojta.artistharness artist
capture library com.vojta.libraryharness library
SIMCTL_CHILD_HARNESS_SCENARIO=look capture player com.vojta.playerharness player

player_checks artwork 'artwork checks: 4 of 4 right -- PASS'
player_checks scroll 'scroll checks:.*PASS'
player_checks layout 'layout checks:.*PASS'

# Exercise the timed collapse/pull and menu forwarding separately from the stable portrait.
xcrun simctl launch --stdout="$LOGS/playlist-states-stdout.log" \
    --stderr="$LOGS/playlist-states-stderr.log" "$DEVICE" com.vojta.playlistharness other late
wait_for_result "$LOGS/playlist-states-stderr.log" 'header checks:.*PASS'
grep -q 'state collapsed:.*picture drawn' "$LOGS/playlist-states-stderr.log"
grep -q 'state pulled:.*picture drawn' "$LOGS/playlist-states-stderr.log"
grep -q 'pinned more takes the touch: SGRMirrorButton' "$LOGS/playlist-states-stderr.log"
xcrun simctl terminate "$DEVICE" com.vojta.playlistharness
echo 'Playlist collapse, pull and more-button hit checks: passed'
capture lyrics com.vojta.lyricsharness.new lyrics -song both -at 40000
capture tabbar com.vojta.tabbarharness tabbar
grep -q 'drawer checks:.*PASS' "$LOGS/tabbar-stderr.log"
echo "Nine portrait screenshots captured from the recorded-layout harnesses. Real Spotify/device QA is still required." | tee out/ui-checks/runtime.txt
