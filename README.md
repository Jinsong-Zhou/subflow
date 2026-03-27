# TranslatedCaption

A macOS menu bar app for real-time English speech transcription with Chinese translation.

## Features

- **Real-time speech-to-text** using Moonshine ASR (on-device, no cloud)
- **Instant English-to-Chinese translation** via Apple Translation framework
- **Floating subtitle overlay** with streaming bilingual captions
- **Menu bar integration** with global hotkey (Cmd+Shift+T)
- **Multiple ASR models** — Small (~157MB, ~73ms) / Medium (~303MB, ~107ms)
- **Configurable** panel width, font size, and model selection

## Requirements

- macOS 26.0 or later
- Screen Recording permission (for system audio capture)

## Installation

1. Download the latest `.dmg` from [Releases](../../releases)
2. Open the DMG and drag **TranslatedCaption** to `/Applications`
3. On first launch, right-click the app and select **Open** (or allow in System Settings > Privacy & Security)
4. Grant Screen Recording permission when prompted

> **Note:** This app is not signed with an Apple Developer ID certificate.
> macOS will show a security warning on first launch. This is expected for
> open-source software distributed outside the Mac App Store.

## Usage

1. Click the caption bubble icon in the menu bar
2. Press **Start** or use **Cmd+Shift+T** to begin recording
3. The floating subtitle panel shows bilingual captions in real-time
4. Open **Settings** to adjust panel width, font size, and ASR model

## Building from Source

### Prerequisites

- macOS 26.0+
- Xcode 26.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Build

```bash
xcodegen generate
open TranslatedCaption.xcodeproj
# Build and run in Xcode (Cmd+R)
```

### Run Tests

```bash
xcodegen generate
xcodebuild test \
  -project TranslatedCaption.xcodeproj \
  -scheme TranslatedCaption \
  -destination 'platform=macOS'
```

## License

[MIT](LICENSE)
