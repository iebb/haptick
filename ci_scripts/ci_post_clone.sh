#!/bin/sh
set -eu

# Signing identity comes from the connected Apple account, never from source.
if [ -n "${CI_TEAM_ID:-}" ]; then
    case "$CI_TEAM_ID" in
        *[!A-Za-z0-9]*) echo "Invalid CI_TEAM_ID" >&2; exit 1 ;;
    esac
    printf 'DEVELOPMENT_TEAM = %s\n' "$CI_TEAM_ID" > "$CI_PRIMARY_REPOSITORY_PATH/Local.xcconfig"
fi

"$CI_PRIMARY_REPOSITORY_PATH/Tests/run.sh"
