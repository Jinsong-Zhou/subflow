整体架构如下：让我为你画一个架构图来概览整个项目。整理一下关键技术决策和项目结构：

**技术栈确认**

经过调研，有一个重要的调整建议：mlx-whisper 是 Python 库，没有 Swift 原生绑定。但 **WhisperKit** 是一个原生 Swift 包，基于 CoreML，专为 Apple Silicon 优化，支持实时流式转写，可以直接通过 SPM 引入，完美适配你选的 Swift 技术栈。精度和 mlx-whisper 同级（都是 Whisper 模型），但省去了 Python 桥接的复杂度。

**四个核心模块**

1. **系统音频捕获**：用 `ScreenCaptureKit`（macOS 13+）直接捕获系统音频，无需 BlackHole 等虚拟驱动。配合 `AVAudioEngine` 把音频转为 16kHz mono PCM buffer。

2. **语音识别**：WhisperKit 接收音频 buffer，实时输出英文文本。支持流式转写。

3. **翻译**：Apple Translation 框架基于 CoreML 模型在本地完成翻译，无需联网，通过 `.translationTask` 修饰符获取 `TranslationSession`，调用 `session.translate()` 把英文翻译成中文。注意：Translation API 目前只能通过 SwiftUI 触发，但你的 app 本身就是 SwiftUI，所以没问题。

4. **悬浮字幕窗**：用 `NSPanel`（`level: .floating`）做一个 always-on-top 的半透明字幕窗，显示英文原文 + 中文翻译。
