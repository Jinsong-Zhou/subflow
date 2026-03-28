# SubFlow

Real-time bilingual subtitle overlay for macOS. Captures system audio, transcribes English speech on-device, and displays floating English-Chinese subtitles — all without sending data to the cloud.

Built for Apple Silicon Macs.

---

## Features

- **On-device speech recognition** — Powered by [Moonshine ASR](https://github.com/moonshine-ai/moonshine-swift), runs entirely on Apple Silicon Neural Engine. No cloud, no API keys, no latency.
- **Real-time English-to-Chinese translation** — Uses Apple's built-in [Translation framework](https://developer.apple.com/documentation/translation) for instant bilingual subtitles.
- **Floating subtitle overlay** — A translucent, always-on-top panel that displays streaming captions over any app. Shows active transcription at full brightness and recent history faded.
- **Menu bar app** — Lives in the menu bar, out of your way. Toggle recording from the menu or with a global hotkey.
- **Global hotkey** — `Cmd+Shift+T` to start/stop recording from anywhere.
- **Multiple ASR models** — Choose between:
  | Model | Size | Latency | Accuracy |
  |-------|------|---------|----------|
  | Moonshine Small | ~157 MB | ~73 ms | Good |
  | Moonshine Medium | ~303 MB | ~107 ms | Great |
- **Configurable display** — Adjust subtitle panel width (400–1000pt) and font size (10–24pt) from Settings.
- **Transcript window** — View full session history with timestamps in a separate window.

## Screenshots

<!-- TODO: Add screenshots -->

## Requirements

- **macOS 26.0** (Tahoe) or later
- **Apple Silicon** (M1 / M2 / M3 / M4) — required for Moonshine ASR Neural Engine acceleration
- **Screen Recording permission** — needed to capture system audio via ScreenCaptureKit

## Installation

### Download

1. Go to the [Releases](../../releases) page
2. Download the latest `SubFlow-x.x.x.dmg`
3. Open the DMG and drag **SubFlow** to `/Applications`

### First Launch

Since SubFlow is distributed outside the Mac App Store and is not notarized with Apple, macOS Gatekeeper will block it on first launch:

1. **Right-click** (or Control-click) `SubFlow.app` in Applications
2. Select **Open** from the context menu
3. Click **Open** in the confirmation dialog

Alternatively: System Settings > Privacy & Security > scroll down > click **Open Anyway**.

You only need to do this once.

### Permissions

On first launch, SubFlow will request **Screen Recording** permission to capture system audio. Grant it in:

> System Settings > Privacy & Security > Screen Recording > enable **SubFlow**

A restart of the app may be required after granting permission.

## Usage

### Quick Start

1. Launch SubFlow — a caption bubble icon appears in the menu bar
2. Click the icon and press **Start** (or press `Cmd+Shift+T`)
3. Play any English audio (YouTube, podcast, meeting, etc.)
4. Bilingual subtitles appear in the floating overlay at the bottom of your screen

### Controls

| Action | Method |
|--------|--------|
| Start/Stop recording | `Cmd+Shift+T` or menu bar > Start/Stop |
| Open transcript | Menu bar > Open Transcript |
| Open settings | Menu bar > Settings... |
| Move subtitle panel | Drag the floating panel by its background |
| Quit | Menu bar > Quit |

### Settings

- **Panel Width** — Slider from 400pt to 1000pt (default: 620pt)
- **Font Size** — Slider from 10pt to 24pt (default: 15pt)
- **ASR Model** — Switch between Small (faster) and Medium (more accurate)

## Architecture

```
SubFlow/
├── SubFlowApp.swift          # App entry point, AppDelegate, window management
├── Models/
│   ├── CaptionEntry.swift     # Bilingual caption data model
│   └── CaptionSettings.swift  # User preferences + ASR model definitions
├── ViewModels/
│   └── CaptionViewModel.swift # Core state: recording, streaming, caption history
├── Views/
│   ├── FloatingCaptionView.swift  # Floating subtitle overlay
│   ├── MainWindowView.swift       # Transcript history window
│   ├── MenuBarView.swift          # Menu bar popover
│   └── SettingsView.swift         # Settings panel
├── Services/
│   ├── AudioCaptureService.swift          # System audio capture via ScreenCaptureKit
│   ├── MoonshineTranscriptionService.swift # On-device ASR via Moonshine
│   └── TranslationService.swift           # Apple Translation framework wrapper
├── Utilities/
│   ├── AppLogger.swift        # File-based logging (~~/Library/Logs/SubFlow.log)
│   └── HotkeyManager.swift    # Global Cmd+Shift+T hotkey
└── Windows/
    └── FloatingPanel.swift    # NSPanel subclass for always-on-top overlay
```

### Data Flow

```
System Audio → ScreenCaptureKit → 16kHz Float samples
    → Moonshine ASR (Neural Engine) → English text stream
    → Apple Translation → Chinese text
    → FloatingCaptionView (streaming + completed captions)
```

### Key Design Decisions

- **No cloud dependency** — All processing happens on-device. Audio never leaves your Mac.
- **Streaming pipeline** — Audio is processed in 0.5s chunks for low-latency subtitle updates.
- **Completion display cycle** — Completed captions show at full brightness, then fade to history after a calculated reading time (3–8 seconds based on text length).
- **XcodeGen** — Project uses `project.yml` instead of committing `.xcodeproj`, keeping the repo clean and merge-conflict-free.

## Building from Source

### Prerequisites

- macOS 26.0+
- Xcode 26.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Build & Run

```bash
git clone https://github.com/Jinsong-Zhou/subflow.git
cd subflow
xcodegen generate
open SubFlow.xcodeproj
# Press Cmd+R in Xcode to build and run
```

### Run Tests

```bash
xcodegen generate
xcodebuild test \
  -project SubFlow.xcodeproj \
  -scheme SubFlow \
  -destination 'platform=macOS'
```

### Create DMG Locally

```bash
bash scripts/create-dmg.sh
# Output: build/SubFlow-1.0.0.dmg
```

## Release Process

Releases are automated via GitHub Actions. To publish a new version:

```bash
# 1. Update version in project.yml (MARKETING_VERSION)
# 2. Commit and push
git add -A && git commit -m "chore: bump version to x.y.z"
git push origin main

# 3. Tag and push — CI builds and publishes automatically
git tag -a vx.y.z -m "vx.y.z: description"
git push origin vx.y.z
```

The workflow builds a Release `.app` on a macOS 26 runner, packages it into a `.dmg`, and uploads it to a GitHub Release.

## Privacy

SubFlow processes everything locally:

- **Audio** — Captured via ScreenCaptureKit, processed by Moonshine ASR on the Neural Engine, never sent anywhere
- **Translation** — Handled by Apple's on-device Translation framework
- **No analytics, no telemetry, no network requests** (except for downloading ASR models on first use)
- **Logs** — Written to `~/Library/Logs/SubFlow.log`, cleared on each launch

## Known Limitations

- English-only speech recognition (Moonshine ASR is English-only)
- Translation is currently English → Simplified Chinese only
- Requires macOS 26.0+ (uses latest ScreenCaptureKit and Translation APIs)
- Apple Silicon only (Moonshine models require Neural Engine)
- Not notarized — Gatekeeper warning on first launch

## Contributing

Contributions are welcome. Please open an issue first to discuss what you'd like to change.

## License

[MIT](LICENSE)
