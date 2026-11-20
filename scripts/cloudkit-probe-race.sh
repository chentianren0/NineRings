#!/bin/bash
# Question D.3 of the CloudKit probe (docs/icloud-probe.md): two copies of the app, in two processes, save the same new
# zone at one agreed moment, each with a play of its own; then a third launch looks at what is there and deletes the
# zone. Each round uses a new zone name, which begins with the probe's prefix.
#
#   scripts/cloudkit-probe-race.sh --app PATH/NineRings.app --out DIR [--rounds 5] [--lead 10]
#
#   --app     A debug build of the app, signed with the iCloud entitlement, which talks to the development environment.
#   --out     Where the reports go: DIR/race-<n>-X.txt, -Y.txt and -check.txt, one set per round. Nothing is written
#             anywhere else.
#   --rounds  How many rounds; default 5.
#   --lead    Seconds between starting the two copies and the agreed moment, so that both are ready; default 10.
#
# The copies are started through LaunchServices (`open -g -n`), behind the app in front, and quit by themselves when done.

set -euo pipefail

app=""
out=""
rounds=5
lead=10
while [ $# -gt 0 ]; do
    case "$1" in
        --app) app="$2"; shift 2 ;;
        --out) out="$2"; shift 2 ;;
        --rounds) rounds="$2"; shift 2 ;;
        --lead) lead="$2"; shift 2 ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "cloudkit-probe-race: unknown option $1" >&2; exit 2 ;;
    esac
done
[ -n "$app" ] && [ -d "$app" ] || { echo "cloudkit-probe-race: name the app with --app PATH/NineRings.app" >&2; exit 2; }
[ -n "$out" ] || { echo "cloudkit-probe-race: name the folder for the reports with --out DIR" >&2; exit 2; }
mkdir -p "$out"

for round in $(seq 1 "$rounds"); do
    zone="NineRingsProbeAgain_race$(uuidgen | cut -c1-6)"
    at=$(( $(date +%s) + lead ))
    echo "round $round: zone $zone, agreed moment $(date -u -r "$at" +%H:%M:%SZ)"
    for role in X Y; do
        open -g -n -W --stdout "$out/race-$round-$role.txt" --stderr /dev/null "$app" --args \
            -ApplePersistenceIgnoreState YES -cloudkit-probe race -probe-zone "$zone" -probe-role "$role" -probe-at "$at" &
    done
    wait
    open -g -n -W --stdout "$out/race-$round-check.txt" --stderr /dev/null "$app" --args \
        -ApplePersistenceIgnoreState YES -cloudkit-probe race-check -probe-zone "$zone"
    grep -h "^RESULT" "$out/race-$round-X.txt" "$out/race-$round-Y.txt" "$out/race-$round-check.txt" || true
done
