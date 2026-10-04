# HapTick

A native haptic timer and silent metronome for iPhone and Apple Watch.

Set an interval or BPM, choose a haptic style, or compose a repeating sequence. Steps use the actual style abbreviations, for example `UP · CLK · SUC · CLK`. Tap a step to change its style, move it, duplicate it, or remove it. Up to 64 steps can repeat continuously.

Start playback on iPhone or send the same composition to Apple Watch. The Watch keeps its saved composition and works independently, including interval/BPM changes with the Digital Crown and optional wrist-flip controls. iPhone haptics play while the app is open; playback stops when the app enters the background. iPhone patterns interpret the Watch styles using Core Haptics, so the physical sensations differ between devices.

The app follows the device language: English, Simplified Chinese, Traditional Chinese, Japanese, French, and Spanish.

## Build

Open `HapTick.xcodeproj` in Xcode. The checked-in project and `project.yml` stay in sync; regenerate with `xcodegen generate` after changing the project configuration.

For local signing, copy `Config/Local.xcconfig.example` to `Local.xcconfig` in the repository root and enter your Apple Development team ID. This file is ignored by Git. A public checkout uses `com.example.haptick` followed by your team ID, with `.watchapp` for the Watch. You can override `HAPTICK_BUNDLE_ID` in that file with your own identifier. This keeps development builds separate from HapTick's published App IDs.

```sh
xcodebuild -project HapTick.xcodeproj -scheme HapTick -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project HapTick.xcodeproj -scheme 'HapTick Watch App' -destination 'generic/platform=watchOS' build CODE_SIGNING_ALLOWED=NO
Tests/run.sh
```

## Xcode Cloud

Use `https://github.com/iebb/haptick.git`, branch `master`, project `HapTick.xcodeproj`, and scheme `HapTick`. Archive for iOS with App Store distribution. Set `HAPTICK_DEVELOPMENT_TEAM` to the 10-character Apple Developer Program team ID in Xcode Cloud's environment variables. `ci_scripts/ci_post_clone.sh` uses it to configure signing, selects the published `ad.neko.haptick` identifier, and runs the shared settings tests. No signing identity or release credential belongs in the source repository. Xcode Cloud manages build numbers, so keep its next number greater than the most recent App Store Connect build.

After an Apple Developer account transfer, verify that **both** the iPhone and Watch App IDs belong to the receiving team. An App Store-used Watch identifier left in the old team prevents distribution and cannot be deleted through the portal. Ask [Apple Developer Program Support](https://developer.apple.com/contact/) to correct the identifier allocation; preserve the existing Watch bundle ID for updates. See [Apple's App ID deletion rules](https://developer.apple.com/help/account/identifiers/delete-an-app-id/) and the [DTS guidance on Watch identifier conflicts](https://developer.apple.com/forums/thread/767280).

## Privacy

Settings and compositions are stored on the device and synced to a paired Apple Watch using WatchConnectivity. The app contains no analytics, advertising, accounts, or network service credentials. App Store release metadata and screenshots are in `AppStoreConnect/`.
