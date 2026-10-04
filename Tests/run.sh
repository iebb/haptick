#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_binary="$(mktemp -t haptick-tests)"
trap 'rm -f "$test_binary"' EXIT
swiftc Shared/Localization.swift Shared/HapTickSettings.swift Tests/main.swift -o "$test_binary"
"$test_binary"
