# SubFlow Project Memory

## Project Overview

SubFlow is a macOS SwiftUI app for real-time caption translation. It captures system audio via ScreenCaptureKit, transcribes speech using Moonshine ASR (on-device), and translates EN→ZH-Hans using Apple's Translation framework. Captions are displayed in a floating transparent overlay panel (NSPanel).

- **GitHub repo**: `Jinsong-Zhou/subflow`
- **Test count**: 76 tests (all passing)
- **Project generation**: XcodeGen (`project.yml`)

## Architecture

- **@Observable + @MainActor**: `CaptionViewModel` is the central state holder
- **MoonshineTranscriptionService**: Wraps MoonshineVoice framework, streams ASR results via callbacks
  - `onTextChanged`: fires every ~500ms with COMPLETE current text (not incremental)
  - `onLineCompleted`: fires when a sentence is fully transcribed
- **TranslationService**: Wraps Apple `TranslationSession` for EN→ZH-Hans
- **AudioCaptureService**: Uses `SCStream` (ScreenCaptureKit) for system audio capture
- **FloatingPanel**: `NSPanel` subclass, always-on-top transparent overlay, user-resizable
- **FloatingCaptionView**: SwiftUI ScrollView with Zoom-style scrolling captions

## Key Design Decisions

### YouTube-Style Caption Pipeline (CaptionViewModel)
The pipeline is intentionally simple — ~30 lines of core logic:
1. `onTextChanged` → show streaming English preview (no Chinese, 0.7 opacity)
2. `onLineCompleted` → translate → show complete EN+ZH pair (0.95/0.9 opacity)
3. Next sentence arrives → old pair moves to history, new streaming takes over

**Generation counter** (`streamingGeneration`) prevents race conditions:
- Increments on every `onTextChanged`
- `onLineCompleted` snapshots the generation before awaiting translation
- If generation changed during translation → send result to history (don't overwrite display)
- This is the ONLY concurrency mechanism needed — no pendingCompletionText, no stable prefix

### Zoom-Style Scrolling Display (FloatingCaptionView)
- **ScrollView** contains all `captionHistory` + current streaming
- New captions appear at bottom, old captions scroll up naturally
- User can **mouse-scroll up** to read history
- Auto-scroll to bottom on new completed caption (0.5s easeOut)
- Streaming text updates: no animation (instant, avoids lag)
- No fade/crossfade/push transitions — pure natural scroll

### Bilingual Reading Time (CaptionViewModel)
- `estimateReadingTime(english:chinese:)` — `nonisolated static` pure function
- English: ~15 chars/sec, Chinese: ~8 chars/sec (denser information per character)
- Takes max of both, multiplied by 1.3 bilingual overhead
- Clamped to 2.5–10 seconds

### FloatingPanel
- Fixed width (from `CaptionSettings.panelWidth`), user-resizable height
- `.resizable` styleMask — user can drag edges to resize
- `minSize: 300×80`
- Positioned at screen bottom center, 60pt from bottom edge

### Model Migration
- `MoonshineTranscriptionService.load()` auto-migrates models from old path `TranslatedCaption/MoonshineModels/` to new `SubFlow/MoonshineModels/`

## File Structure

```
SubFlow/SubFlow/
├── SubFlowApp.swift
├── Models/
│   ├── CaptionEntry.swift
│   └── CaptionSettings.swift
├── Services/
│   ├── AudioCaptureService.swift
│   ├── MoonshineTranscriptionService.swift
│   └── TranslationService.swift
├── Utilities/
│   ├── AppLogger.swift
│   └── HotkeyManager.swift
├── ViewModels/
│   └── CaptionViewModel.swift
├── Views/
│   ├── FloatingCaptionView.swift
│   ├── MainWindowView.swift
│   ├── MenuBarView.swift
│   └── SettingsView.swift
└── Windows/
    └── FloatingPanel.swift

SubFlow/SubFlowTests/
├── AppLoggerTests.swift
├── CaptionEntryTests.swift
├── CaptionSettingsTests.swift
├── CaptionViewModelTests.swift  (readingTime + model switch tests)
├── EndToEndTests.swift          (YouTube-style caption flow tests)
├── FloatingPanelTests.swift
├── SubFlowTests.swift
└── TranslationServiceTests.swift
```

## Pitfalls & Lessons Learned

1. **Translation race condition**: `onLineCompleted` starts an async translation Task. If `onTextChanged` fires before translation completes, the old translation must NOT overwrite `streamingEnglish`. Solution: `streamingGeneration` counter — snapshot before await, check after.
2. **SwiftUI Text animation**: `.contentTransition(.numericText())` is ONLY for numeric changes. For streaming text, disable all animations with `.transaction { $0.animation = nil }`.
3. **Subtitle transition UX**: Crossfade/push transitions cause text overlap or jumping. Zoom-style ScrollView with natural scroll is the best UX for real-time subtitles.
4. **Panel sizing**: Dynamic panel height causes visual distraction. Fixed-size panel with ScrollView content is more comfortable.
5. **TCC permissions**: App needs Screen Recording permission for `SCStream`. Open System Settings → Privacy & Security → Screen Recording.
6. **Over-engineering ASR display**: Stable prefix diffing, streaming translation, timeout mechanisms all added complexity without improving UX. YouTube-style "wait for complete sentence" is simpler and better.
