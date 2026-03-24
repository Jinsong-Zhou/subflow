import SwiftUI
import Translation

@main
struct TranslatedCaptionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var viewModel = CaptionViewModel()
    private var floatingPanel: FloatingPanel?
    private var hotkeyManager: HotkeyManager?
    private var popover = NSPopover()
    private var translationWindow: NSWindow?
    private var notificationObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.clear()
        AppLogger.log("App launched. Log file: \(AppLogger.path)")

        setupStatusItem()
        setupFloatingPanel()
        setupHotkey()
        setupRemoteControl()
        updateFloatingPanelWithTranslation()

        // Pre-load WhisperKit model in background so Start is instant
        viewModel.preloadModel()
    }

    /// Listen for distributed notification to toggle recording (for testing/automation)
    private func setupRemoteControl() {
        // File-based remote control: `touch /tmp/tc-toggle` to toggle recording
        AppLogger.log("Setting up remote control")
        let vm = viewModel
        Task {
            let togglePath = "/tmp/tc-toggle"
            try? FileManager.default.removeItem(atPath: togglePath)
            AppLogger.log("Remote control loop started, watching \(togglePath)")
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if FileManager.default.fileExists(atPath: togglePath) {
                    try? FileManager.default.removeItem(atPath: togglePath)
                    AppLogger.log("Received file toggle trigger")
                    await MainActor.run { vm.toggleCapture() }
                }
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "captions.bubble", accessibilityDescription: "TranslatedCaption")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let menuBarView = MenuBarView(
            onToggleCapture: { [weak self] in self?.viewModel.toggleCapture() },
            onOpenTranscript: { [weak self] in self?.openTranscriptWindow() },
            onQuit: { [weak self] in
                self?.viewModel.stopCapture()
                NSApp.terminate(nil)
            }
        )
        .environment(viewModel)

        popover.contentSize = NSSize(width: 240, height: 180)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: menuBarView)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: viewModel.isRecording ? "captions.bubble.fill" : "captions.bubble",
                accessibilityDescription: "TranslatedCaption"
            )
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func setupFloatingPanel() {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 200)
        )

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 310
            let y = screenFrame.minY + 60
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        floatingPanel = panel
    }

    private func updateFloatingPanelWithTranslation() {
        let config = viewModel.translationService.configuration
        let content = FloatingCaptionView()
            .environment(viewModel)
            .translationTask(config) { [weak self] session in
                self?.viewModel.setTranslationSession(session)
            }

        floatingPanel?.contentView = NSHostingView(rootView: content)
    }

    private func setupHotkey() {
        let manager = HotkeyManager {
            Task { @MainActor in
                self.viewModel.toggleCapture()
            }
        }
        manager.register()
        hotkeyManager = manager
    }

    private var transcriptWindow: NSWindow?

    private func openTranscriptWindow() {
        if let existing = transcriptWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TranslatedCaption"
        window.contentView = NSHostingView(
            rootView: MainWindowView()
                .environment(viewModel)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        transcriptWindow = window
    }
}
