#!/bin/bash
# Makes the App Store pictures: every moment of the series (StoreTools/Shots.json), on every device asked for, in every
# language asked for, each at Apple's exact size and checked; and the product page header. After any change to the
# interface, run it again.
#
#   scripts/store-assets.sh [--devices mac] [--languages en,fr] [--caption on|off] [--bezel FILE]
#                           [--appearance plan|light|dark] [--header|--no-header] [--out DIR]
#                           [--compose-only] [--skip-build]
#
#   --devices      Device ids from Shots.json, comma-separated (default mac). mac is captured from the app's own
#                  window. The others (iphone-6.3, iphone-6.9, ipad-13, duo-outer, duo-inner) run the StoreShots UI
#                  tests on their simulator, one simulator at a time; see StoreTools/StoreShots.md.
#   --languages    App Store languages, comma-separated (default en). Each runs the app in that language.
#   --caption      Captions above the pictures, from StoreTools/Captions.xcstrings (default on).
#   --bezel        A bezel description (see StoreTools/README.md); default none.
#   --appearance   plan: each moment in the appearance Shots.json gives it (default); light or dark: all in one.
#   --header       Also render the product page header, light and dark (default, with --devices mac); --no-header not.
#   --out          Where the pictures go (default: scratch/store/out in the main checkout).
#   --compose-only Compose again from the captures of an earlier run, for another caption or bezel choice.
#   --skip-build   Use the app and the composer as last built.
#
# Writes OUT/<language>/<device>/01.png and so on, OUT/header/header-light.png and header-dark.png, and the raw
# captures under OUT/captures/. Exits non-zero if anything fails or a picture is refused.
#
# On the Mac it runs only its own copy of the app, launched in the background by its own path, and quits it by its
# process id. On a simulator it installs its own build and launches that.

set -euo pipefail

devices="mac"
languages="en"
caption="on"
bezel=""
appearance="plan"
header=""
out=""
compose_only=0
skip_build=0

while [ $# -gt 0 ]; do
    case "$1" in
        --devices) devices="$2"; shift 2 ;;
        --languages) languages="$2"; shift 2 ;;
        --caption) caption="$2"; shift 2 ;;
        --bezel) bezel="$2"; shift 2 ;;
        --appearance) appearance="$2"; shift 2 ;;
        --header) header=1; shift ;;
        --no-header) header=0; shift ;;
        --out) out="$2"; shift 2 ;;
        --compose-only) compose_only=1; shift ;;
        --skip-build) skip_build=1; shift ;;
        -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "store-assets: unknown option $1" >&2; exit 2 ;;
    esac
done

# The folders, found from where this script is: this checkout, and the main checkout, whose scratch folder keeps the
# pictures when this runs in a worktree.
root="$(cd "$(dirname "$0")/.." && pwd)"
main_checkout="$(git -C "$root" worktree list --porcelain | sed -n '1s/^worktree //p')"
[ -n "$out" ] || out="$main_checkout/scratch/store/out"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
tools="$root/StoreTools"
manifest="$tools/Shots.json"
captions="$tools/Captions.xcstrings"
build="$root/scratch/store-build"
[ -n "$header" ] || { case ",$devices," in *,mac,*) header=1 ;; *) header=0 ;; esac; }

say() { echo "store-assets: $*"; }

# The app (debug, for the store-capture mode) and the composer.
app="$build/app/Build/Products/Debug/NineRings.app/Contents/MacOS/NineRings"
composer_bin="$build/tools/release/store-compose"
if [ "$skip_build" -eq 0 ]; then
    if [ "$compose_only" -eq 0 ]; then
        say "building the Mac app"
        xcodebuild -project "$root/NineRings.xcodeproj" -scheme NineRings -configuration Debug -destination 'platform=macOS' \
            -derivedDataPath "$build/app" CODE_SIGNING_ALLOWED=NO build > "$build-app.log" 2>&1 \
            || { tail -30 "$build-app.log"; say "the app did not build (log: $build-app.log)"; exit 1; }
    fi
    say "building the composer"
    swift build --package-path "$tools" -c release --scratch-path "$build/tools" --product store-compose > "$build-tools.log" 2>&1 \
        || { tail -30 "$build-tools.log"; say "the composer did not build"; exit 1; }
fi
compose() { "$composer_bin" "$@"; }

# The system's locale for an App Store language.
locale_for() {
    case "$1" in
        en) echo en_US ;; fr) echo fr_FR ;; ja) echo ja_JP ;; zh-Hans) echo zh_CN ;; zh-Hant) echo zh_TW ;;
        *) echo "$1" | tr '-' '_' ;;
    esac
}

pid=""
quit_app() {
    if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; pid=""; fi
}
trap quit_app EXIT

# Launches the app with the given arguments, waits until it says it is ready, captures its window to $1.
capture_mac() {
    local file="$1"; shift
    local log="$file.log"
    "$app" "$@" > "$log" 2>&1 &
    pid=$!
    local waited=0
    until grep -q "store-capture: ready\|store-capture: failed" "$log" 2>/dev/null; do
        if ! kill -0 "$pid" 2>/dev/null; then break; fi
        if [ "$waited" -ge 2400 ]; then say "no ready signal after 240 s"; break; fi
        sleep 0.1; waited=$((waited + 1))
    done
    local window
    window="$(sed -n 's/^store-capture: ready window \([0-9]*\)$/\1/p' "$log")"
    if [ -z "$window" ]; then
        cat "$log" >&2; quit_app; say "the app did not get ready for $(basename "$file")"; return 1
    fi
    screencapture -l "$window" -o -x "$file"
    quit_app
    rm -f "$log"
}

failures=0
IFS=',' read -r -a device_list <<< "$devices"
IFS=',' read -r -a language_list <<< "$languages"

