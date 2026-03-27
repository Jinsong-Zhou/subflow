import Testing
import AppKit
@testable import TranslatedCaption

@Test @MainActor func floatingPanelIsTransparent() {
    let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200))
    #expect(panel.isOpaque == false)
    #expect(panel.backgroundColor == .clear)
}

@Test @MainActor func floatingPanelIsFloatingLevel() {
    let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200))
    #expect(panel.level == .floating)
}

@Test @MainActor func floatingPanelIsMovableByBackground() {
    let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200))
    #expect(panel.isMovableByWindowBackground)
}

@Test @MainActor func floatingPanelDoesNotHideOnDeactivate() {
    let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200))
    #expect(panel.hidesOnDeactivate == false)
}

@Test @MainActor func floatingPanelHasShadow() {
    let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200))
    #expect(panel.hasShadow)
}

@Test @MainActor func floatingPanelCanJoinAllSpaces() {
    let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200))
    #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
}
