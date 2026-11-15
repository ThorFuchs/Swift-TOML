#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Builds the DocC documentation without a package plugin dependency.
#   Tools/build-docc.sh [output-dir] [hosting-base-path]
# With a hosting base path, the output is a static website for GitHub Pages.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output=${1:-"$root/.build/TOML.doccarchive"}
base=${2:-}
cd "$root"
scratch="$root/.build/docc-build"
swift package --scratch-path "$scratch" dump-symbol-graph --skip-synthesized-members >/dev/null 2>&1
symbols=$(mktemp -d "${TMPDIR:-/tmp}/swift-toml-docc.XXXXXXXX")
trap 'rm -rf "$symbols"' EXIT HUP INT TERM
symbol=$(find "$scratch" -type f -name TOML.symbols.json -print -quit)
test -n "$symbol"
cp "$symbol" "$symbols/TOML.symbols.json"
set -- convert Sources/TOML/TOML.docc --additional-symbol-graph-dir "$symbols" \
  --fallback-display-name TOML --fallback-bundle-identifier io.github.thorfuchs.swift-toml \
  --fallback-bundle-version 1.0.0 --output-path "$output" --warnings-as-errors
if [ -n "$base" ]; then
  set -- "$@" --transform-for-static-hosting --hosting-base-path "$base"
fi
if command -v docc >/dev/null 2>&1; then docc "$@"; else xcrun docc "$@"; fi
printf 'Documentation: %s\n' "$output"
