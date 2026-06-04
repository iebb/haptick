# HapTick Handoff Notes

## Repo Rules

- Always use `master` instead of `main` as the branch name.
- Keep `project.yml` and `HapTick.xcodeproj/project.pbxproj` in sync when changing build settings. `project.yml` is the XcodeGen source of truth, but the checked-in Xcode project is used directly by local/Xcode Cloud workflows.
- App Store Connect rejects duplicate build numbers. Current app version metadata is `MARKETING_VERSION = 1.1` and `CURRENT_PROJECT_VERSION = 3`.

## Product Shape

HapTick is a native SwiftUI haptic metronome/timer with an iOS companion app and a watchOS app that should remain installable and usable independently on Apple Watch.

- Bundle IDs: `ad.neko.haptick` for iOS, `ad.neko.haptick.watchapp` for watchOS.
- The watch app is the primary experience: tap the ring to start/stop, turn the Digital Crown to adjust the value, swipe left/right to switch Interval/BPM display, and optionally flip the wrist to start/stop.
- The iOS companion edits one mode at a time, either interval or BPM, sends settings to the watch, and can send start/stop playback commands when the watch is reachable.
- Settings are persisted and synced with `WatchConnectivity`.

## Watch UI And Timing Behavior

- The watch ring should stay centered on app launch.
- The ring animation is a continuous 60-degree arc. It uses continuous elapsed turns instead of resetting the drawn progress at lap boundaries.
- Pause expensive ring animation when the app is not active/focused or luminance is reduced to save battery.
- The haptic cadence uses monotonic timestamp scheduling with `ProcessInfo.processInfo.systemUptime` and `DispatchSourceTimer`; do not anchor the next pulse to the previous callback time, or timing drift compounds.
- `notifyUser(hapticType:repeatHandler:)` was investigated and should not replace the metronome scheduler without a separate product decision. The SDK limits it to `WKExtendedRuntimeSession` instances scheduled with `startAtDate`, `startAtDate` is alarm-mode only, and inactive use shows system alert UI. HapTick currently uses the `self-care` background mode.

## Haptic Style Constraints

The app allows intervals down to `0.2s`, but the UI must warn in red when the selected style cannot run that fast. Unsupported non-selected styles should also show red, without a selected border.

Practical minimums from real-watch user testing:

- `directionUp`: `0.2s`
- `directionDown`: `0.2s`
- `success`: `0.3s`
- `notification`: `0.75s`
- `failure`: `0.35s`
- `retry`: `0.35s`
- `start`: `0.2s`
- `stop`: `0.25s`
- `click`: `0.2s`

BPM limits should be derived from the effective interval/style constraints. If an entered BPM is too high, show a red warning and suggest slowing down or choosing another supported style.

## App Store And Release Notes

- App Store metadata and screenshots live under `AppStoreConnect/`.
- Descriptions should include the word `metronome`.
- The watch app has a companion iOS app but should still be configured and described as independently usable on Apple Watch.
- Keep encryption compliance declared with `ITSAppUsesNonExemptEncryption = false`.
- App icons are generated from the IconKitchen output and must be applied to both iOS and watch asset catalogs.

## Verification Commands

Use these before pushing behavior or release metadata changes:

```sh
xcodebuild -project HapTick.xcodeproj -scheme 'HapTick Watch App' -destination 'generic/platform=watchOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project HapTick.xcodeproj -scheme 'HapTick' -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
```
