import AppKit
import SwiftUI

/// Sidebar, canvas and collapsible inspector. Also switches workspaces: each workspace keeps
/// its own canvas, saved when leaving it and when the app quits.
@MainActor
final class MainSplitViewController: NSSplitViewController {
    let database: AppDatabase
    let sidebar: SidebarViewController
    let canvas = CanvasViewController()
    private let inspectorModel = InspectorModel()
    private(set) var currentWorkspace: Int64?

    init(database: AppDatabase) {
        self.database = database
        sidebar = SidebarViewController(database: database)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

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
        sidebar.onSwitchWorkspace = { [weak self] id in self?.switchWorkspace(to: id) }
        sidebar.onCreateWorkspace = { [weak self] in self?.createWorkspace() }
        sidebar.onDeleteWorkspace = { [weak self] id in self?.deleteWorkspace(id) }
        canvas.onInspectedItemChange = { [weak self] item in self?.inspectorModel.item = item }
        canvas.onAddFavorites = { [weak self] urls in self?.sidebar.addFavorites(urls, at: nil) }

        currentWorkspace = try? database.currentWorkspaceID()
        loadCurrentWorkspace()
    }

    // MARK: - Workspaces

    /// Saves the current workspace's canvas.
    func saveWorkspace() {
        guard let id = currentWorkspace, let data = try? JSONEncoder().encode(canvas.snapshot()) else { return }
        try? database.saveCanvas(data, for: id)
    }

    func switchWorkspace(to id: Int64) {
        guard id != currentWorkspace else { return }
        saveWorkspace()
        try? database.setCurrentWorkspace(id)
        currentWorkspace = id
        loadCurrentWorkspace()
        sidebar.reload()
    }

    @objc func createWorkspace() {
        let count = ((try? database.workspaces()) ?? []).count
        guard let workspace = try? database.createWorkspace(name: String(localized: "Workspace \(count + 1)")) else {
            return
        }
        switchWorkspace(to: workspace.id)
    }

    func deleteWorkspace(_ id: Int64) {
        guard ((try? database.workspaces()) ?? []).count > 1 else { return }
        try? database.deleteWorkspace(id)
        if id == currentWorkspace {
            currentWorkspace = try? database.currentWorkspaceID()
            loadCurrentWorkspace()
        }
        sidebar.reload()
    }

    private func loadCurrentWorkspace() {
        let data = currentWorkspace.flatMap { try? database.canvas(for: $0) }
        let snapshot = data.flatMap { try? JSONDecoder().decode(CanvasSnapshot.self, from: $0) } ?? CanvasSnapshot()
        canvas.restore(snapshot)
    }
}
