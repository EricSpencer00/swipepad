#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
cache_dir=${TMPDIR:-/tmp}/swipepad-broad-cache
mkdir -p "$cache_dir"
CLANG_MODULE_CACHE_PATH="$cache_dir" swift build -c release --disable-sandbox >/dev/null
bin_dir=$(swift build -c release --disable-sandbox --show-bin-path)
run_dir=$(mktemp -d /tmp/swipepad-broad.XXXXXX)
trap 'rm -rf "$run_dir"' EXIT
swiftc -O -module-cache-path "$cache_dir" -I "$bin_dir/Modules" Tests/BroadRecognition/main.swift "$bin_dir"/SwipepadCore.build/*.o -o "$run_dir/checks"
"$run_dir/checks"
