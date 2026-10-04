#!/bin/sh
set -eu

# CI_TEAM_ID can identify the App Store Connect organisation rather than the
# Developer Program signing team. Configure the latter in the cloud workflow.
signing_team="${HAPTICK_DEVELOPMENT_TEAM:?Set HAPTICK_DEVELOPMENT_TEAM in Xcode Cloud}"
case "$signing_team" in
    *[!A-Za-z0-9]*) echo "Invalid signing team" >&2; exit 1 ;;
esac
if [ "${#signing_team}" -ne 10 ]; then
    echo "The signing team must be a 10-character Developer Program team ID" >&2
    exit 1
fi
printf 'DEVELOPMENT_TEAM = %s\n' "$signing_team" > "$CI_PRIMARY_REPOSITORY_PATH/Local.xcconfig"

"$CI_PRIMARY_REPOSITORY_PATH/Tests/run.sh"
