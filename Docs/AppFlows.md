# HapTick App Flows

## iOS Companion

Purpose: edit the timer value and behavior comfortably on iPhone, then sync the same settings to Apple Watch.

```mermaid
flowchart TD
    Open["Open HapTick on iPhone"] --> Load["Load saved settings"]
    Load --> Link["Activate WatchConnectivity"]
    Link --> Unit["Choose unit: Interval or BPM"]
    Unit --> Interval{"Interval selected?"}
    Interval -->|Yes| EditInterval["Type interval seconds"]
    Interval -->|No| EditBPM["Type BPM"]
    EditInterval --> ValidateInterval["Clamp interval to >= 0.8s"]
    EditBPM --> ConvertBPM["Convert BPM to interval seconds"]
    ValidateInterval --> Save["Save settings locally"]
    ConvertBPM --> Save
    Save --> Queue["Queue settings for Apple Watch"]
    Queue --> Reachable{"Watch reachable now?"}
    Reachable -->|Yes| Send["Send immediate message"]
    Reachable -->|No| Context["Keep application context queued"]
    Send --> Done["Settings updated"]
    Context --> Done
```

Primary iOS screens:

1. Settings form
2. Unit picker, showing either Interval input or BPM input
3. Haptic Style grid
4. Flip to start/stop toggle
5. Watch sync status

Key rules:

- The user edits either Interval or BPM, never both at the same time.
- Interval is the stored source of truth.
- BPM is converted to interval seconds before saving.
- The only numeric floor is `0.8s` interval.

## watchOS App

Purpose: start and stop a repeating haptic timer with minimal friction on Apple Watch.

```mermaid
flowchart TD
    Open["Open HapTick on Apple Watch"] --> Load["Load saved settings"]
    Load --> Sync["Activate WatchConnectivity"]
    Sync --> Ready["Ready state"]
    Ready --> Crown["Turn Digital Crown"]
    Crown --> Mode{"Current display unit"}
    Mode -->|Interval| AdjustInterval["Adjust interval"]
    Mode -->|BPM| AdjustBPM["Adjust BPM"]
    AdjustInterval --> Persist["Save and sync settings"]
    AdjustBPM --> Persist
    Ready --> Swipe["Swipe left or right"]
    Swipe --> ToggleUnit["Toggle Interval/BPM display"]
    ToggleUnit --> Persist
    Ready --> TapRing["Tap ring"]
    TapRing --> Running["Start haptic loop"]
    Running --> Pulse["Play selected haptic style"]
    Pulse --> Count["Increment pulse counter"]
    Count --> Wait["Wait interval"]
    Wait --> Pulse
    Running --> TapRingStop["Tap ring again"]
    TapRingStop --> Ready
    Running --> Flip["Flip gesture, if enabled"]
    Ready --> Flip
    Flip --> GestureOK{"Fast flip, cooldown clear"}
    GestureOK -->|Yes| ToggleRun["Start or stop"]
    GestureOK -->|No| Ignore["Ignore gesture"]
    ToggleRun --> Ready
    Ignore --> Ready
```

Primary watchOS screens and states:

1. Centered timer ring
2. Ready state, showing `ready`
3. Running state, showing pulse count
4. Style grid below the ring
5. Flip to start/stop toggle below the style grid
6. First-launch Digital Crown hint

Key rules:

- Tap the ring to start or stop.
- Turn the Digital Crown to edit the currently displayed unit.
- Swipe left or right to toggle Interval/BPM display.
- Flip only toggles after a successful fast flip, then waits through cooldown.
- Animation can pause when the watch is dimmed or not focused; haptics continue through the runtime session.

## Shared Settings Contract

```mermaid
flowchart LR
    Phone["iOS PhoneSettingsStore"] <--> WC["WatchConnectivity"]
    Watch["watchOS TimerController"] <--> WC
    Phone --> Shared["HapTickSettings"]
    Watch --> Shared
    Shared --> Defaults["UserDefaults"]
```

Shared fields:

- `intervalSeconds`
- `hapticStyle`
- `motionToggleEnabled`
- `displayMode`
