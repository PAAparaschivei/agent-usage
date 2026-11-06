import Foundation
import XCTest
@testable import AgentUsageCore

final class AgentUsageCoreTests: XCTestCase {
    func testMockSnapshotContainsTheThreeApprovedProviders() {
        let snapshot = MockSnapshot.make()
        XCTAssertEqual(snapshot.providers.map(\.provider), [.claude, .codex, .grok])
    }

    func testWeeklyWindowIsSelectedInsteadOfTheFirstWindow() {
        let claude = MockSnapshot.make().provider(.claude)
        XCTAssertEqual(claude?.primaryWindow?.id, "weekly")
        XCTAssertEqual(claude?.weeklyWindow?.id, "weekly")

        let reordered = ProviderSnapshot(
            provider: .claude,
            capturedAt: .now,
            state: .fresh,
            source: "Fixture",
            plan: nil,
            windows: [
                UsageWindow(id: "5h", label: "5-hour", usedPercent: 10, resetsAt: nil),
                UsageWindow(id: "7d", label: "Weekly", usedPercent: 20, resetsAt: nil),
            ]
        )
        XCTAssertEqual(reordered.primaryWindow?.id, "5h")
        XCTAssertEqual(reordered.weeklyWindow?.id, "7d")
    }

    func testRemainingValueIsClamped() {
        XCTAssertEqual(UsageMetricMode.left.value(for: 72), 28)
        XCTAssertEqual(UsageMetricMode.left.value(for: 120), 0)
        XCTAssertEqual(UsageMetricMode.used.value(for: -4), 0)
    }

    func testExpiredOrCachedUsageIsNeverPresentedAsCurrent() {
        let now = Date(timeIntervalSince1970: 1_789_418_000)
        let provider = ProviderSnapshot(provider: .codex, capturedAt: now, state: .fresh,
            source: "fixture", plan: nil, windows: [
                UsageWindow(id: "7d", label: "Weekly", usedPercent: 17, resetsAt: now.addingTimeInterval(600))
            ])
        XCTAssertEqual(provider.statusValue(mode: .left, now: now), "83%")
        XCTAssertEqual(provider.statusValue(mode: .left, now: now.addingTimeInterval(600)), "—")
        XCTAssertEqual(provider.aged(now: now, force: true).statusValue(mode: .left, now: now), "—")
        let noReset = ProviderSnapshot(provider: .grok, capturedAt: now, state: .fresh,
            source: "fixture", plan: nil, windows: [
                UsageWindow(id: "current", label: "Current period", usedPercent: 20, resetsAt: nil)
            ])
        XCTAssertEqual(noReset.statusValue(mode: .left, now: now), "80%")
        XCTAssertEqual(noReset.statusValue(mode: .left, now: now.addingTimeInterval(901)), "—")
    }

    func testSnapshotStoreRoundTripsAtomically() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let appStore = SnapshotStore(directory: directory)
        let widgetStore = SnapshotStore(directory: directory)
        let expected = MockSnapshot.make(now: Date(timeIntervalSince1970: 1_788_000_000))
        try appStore.write(expected)
        XCTAssertEqual(try widgetStore.read(), expected)
    }

    func testFormattingPreservesResetAndFreshnessMeaning() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        XCTAssertEqual(UsageText.age(now.addingTimeInterval(-125), now: now), "Updated 2m ago")
        XCTAssertEqual(UsageText.reset(now.addingTimeInterval(-1), now: now), "Update needed")
        XCTAssertEqual(UsageText.reset(now.addingTimeInterval(3_900), now: now), "Resets in 1h 5m")
    }

    func testAlertPolicySelectsOneNewThreshold() {
        XCTAssertNil(UsageAlertPolicy.nextThreshold(leftPercent: 21, alreadySent: []))
        XCTAssertEqual(UsageAlertPolicy.nextThreshold(leftPercent: 15, alreadySent: []), 20)
        XCTAssertEqual(UsageAlertPolicy.nextThreshold(leftPercent: 8, alreadySent: [20]), 10)
        XCTAssertEqual(UsageAlertPolicy.nextThreshold(leftPercent: 4, alreadySent: []), 5)
        XCTAssertNil(UsageAlertPolicy.nextThreshold(leftPercent: 4, alreadySent: [20, 10, 5]))
    }
}
