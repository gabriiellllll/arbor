import AppKit

/// The infinite canvas: a magnifiable scroll view over a very large document whose
/// coordinates are canvas coordinates (y down, origin in the middle), with the background
/// pattern drawn behind it.
///
/// Pan: trackpad / scroll wheel, space + drag, or the hand tool. Zoom: pinch, or
/// `zoomIn()` / `zoomOut()` / `resetZoom()`.
@MainActor
public final class CanvasView: NSView {
    // ponytail: 100 000 pt each way is effectively infinite; recenter the document if users ever hit the edge.
    /// Half the canvas size in each direction.
    public static let extent: CGFloat = 100_000

    /// Add panels here, with frames in canvas coordinates.
    public let documentView = CanvasDocumentView()
    /// Branch layers live here, below the panels.
    public let branchesView = BranchesView()

    /// Called whenever the visible area or the zoom changes.
    public var onViewportChange: (() -> Void)?

    public var background: CanvasBackground = .dots {
        didSet { backgroundView.style = background }
    }

    /// When active, dragging anywhere pans the canvas.
    public var isHandToolActive = false {
        didSet { updatePanningMode() }
    }

    public var magnification: CGFloat {
        scrollView.magnification
    }

    /// The part of the canvas currently on screen, in canvas coordinates.
    public var visibleCanvasRect: CGRect {
        scrollView.contentView.bounds
    }

    private let scrollView = NSScrollView()
    private let backgroundView = CanvasBackgroundView()
    private var isSpaceHeld = false {
        didSet { updatePanningMode() }
    }

    private var keyMonitor: Any?
    private var boundsObserver: NSObjectProtocol?

    override public init(frame: NSRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setUp() {
        backgroundView.frame = bounds
        backgroundView.autoresizingMask = [.width, .height]
        addSubview(backgroundView)

        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.allowsMagnification = true
        scrollView.minMagnification = Zoom.minimum
        scrollView.maxMagnification = Zoom.maximum
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        addSubview(scrollView)

        // Frame and bounds share the same origin so clip view, document and canvas
        // coordinates are all identical.
        let extent = Self.extent
        let canvasRect = CGRect(x: -extent, y: -extent, width: extent * 2, height: extent * 2)
        documentView.frame = canvasRect
        documentView.bounds = canvasRect
        branchesView.frame = documentView.bounds
        documentView.addSubview(branchesView)
        documentView.onPan = { [weak self] delta in self?.pan(byViewDelta: delta) }
        scrollView.documentView = documentView

        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.viewportDidChange() }
        }
        scroll(toCanvasOrigin: CGPoint(x: -40, y: -40))
    }

    // MARK: - Zoom

    public func zoomIn() {
        setZoom(Zoom.stepIn(from: magnification))
    }

    public func zoomOut() {
        setZoom(Zoom.stepOut(from: magnification))
    }

    public func resetZoom() {
        setZoom(1)
    }

    /// Zooms around the center of the visible area.
    public func setZoom(_ scale: CGFloat, animated: Bool = true) {
        let visible = visibleCanvasRect
        let center = CGPoint(x: visible.midX, y: visible.midY)
        guard animated else {
            scrollView.setMagnification(Zoom.clamped(scale), centeredAt: center)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            scrollView.animator().setMagnification(Zoom.clamped(scale), centeredAt: center)
        }
    }

    // MARK: - Scrolling

    /// Scrolls so `rect` (canvas coordinates) is visible, moving as little as possible.
    /// With a `context` rectangle, keeps it visible too when both fit.
    public func reveal(_ rect: CGRect, context: CGRect? = nil, animated: Bool = true) {
        let margin = 40 / magnification
        let origin = context.map {
            Reveal.origin(revealing: rect, withContext: $0, in: visibleCanvasRect, margin: margin)
        } ?? Reveal.origin(revealing: rect, in: visibleCanvasRect, margin: margin)
        scroll(toCanvasOrigin: origin, animated: animated)
    }

    public func scroll(toCanvasOrigin origin: CGPoint, animated: Bool = false) {
        let clip = scrollView.contentView
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.allowsImplicitAnimation = true
                clip.animator().setBoundsOrigin(origin)
            }
        } else {
            clip.setBoundsOrigin(origin)
        }
        scrollView.reflectScrolledClipView(clip)
    }

    private func pan(byViewDelta delta: CGVector) {
        let origin = visibleCanvasRect.origin
        scroll(toCanvasOrigin: CGPoint(
            x: origin.x - delta.dx / magnification,
            y: origin.y - delta.dy / magnification
        ))
    }

    override public func layout() {
        super.layout()
        // Resizing the clip view does not always post a bounds change.
        viewportDidChange()
    }

    private func viewportDidChange() {
        backgroundView.canvasRect = visibleCanvasRect
        backgroundView.magnification = magnification
        onViewportChange?()
    }

    // MARK: - Space + drag

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        guard window != nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.consumeSpace(event) ?? false }
            return consumed ? nil : event
        }
        viewportDidChange()
    }

    /// Holding space turns drags into panning, unless the user is typing text.
    private func consumeSpace(_ event: NSEvent) -> Bool {
        guard event.window === window, event.charactersIgnoringModifiers == " ",
              event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask),
              !(window?.firstResponder is NSText) else { return false }
        isSpaceHeld = event.type == .keyDown
        return true
    }

    private func updatePanningMode() {
        documentView.isPanning = isHandToolActive || isSpaceHeld
    }
}
