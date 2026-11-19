#!/bin/sh
# Adds every String(localized:) / SwiftUI string used by the app to the String Catalog.
# Run after a build (xcodebuild only extracts strings; it does not update the catalog).
# Usage: scripts/sync-strings.sh [derived-data-path]
set -eu
derived="${1:-DerivedData}"
dir="$derived/Build/Intermediates.noindex/Arbor.build"
[ -n "$(find "$dir" -name '*.stringsdata' -path '*/Arbor.build/Objects-normal/*' 2>/dev/null | head -1)" ] \
    || { echo "no .stringsdata found under $derived; build first" >&2; exit 1; }
find "$dir" -name '*.stringsdata' -path '*/Arbor.build/Objects-normal/*' -print0 \
    | xargs -0 sh -c 'xcrun xcstringstool sync App/Resources/Localizable.xcstrings --stringsdata "$@"' sync
