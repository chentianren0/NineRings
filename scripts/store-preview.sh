#!/bin/bash
# Makes the App Store preview videos for iPhone and iPad, in English: the app played on its simulator by the StorePreview
# UI test, recorded from the simulator's screen, cut into three pieces joined by dissolves, with a touch point drawn
# where each tap lands, at Apple's size, 30 frames a second, with a silent stereo track (previews play muted first; the
# simulator records no sound). Also the poster frame: ring 3 part way through the slot, as in the first picture; and the
# same moment at the simulator's full size, upright, as poster-full.png, for other store pictures.
#
#   scripts/store-preview.sh [--devices iphone-6.3,ipad-13] [--out DIR] [--skip-build] [--edit-only]
#
#   --devices    iphone-6.3 (886 x 1920, portrait) and/or ipad-13 (1600 x 1200, landscape); default both.
#   --out        Where the videos go (default: scratch/store/out in the main checkout), as OUT/preview/<device>/preview.mp4
#                poster.png and poster-full.png; the raw recording and the steps under OUT/captures/preview/.
#   --skip-build Use the app and the tests as last built (by this script or scripts/store-assets.sh).
#   --edit-only  Cut the last recording again, without the simulator.
#
# One simulator at a time: it boots the device's simulator only if it is not running, and shuts down only what it booted.
# Needs ffmpeg.

set -euo pipefail

devices="iphone-6.3,ipad-13"
out=""
skip_build=0
edit_only=0
while [ $# -gt 0 ]; do
    case "$1" in
        --devices) devices="$2"; shift 2 ;;
        --out) out="$2"; shift 2 ;;
        --skip-build) skip_build=1; shift ;;
        --edit-only) edit_only=1; shift ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "store-preview: unknown option $1" >&2; exit 2 ;;
    esac
done

root="$(cd "$(dirname "$0")/.." && pwd)"
main_checkout="$(git -C "$root" worktree list --porcelain | sed -n '1s/^worktree //p')"
[ -n "$out" ] || out="$main_checkout/scratch/store/out"
mkdir -p "$out"; out="$(cd "$out" && pwd)"
manifest="$root/StoreTools/Shots.json"
build="$root/scratch/store-build"
composer_bin="$build/tools/release/store-compose"
say() { echo "store-preview: $*"; }
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
command -v ffmpeg > /dev/null || { say "needs ffmpeg"; exit 1; }

if [ "$skip_build" -eq 0 ] || [ ! -x "$composer_bin" ]; then
    swift build --package-path "$root/StoreTools" -c release --scratch-path "$build/tools" --product store-compose > "$build-tools.log" 2>&1 \
        || { tail -30 "$build-tools.log"; say "the composer did not build"; exit 1; }
fi
field() { "$composer_bin" device --manifest "$manifest" --device "$1" | sed -n "s/^$2=//p"; }

# The preview's size and whether it is landscape, per device.
preview_size() {
    case "$1" in
        iphone-6.3) echo "886 1920 0" ;;
        ipad-13) echo "1600 1200 1" ;;
        *) say "no preview for $1 (iphone-6.3 or ipad-13)"; return 1 ;;
    esac
}

# Records the preview's sequence on the device's simulator into $work: raw.mov, marks.txt, and start.txt (when the
# recording started).
record() {
    local device="$1" work="$2" landscape="$3" simulator destination booted_here=0
    simulator="$(field "$device" simulator)"
    destination="platform=iOS Simulator,name=$simulator"
    xcrun simctl list devices available | grep -qF -- "    $simulator (" \
        || { say "no simulator named \"$simulator\"; make one or change Shots.json"; return 1; }
    if [ "$skip_build" -eq 0 ]; then
        say "building the app and the tests for $simulator"
        xcodebuild build -project "$root/NineRings.xcodeproj" -scheme NineRings -configuration Debug \
            -destination "$destination" -derivedDataPath "$build/app" CODE_SIGNING_ALLOWED=NO > "$build-sim.log" 2>&1 \
        && xcodebuild build-for-testing -project "$root/NineRings.xcodeproj" -scheme StoreShots -configuration Debug \
            -destination "$destination" -derivedDataPath "$build/app" CODE_SIGNING_ALLOWED=NO >> "$build-sim.log" 2>&1 \
        || { tail -30 "$build-sim.log"; say "the build for $simulator failed"; return 1; }
    fi
    if ! xcrun simctl list devices booted | grep -qF -- "    $simulator ("; then
        xcrun simctl boot "$simulator"; booted_here=1
    fi
    xcrun simctl bootstatus "$simulator" > /dev/null
    xcrun simctl status_bar "$simulator" override --time 9:41 --batteryLevel 100 --batteryState charged \
        --wifiBars 3 --cellularBars 4 --operatorName ''
    xcrun simctl install "$simulator" "$build/app/Build/Products/Debug-iphonesimulator/NineRings.app"

