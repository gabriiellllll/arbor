import AppKit
import CanvasKit

/// Back and Forward through the folders opened on the canvas.
extension CanvasViewController {
    func recordVisit(_ id: PanelID) {
        guard !isNavigatingHistory, let path = panels[id]?.url.path else { return }
        history.visit(path)
    }

    func goBack() {
        history.back().map(show)
    }

    func goForward() {
        history.forward().map(show)
    }

    /// Reveals the panel of `path`, reopening the folder as a root if it was closed.
    private func show(_ path: String) {
        isNavigatingHistory = true
        defer { isNavigatingHistory = false }
        if let id = panels.first(where: { $0.value.url.path == path })?.key {
            activate(id, reveal: true)
        } else {
            openRoot(URL(fileURLWithPath: path, isDirectory: true))
        }
    }
}
