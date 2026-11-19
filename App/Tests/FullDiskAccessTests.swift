@testable import Arbor
import XCTest

final class FullDiskAccessTests: XCTestCase {
    private var defaults: UserDefaults!
    private var onboarding: AccessOnboarding!
    private let suite = "FullDiskAccessTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        onboarding = AccessOnboarding(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testReadableProbeMeansGranted() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(FullDiskAccess.status(probing: file.path), .granted)
    }

    func testUnreadableProbeMeansDenied() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(FullDiskAccess.status(probing: file.path), .denied)
    }

    func testMissingProbeIsUnknown() {
        XCTAssertEqual(FullDiskAccess.status(probing: "/nonexistent/\(UUID().uuidString)"), .unknown)
    }

    func testFirstRunWithoutAccessShowsOnboarding() {
        XCTAssertEqual(onboarding.prompt(for: .denied), .firstRun)
    }

    func testDismissedOnboardingStaysQuiet() {
        onboarding.dismiss()
        XCTAssertEqual(onboarding.prompt(for: .denied), .none)
    }

    func testLosingAccessAfterAGrantIsReported() {
        XCTAssertEqual(onboarding.prompt(for: .granted), .none)
        XCTAssertEqual(onboarding.prompt(for: .denied), .lost)
    }

    func testLossIsReportedEvenIfFirstRunWasDismissed() {
        onboarding.dismiss()
        XCTAssertEqual(onboarding.prompt(for: .granted), .none)
        XCTAssertEqual(onboarding.prompt(for: .denied), .lost)
    }

    func testUnknownStatusShowsNothing() {
        XCTAssertEqual(onboarding.prompt(for: .unknown), .none)
    }
}