    rm -rf "$work"; mkdir -p "$work"
    xcrun simctl io "$simulator" recordVideo --codec=h264 --force "$work/raw.mov" > "$work/record.log" 2>&1 &
    local recorder=$! waited=0
    until grep -q "Recording started" "$work/record.log" 2>/dev/null; do
        sleep 0.05; waited=$((waited + 1))
        [ "$waited" -lt 400 ] || { cat "$work/record.log"; kill "$recorder" 2>/dev/null; say "the recording did not start"; return 1; }
    done
    now > "$work/start.txt"
    say "playing the sequence on $simulator (about two minutes)"
    local result=0
    TEST_RUNNER_STORE_MARKS="$work/marks.txt" TEST_RUNNER_STORE_LANDSCAPE="$landscape" \
        xcodebuild test-without-building -project "$root/NineRings.xcodeproj" -scheme StoreShots \
            -only-testing:StoreShots/StorePreview/testPreview -destination "$destination" \
            -derivedDataPath "$build/app" -resultBundlePath "$work/preview.xcresult" > "$work/test.log" 2>&1 || result=1
    kill -INT "$recorder"; wait "$recorder" || true
    xcrun simctl status_bar "$simulator" clear || true
    [ "$booted_here" -eq 0 ] || xcrun simctl shutdown "$simulator" || true
    [ "$result" -eq 0 ] || { tail -30 "$work/test.log"; say "the StorePreview test failed (log: $work/test.log)"; return 1; }
}

# The time of a step, in seconds from the recording's start; with "x" or "y", where its tap landed.
step() { awk -v name="$2" -v what="${3:-t}" -v start="$(cat "$1/start.txt")" \
    '$1 == name { if (what == "t") printf "%.3f\n", $2 - start; else if (what == "x") print $3; else print $4 }' "$1/marks.txt"; }
calc() { awk "BEGIN { printf \"%.3f\", $* }"; }

