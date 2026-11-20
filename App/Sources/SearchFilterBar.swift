import AppKit
import IndexKit

/// Filter pop-ups of a search panel: kind, size, date, tag, volume. Item 0 of each is "any".
@MainActor
final class SearchFilterBar: NSStackView {
    var onChange: (() -> Void)?

    private let kind = NSPopUpButton()
    private let size = NSPopUpButton()
    private let age = NSPopUpButton()
    private let tagPopUp = NSPopUpButton()
    private let volume = NSPopUpButton()
    private let tags: [String]
    private let roots: [IndexRoot]

    init(tags: [String], roots: [IndexRoot]) {
        self.tags = tags
        self.roots = roots
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 4
        let sizeFormat = { (bytes: Int64) in
            String(localized: "Over \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
        }
        fill(kind, String(localized: "Any Kind"), SearchSpec.KindFilter.allCases.map(Self.title), "kind")
        fill(size, String(localized: "Any Size"), SearchSpec.minSizes.map(sizeFormat), "size")
        fill(age, String(localized: "Any Date"), SearchSpec.Age.allCases.map(Self.title), "date")
        fill(tagPopUp, String(localized: "Any Tag"), tags, "tag")
        fill(volume, String(localized: "All Volumes"), roots.map { FileManager.default.displayName(atPath: $0.path) },
             "volume")
        for (index, name) in tags.enumerated() {
            tagPopUp.item(at: index + 1)?.image = TagColors.dotImage(TagColors.color(for: name))
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ spec: SearchSpec) {
        kind.selectItem(at: spec.kind.flatMap { SearchSpec.KindFilter.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        size.selectItem(at: spec.minSize.flatMap { SearchSpec.minSizes.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        age.selectItem(at: spec.age.flatMap { SearchSpec.Age.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        tagPopUp.selectItem(at: spec.tag.flatMap { tags.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        volume.selectItem(at: spec.rootID.flatMap { id in roots.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0)
    }

    func apply(to spec: SearchSpec) -> SearchSpec {
        var spec = spec
        spec.kind = Self.choice(kind, SearchSpec.KindFilter.allCases)
        spec.minSize = Self.choice(size, SearchSpec.minSizes)
        spec.age = Self.choice(age, SearchSpec.Age.allCases)
        spec.tag = Self.choice(tagPopUp, tags)
        spec.rootID = Self.choice(volume, roots)?.id
        return spec
    }

    private static func choice<Value>(_ popUp: NSPopUpButton, _ values: [Value]) -> Value? {
        let index = popUp.indexOfSelectedItem - 1
        return values.indices.contains(index) ? values[index] : nil
    }

    private func fill(_ popUp: NSPopUpButton, _ any: String, _ titles: [String], _ identifier: String) {
        popUp.addItems(withTitles: [any] + titles)
        popUp.controlSize = .small
        popUp.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        popUp.target = self
        popUp.action = #selector(changed)
        popUp.setAccessibilityIdentifier("filter.\(identifier)")
        popUp.isHidden = titles.isEmpty
        addArrangedSubview(popUp)
    }

    @objc private func changed() {
        onChange?()
    }

    private static func title(_ kind: SearchSpec.KindFilter) -> String {
        switch kind {
        case .folders: String(localized: "Folders")
        case .files: String(localized: "Files")
        case .images: String(localized: "Images")
        case .documents: String(localized: "Documents")
        case .audio: String(localized: "Audio")
        case .video: String(localized: "Video")
        case .archives: String(localized: "Archives")
        case .code: String(localized: "Code")
        }
    }

    private static func title(_ age: SearchSpec.Age) -> String {
        switch age {
        case .day: String(localized: "Past Day")
        case .week: String(localized: "Past Week")
        case .month: String(localized: "Past Month")
        case .year: String(localized: "Past Year")
        }
    }
}
