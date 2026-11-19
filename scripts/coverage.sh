#!/bin/sh
# Prints line coverage of a Kit's Sources (tests and dependencies excluded) after
# `swift test --enable-code-coverage`. Fails if below the optional minimum percent.
# Usage: scripts/coverage.sh <KitName> [min-percent]
set -eu
kit="$1"
min="${2:-0}"
json=$(swift test --package-path "Packages/$kit" --show-codecov-path)
percent=$(jq --arg dir "/Packages/$kit/Sources/" '
  [.data[0].files[] | select(.filename | contains($dir)) | .summary.lines]
  | if (map(.count) | add) > 0 then (map(.covered) | add) * 100 / (map(.count) | add) else 100 end
  | floor' "$json")
echo "$kit line coverage: $percent% (minimum $min%)"
[ "$percent" -ge "$min" ]