# Cuts $work's recording into the preview and its poster frame in $dest.
edit() {
    local device="$1" work="$2" dest="$3" width height landscape
    read -r width height landscape < <(preview_size "$device")
    local raw_w raw_h
    raw_w="$(ffprobe -v error -select_streams v -show_entries stream=width -of csv=p=0 "$work/raw.mov")"
    raw_h="$(ffprobe -v error -select_streams v -show_entries stream=height -of csv=p=0 "$work/raw.mov")"
    # The recorder's frames come out of order (B-frames at a varying rate), and part-way through ffmpeg would time them
    # by their decoding times, seconds behind: -fflags +igndts keeps their own times.
    # The simulator records its screen as the display scans it: turn a portrait recording of a landscape preview.
    local turn="" frame_w="$raw_w"
    if [ "$landscape" -eq 1 ] && [ "$raw_h" -gt "$raw_w" ]; then turn="transpose=2,"; frame_w="$raw_h"; fi
    local points_w scale
    points_w="$(awk '$1 == "screen" { print $3 }' "$work/marks.txt")"
    scale="$(calc "$frame_w / $points_w")"

    # The pieces: ring 1 and ring 3 off, then ring 5 refused, with its reason; with a dissolve, Solve playing on; with a
    # dissolve, the last ring off, the congratulation, and every ring back on, which is where the preview starts again.
    local fade=0.5 r1 r3 rf sv la rs
    r1="$(step "$work" ring1)"; r3="$(step "$work" ring3)"; rf="$(step "$work" refuse)"
    sv="$(step "$work" solve)"; la="$(step "$work" last)"; rs="$(step "$work" reset)"
    local cuts=(
        "$(calc "$r1 - 0.4")" "$(calc "$rf + 2.8")"
        "$(calc "$sv - 0.1")" "$(calc "$sv + 7")"
        "$(calc "$la - 0.4")" "$(calc "$rs + 3.0")"
    )
    length() { calc "${cuts[$((2 * $1 + 1))]} - ${cuts[$((2 * $1))]}"; }
    local total
    total="$(calc "$(length 0) + $(length 1) + $(length 2) - 2 * $fade")"
    # Apple: 15 to 30 seconds. Shorten the solving piece if needed, to no less than 3 seconds.
    if awk "BEGIN { exit !($total > 29.8) }"; then
        cuts[3]="$(calc "${cuts[3]} - ($total - 29.8)")"
        awk "BEGIN { exit !($(length 1) >= 3) }" || { say "the pieces are too long for 30 seconds ($total s)"; return 1; }
        total=29.8
    fi
    awk "BEGIN { exit !($total >= 15) }" || { say "the preview is too short ($total s)"; return 1; }

    # A touch point where each tap of the kept pieces lands, from just before the tap to a moment after.
    local taps=(ring1 ring3 refuse solve last reset) size=132 overlays="" previous="turned" index=0
    local circle="color=c=black@0:s=${size}x${size},format=rgba,geq=r=60:g=60:b=67:a='if(lt(hypot(X-66,Y-66),56),64,if(lt(hypot(X-66,Y-66),62),150,0))'"
    local splits="[c]split=${#taps[@]}"
    for name in "${taps[@]}"; do splits+="[c$index]"; index=$((index + 1)); done
    index=0
    for name in "${taps[@]}"; do
        local t x y
        t="$(calc "$(step "$work" "$name") + 0.15")"
        x="$(calc "$(step "$work" "$name" x) * $scale - $size / 2")"; y="$(calc "$(step "$work" "$name" y) * $scale - $size / 2")"
        overlays+="[$previous][c$index]overlay=x=$x:y=$y:enable='between(t,$(calc "$t - 0.2"),$(calc "$t + 0.35"))'[t$index];"
        previous="t$index"; index=$((index + 1))
    done

    # Apple's size: the iPhone's screen is a little taller than 886 x 1920, so a few rows go from the top and bottom.
    local fit="scale=$width:-2,crop=$width:$height"
    local graph="[0:v]fps=30,${turn}format=yuv420p[turned];$circle[c];$splits;$overlays"
    graph+="[$previous]split=3[s0][s1][s2];"
    for index in 0 1 2; do
        graph+="[s$index]trim=${cuts[$((2 * index))]}:${cuts[$((2 * index + 1))]},setpts=PTS-STARTPTS[p$index];"
    done
    local first_end second_end
    first_end="$(calc "$(length 0) - $fade")"
    second_end="$(calc "$first_end + $(length 1) - $fade")"
    graph+="[p0][p1]xfade=transition=fade:duration=$fade:offset=$first_end[x0];[x0][p2]xfade=transition=fade:duration=$fade:offset=$second_end,$fit,format=yuv420p[v]"

    mkdir -p "$dest"
    say "cutting $device: $total s"
    ffmpeg -loglevel error -y -fflags +igndts -i "$work/raw.mov" -f lavfi -i "anullsrc=r=48000:cl=stereo" -filter_complex "$graph" \
        -map "[v]" -map 1:a -t "$total" -r 30 -c:v libx264 -profile:v high -level 4.0 -pix_fmt yuv420p \
        -b:v 11M -maxrate 12M -bufsize 24M -c:a aac -b:a 256k -ac 2 -ar 48000 -movflags +faststart "$dest/preview.mp4"

    # The poster frame: ring 3 part way through the slot, 2.4 s into its move of about 4 s, as in the first picture.
    local poster
    poster="$(calc "$r3 + 2.4 - ${cuts[0]}")"
    ffmpeg -loglevel error -y -ss "$poster" -i "$dest/preview.mp4" -frames:v 1 "$dest/poster.png"
    # The same moment from the recording, at the simulator's full size, upright, without a touch point.
    ffmpeg -loglevel error -y -ss "$(calc "$r3 + 2.4")" -i "$work/raw.mov" -frames:v 1 ${turn:+-vf "${turn%,}"} "$dest/poster-full.png"
    echo "$poster" > "$dest/poster-time.txt"
    local got
    got="$(ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate,channels,sample_rate -show_entries format=duration -of compact=p=0:nk=1 "$dest/preview.mp4" | tr '\n' ' ')"
    say "$device: $dest/preview.mp4 ($got); poster frame at $(printf '%.2f' "$poster") s"
}

failures=0
IFS=',' read -r -a device_list <<< "$devices"
for device in "${device_list[@]}"; do
    read -r _ _ landscape < <(preview_size "$device") || { failures=$((failures + 1)); continue; }
    work="$out/captures/preview/$device"
    if [ "$edit_only" -eq 0 ]; then
        record "$device" "$work" "$landscape" || { failures=$((failures + 1)); continue; }
    fi
    edit "$device" "$work" "$out/preview/$device" || failures=$((failures + 1))
done
[ "$failures" -eq 0 ] || { say "$failures device(s) failed"; exit 1; }
say "done: $out"
