import AgentUsageCore
@testable import AgentUsageCollectors
import Foundation
import XCTest

final class CollectorAdapterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_210_000)

    func testClaudeStatusLineFixture() throws {
        let data = Data(#"""
        {
          "captured_at": 1788209700,
          "model": "Opus 5",
          "rate_limits": {
            "five_hour": {"used_percentage": 18, "resets_at": 1788213600},
            "seven_day": {"used_percentage": 31, "resets_at": 1788750000}
          }
        }
        """#.utf8)

        let snapshot = try ClaudeStatusAdapter.decode(data: data, now: now)
        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(snapshot.state, .fresh)
        XCTAssertNil(snapshot.plan)
        XCTAssertEqual(snapshot.windows.map(\.label), ["5-hour", "Weekly"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [18, 31])
    }

    func testCodexAppServerFixture() throws {
        let data = Data(#"""
        {
          "id": 2,
          "result": {
            "rateLimits": {
              "primary": {"usedPercent": 30, "windowDurationMins": 10080, "resetsAt": 1788757394},
              "secondary": null,
              "planType": "prolite"
            },
            "rateLimitsByLimitId": null
          }
        }
        """#.utf8)

        let snapshot = try CodexAdapter.decode(responseData: data, now: now)
        XCTAssertEqual(snapshot.provider, .codex)
        XCTAssertEqual(snapshot.plan, "Plus")
        XCTAssertEqual(snapshot.windows.first?.label, "Weekly")
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 30)
    }

    func testCodexAdapterReadsLimitsOverStdio() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("codex-fixture")
        let commands = #"""
        #!/bin/sh
        set -eu
        IFS= read -r request
        case "$request" in *'"method":"initialize"'*) ;; *) exit 1 ;; esac
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r request
        case "$request" in *'"method":"initialized"'*) ;; *) exit 1 ;; esac
        IFS= read -r request
        case "$request" in *'"method":"account/rateLimits/read"'*) ;; *) exit 1 ;; esac
        printf '%s\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":27,"windowDurationMins":300}}}}'
        """#
        try Data(commands.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        let result = try await CodexAdapter(executableURL: script).load(now: now)
        XCTAssertEqual(result.windows.first?.usedPercent, 27)
        XCTAssertEqual(result.windows.first?.label, "5-hour")
    }

    func testCodexExitedLauncherReportsSourceUnavailable() async {
        let adapter = CodexAdapter(executableURL: URL(fileURLWithPath: "/usr/bin/false"))
        do {
            _ = try await adapter.load(now: now)
            XCTFail("An exited launcher cannot return a snapshot")
        } catch {
            XCTAssertEqual(error as? ProviderCollectionError, .sourceUnavailable)
        }
    }

    func testMalformedProviderResponsesAreRejected() {
        let malformed = Data("{}".utf8)
        XCTAssertThrowsError(try ClaudeStatusAdapter.decode(data: malformed, now: now))
        XCTAssertThrowsError(try CodexAdapter.decode(responseData: malformed, now: now))
    }

    func testGrokReadsLocalBillingLog() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let logURL = directory.appendingPathComponent("unified.jsonl")
        let line = #"{"ts":"2026-08-31T20:55:00Z","msg":"billing: fetched credits config","ctx":{"subscriptionTier":"SuperGrok","config":{"creditUsagePercent":20,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-09-06T12:20:01Z"}}}}"#
        try Data((line + "\n").utf8).write(to: logURL)

        let snapshot = try await GrokAdapter(logURL: logURL).load(now: now)
        XCTAssertEqual(snapshot.state, .fresh)
        XCTAssertEqual(snapshot.plan, "SuperGrok")
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 20)
    }

    func testCoordinatorKeepsLastGoodSnapshot() async {
        let previous = MockSnapshot.make(now: now.addingTimeInterval(-3_600))
        let coordinator = UsageCollectionCoordinator(adapters: [
            FailingAdapter(provider: .claude),
            FailingAdapter(provider: .codex),
            FailingAdapter(provider: .grok),
        ])

        let next = await coordinator.collect(previous: previous, now: now)
        XCTAssertTrue(next.providers.allSatisfy { $0.state == .stale })
        XCTAssertEqual(
            next.provider(.codex)?.windows,
            previous.provider(.codex)?.windows
        )
    }
}

private struct FailingAdapter: ProviderAdapter {
    let provider: ProviderID

    func load(now: Date) async throws -> ProviderSnapshot {
        throw ProviderCollectionError.sourceUnavailable
    }
}
