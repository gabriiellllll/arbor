#!/bin/sh
# Packages a signed Arbor.app into a .zip and a .dmg with SHA-256 sums.
# Usage: scripts/package-release.sh <path/to/Arbor.app> <version> <output-dir>
set -eu
app="$1"
version="$2"
out="$3"

mkdir -p "$out"
zip="$out/Arbor-$version.zip"
dmg="$out/Arbor-$version.dmg"

ditto -c -k --keepParent "$app" "$zip"

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Arbor.app"
ln -s /Applications "$staging/Applications"
# ponytail: `hdiutil create` is deprecated on macOS 26+ (still works); move to `diskutil image create` when CI runners do.
hdiutil create -volname "Arbor $version" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null

(cd "$out" && shasum -a 256 "Arbor-$version.zip" "Arbor-$version.dmg" > SHA256SUMS.txt)
cat "$out/SHA256SUMS.txt"
