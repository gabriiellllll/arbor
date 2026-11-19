import AppKit
import SwiftUI

/// Sidebar, canvas and collapsible inspector.
@MainActor
final class MainSplitViewController: NSSplitViewController {
    let sidebar = SidebarViewController()
    let canvas = CanvasViewController()
    private let inspectorModel = InspectorModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        addSplitViewItem(sidebarItem)

        addSplitViewItem(NSSplitViewItem(viewController: canvas))

        let inspector = NSHostingController(rootView: InspectorView(model: inspectorModel))
        inspector.sizingOptions = []
        let inspectorItem = NSSplitViewItem(inspectorWithViewController: inspector)
        inspectorItem.minimumThickness = 220
        addSplitViewItem(inspectorItem)

        sidebar.onOpen = { [weak self] url, color in self?.canvas.openRoot(url, colorIndex: color) }
        canvas.onInspectedItemChange = { [weak self] item in self?.inspectorModel.item = item }
    }
}
