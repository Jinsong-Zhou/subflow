# SubFlow

Real-time bilingual subtitle overlay for macOS. Captures system audio, transcribes English speech on-device, and displays floating English-Chinese subtitles — all without sending data to the cloud.

Built for Apple Silicon Macs.

---

## Features

- **On-device speech recognition** — Powered by [Moonshine ASR](https://github.com/moonshine-ai/moonshine-swift), runs entirely on Apple Silicon Neural Engine. No cloud, no API keys, no latency.
- **Real-time English-to-Chinese translation** — Uses Apple's built-in [Translation framework](https://developer.apple.com/documentation/translation) for instant bilingual subtitles.
- **Zoom-style scrolling subtitles** — A translucent, always-on-top floating panel with smooth scrolling. New captions appear at the bottom, old ones scroll up. Scroll back with the mouse wheel to review history.
- **Menu bar app** — Lives in the menu bar, out of your way. Toggle recording from the menu or with a global hotkey.
- **Global hotkey** — `Cmd+Shift+T` to start/stop recording from anywhere.
- **Resizable panel** — Drag the panel edges to resize. Drag the background to move.
- **Multiple ASR models** — Choose between:
  | Model | Size | Latency | Accuracy |
  |-------|------|---------|----------|
  | Moonshine Small | ~157 MB | ~73 ms | Good |
  | Moonshine Medium | ~303 MB | ~107 ms | Great |
- **Configurable display** — Adjust subtitle panel width (400–1000pt) and font size (10–24pt) from Settings.
- **Transcript window** — View full session history with timestamps in a separate window.

## Requirements

- **macOS 26.0** (Tahoe) or later
- **Apple Silicon** (M1 / M2 / M3 / M4) — required for Moonshine ASR Neural Engine acceleration
- **Xcode 26.0+** — for building from source
- **Screen Recording permission** — needed to capture system audio via ScreenCaptureKit

## Installation

SubFlow is distributed as source. Clone the repo, open in Xcode, hit Run. No DMG, no notarization ceremony — a free Apple ID signed into Xcode is enough to build and run locally; a paid Apple Developer Program membership is **not** required.

The [Quick start](#quick-start) below is copy-pasteable from top to bottom.

### Quick start

```bash
brew install xcodegen
git clone https://github.com/Jinsong-Zhou/subflow.git
cd subflow
xcodegen generate
open SubFlow.xcodeproj
```

Then, in Xcode, press **Run** (⌘R). If it prompts for a signing team, pick your own Apple ID's Personal Team from the dropdown.

The rest of this section walks through the same steps with more detail, plus test commands and troubleshooting.

### Step 0: Verify Prerequisites

```bash
# Check macOS version (must be 26.0+)
sw_vers --productVersion

# Check Xcode (must be 26.0+)
xcodebuild -version

# Check for Apple Silicon
uname -m  # must output "arm64"
```

### Step 1: Install XcodeGen

```bash
# XcodeGen generates the .xcodeproj from project.yml
# This avoids committing .xcodeproj to git (prevents merge conflicts)
brew install xcodegen

# Verify
xcodegen --version
```

### Step 2: Clone and Generate Project

```bash
git clone https://github.com/Jinsong-Zhou/subflow.git
cd subflow

# Generate Xcode project from project.yml
xcodegen generate
# Expected output: "Created project at .../SubFlow.xcodeproj"
```

### Step 3: Build

```bash
# Build the app (Release configuration, no code signing for CI)
xcodebuild build \
  -project SubFlow.xcodeproj \
  -scheme SubFlow \
  -destination 'platform=macOS' \
  -configuration Debug

# Expected output: "** BUILD SUCCEEDED **"
```

**If the build fails** with dependency resolution errors, Xcode needs to resolve Swift packages first:

```bash
xcodebuild -resolvePackageDependencies -project SubFlow.xcodeproj
# Then retry the build command above
```

### Step 4: Run Tests

```bash
xcodebuild test \
  -project SubFlow.xcodeproj \
  -scheme SubFlowTests \
  -destination 'platform=macOS'

# Expected output: "Test run with 84 tests in 2 suites passed"
# Expected output: "** TEST SUCCEEDED **"
```

### Step 5: Run the App

```bash
# Find the built app
APP_PATH=$(xcodebuild build \
  -project SubFlow.xcodeproj \
  -scheme SubFlow \
  -destination 'platform=macOS' \
  -configuration Debug \
  -showBuildSettings 2>/dev/null \
  | grep ' BUILT_PRODUCTS_DIR =' \
  | sed 's/.*= //')

# Launch
open "$APP_PATH/SubFlow.app"
```

**First launch requirements:**
1. Grant **Screen Recording** permission when prompted (System Settings > Privacy & Security > Screen Recording)
2. On first recording start, `ModelDownloader` fetches the eight Moonshine `.ort` files (~157 MB Small / ~303 MB Medium total) directly from the official upstream CDN at `https://download.moonshine.ai/model/<model-id>/quantized/<file>` — the same endpoint Moonshine's own `pip install moonshine-voice && python -m moonshine_voice.download` tool uses. A progress window appears during the one-time download, then the files are cached under `~/Library/Application Support/SubFlow/MoonshineModels/<model-id>/` for all subsequent launches. No action required from contributors — SubFlow does not mirror these weights.
3. May need to restart the app after granting Screen Recording permission

### Step 6: Remote Control (for Automation)

SubFlow supports file-based remote control for automated testing:

```bash
# Toggle recording on/off (polls every 500ms)
touch /tmp/tc-toggle

# Check logs
tail -f ~/Library/Logs/SubFlow.log
```

### Troubleshooting

**Build fails with Swift package resolution errors** — run once, then retry:
```bash
xcodebuild -resolvePackageDependencies -project SubFlow.xcodeproj
```

**First-launch model download fails** — SubFlow pulls the Moonshine weights from `download.moonshine.ai` and retries each file three times with exponential backoff, which covers most transient network hiccups. If it still fails, two common causes:

- **Shell proxy vs system proxy.** `URLSession` reads the *system-level* proxy settings (System Settings → Network → your network → Details → Proxies), not `HTTP_PROXY` / `HTTPS_PROXY` shell environment variables. If your proxy works from `curl` but not from SubFlow, it's probably only configured at the shell level.
- **Connectivity to `download.moonshine.ai`.** Quick check: `curl -sI https://download.moonshine.ai/model/medium-streaming-en/quantized/adapter.ort | head -1` should return `HTTP/2 200`. If it hangs or fails, the issue is between your network and Moonshine's CDN (hosted on Google Cloud).

**"Developer cannot be verified" on launch** — you built SubFlow locally, so it is signed with your own Apple ID's Personal Team; macOS should not block it. If you copied the built `.app` to another machine, that Team is untrusted there — either rebuild on that machine, or right-click → **Open** once to bypass Gatekeeper.

## Project Structure

```
subflow/
├── project.yml                  # XcodeGen project definition (THE source of truth)
├── CLAUDE.md                    # AI agent project context and architecture notes
├── scripts/
│   └── create-dmg.sh            # Build + package into .dmg
├── .github/workflows/
│   └── release.yml              # CI: tag push → build → GitHub Release
│
├── SubFlow/                     # App source code
│   ├── SubFlowApp.swift         # @main, AppDelegate, window management
│   ├── Models/
│   │   ├── CaptionEntry.swift   # Bilingual caption data (EN + ZH + timestamp)
│   │   └── CaptionSettings.swift # User prefs (panelWidth, fontSize, modelId)
│   ├── ViewModels/
│   │   └── CaptionViewModel.swift # Core state machine (~250 lines)
│   ├── Views/
│   │   ├── FloatingCaptionView.swift  # Zoom-style scrolling subtitle overlay
│   │   ├── MainWindowView.swift       # Transcript history window
│   │   ├── MenuBarView.swift          # Menu bar popover
│   │   └── SettingsView.swift         # Settings panel (width, font, model)
│   ├── Services/
│   │   ├── AudioCaptureService.swift          # ScreenCaptureKit audio capture
│   │   ├── MoonshineTranscriptionService.swift # On-device ASR
│   │   └── TranslationService.swift           # Apple Translation wrapper
│   ├── Utilities/
│   │   ├── AppLogger.swift      # ~/Library/Logs/SubFlow.log
│   │   └── HotkeyManager.swift  # Global Cmd+Shift+T
│   └── Windows/
│       └── FloatingPanel.swift  # NSPanel (floating, transparent, resizable)
│
└── SubFlowTests/                # 76 tests
    ├── CaptionViewModelTests.swift
    ├── EndToEndTests.swift
    ├── SubFlowTests.swift
    └── ...
```

## Data Flow

```
System Audio → ScreenCaptureKit → 16kHz Float samples
    → Moonshine ASR (Neural Engine, ~500ms chunks)
    → onTextChanged: English preview (streaming)
    → onLineCompleted: full English sentence
        → Apple Translation → Chinese
        → Display complete EN + ZH pair
        → After reading time → scroll to history
```

## Usage

### Quick Start

1. Launch SubFlow — a caption bubble icon appears in the menu bar
2. Click the icon and press **Start** (or press `Cmd+Shift+T`)
3. Play any English audio (YouTube, podcast, meeting, etc.)
4. Bilingual subtitles appear in the floating overlay at the bottom of your screen
5. Scroll up in the subtitle panel to review previous captions

### Controls

| Action | Method |
|--------|--------|
| Start/Stop recording | `Cmd+Shift+T` or menu bar > Start/Stop |
| Open transcript | Menu bar > Open Transcript |
| Open settings | Menu bar > Settings... |
| Move subtitle panel | Drag the panel background |
| Resize subtitle panel | Drag the panel edges |
| Scroll history | Mouse wheel on the subtitle panel |
| Quit | Menu bar > Quit |

### Settings

- **Panel Width** — 400pt to 1000pt (default: 620pt)
- **Font Size** — 10pt to 24pt (default: 15pt)
- **ASR Model** — Small (faster) or Medium (more accurate, default)

## Privacy

All processing happens on-device:
- **Audio** — Captured and processed locally, never sent anywhere
- **Translation** — Apple's on-device Translation framework
- **No analytics, no telemetry, no network requests** (except the one-time ASR model download from Moonshine's official upstream CDN on first launch)
- **Logs** — `~/Library/Logs/SubFlow.log`, cleared on each launch

## Known Limitations

- English-only speech recognition (Moonshine ASR)
- Translation: English → Simplified Chinese only
- Requires macOS 26.0+ and Apple Silicon
- No binary distribution — see [Installation](#installation) to build from source

## License

[MIT](LICENSE)
