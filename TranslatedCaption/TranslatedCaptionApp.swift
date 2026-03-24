import SwiftUI
import Translation

@main
struct TranslatedCaptionApp: App {
    @State private var viewModel = CaptionViewModel()
    @State private var floatingPanel: FloatingPanel?
    @State private var hotkeyManager: HotkeyManager?
    @State private var translationConfig: TranslationSession.Configuration?

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(viewModel)
                .translationTask(translationConfig) { session in
                    viewModel.setTranslationSession(session)
                }
                .onAppear {
                    translationConfig = viewModel.translationService.configuration
                    setupFloatingPanel()
                    setupHotkey()
                }
                .onDisappear { teardown() }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 600, height: 500)
    }

    @MainActor
    private func setupFloatingPanel() {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 160)
        )

        let hostingView = NSHostingView(
            rootView: FloatingCaptionView()
                .environment(viewModel)
        )
        panel.contentView = hostingView

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 260
            let y = screenFrame.minY + 60
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        floatingPanel = panel
    }

    @MainActor
    private func setupHotkey() {
        let manager = HotkeyManager {
            Task { @MainActor in
                viewModel.toggleCapture()
            }
        }
        manager.register()
        hotkeyManager = manager
    }

    @MainActor
    private func teardown() {
        hotkeyManager?.unregister()
        floatingPanel?.close()
        viewModel.stopCapture()
    }
}
