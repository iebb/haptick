# HapTick

A native haptic timer and silent metronome for iPhone and Apple Watch.

Set an interval or BPM, choose a haptic style, or compose a repeating sequence. Steps use the actual style abbreviations, for example `UP · CLK · SUC · CLK`. Tap a step to change its style, move it, duplicate it, or remove it. Up to 64 steps can repeat continuously.

Start playback on iPhone or send the same composition to Apple Watch. The Watch keeps its saved composition and works independently, including interval/BPM changes with the Digital Crown and optional wrist-flip controls. iPhone haptics play while the app is open; playback stops when the app enters the background. iPhone patterns interpret the Watch styles using Core Haptics, so the physical sensations differ between devices.

The app follows the device language: English, Simplified Chinese, Traditional Chinese, Japanese, French, and Spanish.

## Build

Open `HapTick.xcodeproj` in Xcode. The checked-in project and `project.yml` stay in sync; regenerate with `xcodegen generate` after changing the project configuration.

For local signing, copy `Config/Local.xcconfig.example` to `Local.xcconfig` in the repository root and enter your Apple Development team ID. This file is ignored by Git. Bundle identifiers must belong to your team for device or distribution builds.

```sh
xcodebuild -project HapTick.xcodeproj -scheme HapTick -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project HapTick.xcodeproj -scheme 'HapTick Watch App' -destination 'generic/platform=watchOS' build CODE_SIGNING_ALLOWED=NO
Tests/run.sh
```

## Xcode Cloud

Use `https://github.com/iebb/haptick.git`, branch `master`, project `HapTick.xcodeproj`, and scheme `HapTick`. Archive for iOS with App Store distribution. `ci_scripts/ci_post_clone.sh` configures signing using Xcode Cloud's `CI_TEAM_ID`; no signing identity or release credential belongs in the source repository. Xcode Cloud manages build numbers, so keep its next number greater than the most recent App Store Connect build.

## Privacy

Settings and compositions are stored on the device and synced to a paired Apple Watch using WatchConnectivity. The app contains no analytics, advertising, accounts, or network service credentials. App Store release metadata and screenshots are in `AppStoreConnect/`.