# A field of a device in Shots.json.
field() { compose device --manifest "$manifest" --device "$1" | sed -n "s/^$2=//p"; }

# Captures every moment on a simulator with the StoreShots UI tests, into $captures, for $language.
capture_simulator() {
    local device="$1" simulator="$2" result="$out/captures/$language/$device.xcresult"
    local export="$out/captures/$language/$device-export"
    rm -rf "$result" "$export"
    TEST_RUNNER_STORE_MANIFEST="$manifest" TEST_RUNNER_STORE_DEVICE="$device" \
    TEST_RUNNER_STORE_LANGUAGE="$language" TEST_RUNNER_STORE_APPEARANCE="$appearance" \
        xcodebuild test-without-building -project "$root/NineRings.xcodeproj" -scheme StoreShots \
            -destination "platform=iOS Simulator,name=$simulator" -derivedDataPath "$build/app" \
            -resultBundlePath "$result" > "$result.log" 2>&1 \
        || { tail -30 "$result.log"; say "the StoreShots tests failed on $device (log: $result.log)"; return 1; }
    xcrun xcresulttool export attachments --path "$result" --output-path "$export" > /dev/null
    compose collect --from "$export" --to "$captures"
}

for device in "${device_list[@]}"; do
    method="$(field "$device" capture)"
    [ -n "$method" ] || { failures=$((failures + 1)); continue; }
    simulator=""
    booted_here=0
    if [ "$method" = "simulator" ] && [ "$compose_only" -eq 0 ]; then
        simulator="$(field "$device" simulator)"
        destination="platform=iOS Simulator,name=$simulator"
        if [ "$skip_build" -eq 0 ]; then
            say "building the app and StoreShots for $simulator"
            xcodebuild build -project "$root/NineRings.xcodeproj" -scheme NineRings -configuration Debug \
                -destination "$destination" -derivedDataPath "$build/app" CODE_SIGNING_ALLOWED=NO > "$build-sim.log" 2>&1 \
            && xcodebuild build-for-testing -project "$root/NineRings.xcodeproj" -scheme StoreShots -configuration Debug \
                -destination "$destination" -derivedDataPath "$build/app" CODE_SIGNING_ALLOWED=NO >> "$build-sim.log" 2>&1 \
            || { tail -30 "$build-sim.log"; say "the build for $simulator failed"; failures=$((failures + 1)); continue; }
        fi
        # One simulator at a time: boot this one if it is not running, and shut down only what was booted here.
        if ! xcrun simctl list devices booted | grep -q "$simulator ("; then
            xcrun simctl boot "$simulator"
            booted_here=1
        fi
        xcrun simctl bootstatus "$simulator" > /dev/null
        xcrun simctl status_bar "$simulator" override --time 9:41 --batteryLevel 100 --batteryState charged \
            --wifiBars 3 --cellularBars 4 --operatorName ''
        xcrun simctl install "$simulator" "$build/app/Build/Products/Debug-iphonesimulator/NineRings.app"
    fi
    for language in "${language_list[@]}"; do
        captures="$out/captures/$language/$device"
        mkdir -p "$captures"
        if [ "$compose_only" -eq 0 ]; then
            if [ "$method" = "mac-window" ]; then
                window="$(field "$device" window)"
                while IFS=$'\t' read -r -a line; do
                    id="${line[0]}"; shade="${line[1]}"; arguments=("${line[@]:2}")
                    say "capturing $language $device $id ($shade)"
                    # The system's options first, the store-capture options last: see NineRings/Store/StoreLaunch.swift.
                    capture_mac "$captures/$id-$shade.png" \
                        -AppleLanguages "($language)" -AppleLocale "$(locale_for "$language")" \
                        -appearance "$shade" -window-size "$window" \
                        "${arguments[@]}" -store-capture \
                        || failures=$((failures + 1))
                done < <(compose plan --manifest "$manifest" --device "$device" --appearance "$appearance")
            else
                say "capturing $language $device on $simulator"
                capture_simulator "$device" "$simulator" || { failures=$((failures + 1)); continue; }
            fi
        fi
        say "composing $language $device"
        bezel_options=()
        [ -z "$bezel" ] || bezel_options=(--bezel "$bezel")
        compose compose --manifest "$manifest" --captions "$captions" --device "$device" --language "$language" \
            --captures "$captures" --out "$out/$language/$device" --caption "$caption" --appearance "$appearance" \
            ${bezel_options[@]+"${bezel_options[@]}"} \
            || failures=$((failures + 1))
    done
    if [ -n "$simulator" ]; then
        xcrun simctl status_bar "$simulator" clear || true
        [ "$booted_here" -eq 0 ] || xcrun simctl shutdown "$simulator" || true
    fi
done

if [ "$header" -eq 1 ] && [ "$compose_only" -eq 0 ]; then
    for shade in light dark; do
        say "rendering the header ($shade)"
        work="$out/captures/header-$shade"
        rm -rf "$work"; mkdir -p "$work"
        arguments=()
        while IFS= read -r argument; do arguments+=("$argument"); done \
            < <(compose header-arguments --manifest "$manifest" --appearance "$shade" --dir "$work")
        "$app" "${arguments[@]}" > "$work.log" 2>&1 || { cat "$work.log" >&2; failures=$((failures + 1)); continue; }
        rendered="$(ls "$work"/*.png | head -1)"
        compose finish-header --manifest "$manifest" --in "$rendered" --out "$out/header/header-$shade.png" --appearance "$shade" \
            || failures=$((failures + 1))
        rm -f "$work.log"
    done
fi

if [ "$failures" -gt 0 ]; then
    say "$failures step(s) failed"
    exit 1
fi
say "done: $out"
