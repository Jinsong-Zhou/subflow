# TranslatedCaption — Design Spec

A macOS app that captures system audio output, performs real-time English speech-to-text transcription, translates to Chinese, and displays bilingual subtitles in a floating overlay.

## Requirements

| Requirement | Decision |
|-------------|----------|
| App form | Standard window + floating subtitle overlay |
| Subtitle display | Hybrid: floating window shows recent 2-3 entries, main window shows full scrolling history |
| Audio source | System audio only (no microphone) |
| Target OS | macOS 26+ (Tahoe) |
| History | Session-only, in-memory, no persistence |
| Controls | Main window button + global hotkey (Cmd+Shift+T) |
| UI style | No emoji anywhere in the UI |

## Architecture

Single-process pipeline using Swift Concurrency (`AsyncStream`) to chain modules:

```
ScreenCaptureKit → AVAudioEngine(resample) → WhisperKit → Translation → UI
```

### Data Flow

```
┌─────────────────────────────────────────────────────┐
│                    TranslatedCaption                 │
│                                                     │
│  ┌──────────────┐    PCM Buffer     ┌────────────┐  │
│  │ AudioCapture │ ───AsyncStream──> │ WhisperKit │  │
│  │ Service      │   16kHz mono      │            │  │
│  └──────────────┘                   └─────┬──────┘  │
│                                           │ English  │
│                                           v          │
│                                    ┌──────────────┐  │
│                                    │ Translation  │  │
│                                    │ Service      │  │
│                                    └──────┬───────┘  │
│                                           │ Chinese  │
│                                           v          │
│                                    ┌──────────────┐  │
│                                    │ CaptionVM    │  │
│                                    │ (@Observable)│  │
│                                    └──┬────────┬──┘  │
│                                       │        │     │
│                              ┌────────v──┐ ┌───v─────────┐
│                              │ Main      │ │ Floating    │
│                              │ Window    │ │ Caption     │
│                              │ (history) │ │ (recent)    │
│                              └───────────┘ └─────────────┘
└─────────────────────────────────────────────────────┘
```

## Tech Stack

| Component | Technology | Notes |
|-----------|-----------|-------|
| Audio capture | ScreenCaptureKit + AVAudioEngine | System audio, resample to 16kHz mono Float32 |
| Speech recognition | WhisperKit (large-v3-turbo) | Swift-native, CoreML, Apple Silicon optimized |
| Translation | Apple Translation framework | Local/offline, `.translationTask` modifier |
| UI framework | SwiftUI + AppKit | SwiftUI views, NSPanel for floating window |
| State management | `@Observable` ViewModel | Swift Concurrency (async/await, AsyncStream) |
| Global hotkey | NSEvent global monitor | Cmd+Shift+T |

### Dependencies (SPM)

| Package | Purpose |
|---------|---------|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | Speech-to-text |

All other dependencies are system frameworks: ScreenCaptureKit, AVFoundation, Translation, SwiftUI, AppKit.

## Modules

### 1. AudioCaptureService

- `SCShareableContent.current` to enumerate capturable audio sources
- `SCStream` configured for system audio only (no microphone)
- `AVAudioEngine` resamples to 16kHz mono Float32 (WhisperKit input format)
- Outputs `AsyncStream<[Float]>` of audio buffers
- Requires Screen Recording permission on first use (system prompt)

### 2. TranscriptionService

- Loads WhisperKit model (`large-v3-turbo` — good accuracy/speed balance)
- Accumulates audio buffers (~3-5 seconds) before inference
- Outputs English text via `AsyncStream<String>`
- Supports streaming partial results

### 3. TranslationService

- Apple Translation framework via SwiftUI `.translationTask` modifier
- `TranslationSession` configured: source `.english`, target `.simplifiedChinese`
- Model downloaded automatically by the system on first use
- `session.translate(text)` returns Chinese translation

### 4. CaptionViewModel (@Observable)

State:
- `isRecording: Bool`
- `currentEnglish: String` — currently recognized English (streaming)
- `currentChinese: String` — current translation
- `captionHistory: [CaptionEntry]` — full session history (in-memory)
- `recentCaptions: [CaptionEntry]` — last 2-3 entries for floating window

Methods:
- `startCapture()` — start audio capture -> recognition -> translation pipeline
- `stopCapture()` — stop pipeline
- `toggleCapture()` — triggered by global hotkey

### 5. Data Model

```swift
struct CaptionEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let englishText: String
    let chineseText: String
}
```

## UI Design

### Floating Caption Window

- `NSPanel` with `level: .floating`, `styleMask: [.nonactivatingPanel]`
- Does not steal focus from other apps
- Draggable to reposition
- Visual style: **Minimal Dark**
  - Background: `rgba(0, 0, 0, 0.85)` with `NSVisualEffectView` blur
  - Border radius: 12px
  - English text: white (`rgba(255, 255, 255, 0.95)`), 15px
  - Chinese text: light blue (`rgba(120, 200, 255, 0.9)`), 14px
- Shows most recent 2-3 caption entries
- Old entries replaced as new ones arrive

### Main Window

- Standard `NSWindow` with SwiftUI content
- **Toolbar area:** record/stop button (green when recording) + hotkey hint label (`Cmd+Shift+T`)
- **Content area:** scrolling list of `CaptionEntry` items
  - Each entry: timestamp (small, dim) + English text (white) + Chinese text (light blue)
  - Auto-scrolls to bottom on new entries
- Dark appearance consistent with floating window

## Permissions

- `NSScreenCaptureUsageDescription` in Info.plist — required for ScreenCaptureKit audio capture
- App Sandbox must be disabled (ScreenCaptureKit system audio capture requires it)

## Project Structure

```
TranslatedCaption/
├── TranslatedCaptionApp.swift
├── Models/
│   └── CaptionEntry.swift
├── Services/
│   ├── AudioCaptureService.swift
│   ├── TranscriptionService.swift
│   └── TranslationService.swift
├── ViewModels/
│   └── CaptionViewModel.swift
├── Views/
│   ├── MainWindowView.swift
│   └── FloatingCaptionView.swift
├── Windows/
│   └── FloatingPanel.swift
└── Utilities/
    └── HotkeyManager.swift
```

## Out of Scope (v1)

- Microphone capture (own voice)
- Persistent history / export
- Multiple language pairs
- Menu bar mode
- Settings UI (model selection, font size, etc.)
- Auto-start on login
