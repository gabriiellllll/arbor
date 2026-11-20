@testable import DiskKit
import XCTest

final class MountedVolumesTests: XCTestCase {
    func testStartupVolumeIsListedFirst() throws {
        let volumes = MountedVolumes.current()
        let first = try XCTUnwrap(volumes.first)
        XCTAssertTrue(first.isRoot)
        XCTAssertEqual(first.url.path, "/")
        XCTAssertFalse(first.name.isEmpty)
    }

    func testOrderPutsRootFirstThenNames() {
        func volume(_ name: String, root: Bool = false) -> Volume {
            Volume(
                url: URL(fileURLWithPath: "/Volumes/\(name)"),
                name: name,
                isRoot: root,
                isRemovable: false,
                isInternal: true
            )
        }
        let ordered = MountedVolumes.ordered([
            volume("Zeta"),
            volume("disk10"),
            volume("Mac", root: true),
            volume("disk2"),
        ])
        XCTAssertEqual(ordered.map(\.name), ["Mac", "disk2", "disk10", "Zeta"])
    }
}
