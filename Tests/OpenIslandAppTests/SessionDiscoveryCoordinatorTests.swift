import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct SessionDiscoveryCoordinatorTests {
    @Test
    func codexRolloutTargetsExcludeHealthyRealtimeSessions() {
        let sessions = [
            codexSession(id: "covered", transcriptPath: "/tmp/covered.jsonl"),
            codexSession(id: "fallback", transcriptPath: "/tmp/fallback.jsonl"),
        ]

        let targets = SessionDiscoveryCoordinator.codexRolloutWatchTargets(
            for: sessions,
            healthyRealtimeCodexSessionIDs: ["covered"]
        )

        #expect(targets.map(\.sessionID) == ["fallback"])
    }

    @Test
    func codexRolloutTargetsResumeWhenRealtimeHealthExpires() {
        let sessions = [
            codexSession(id: "fallback", transcriptPath: "/tmp/fallback.jsonl"),
        ]

        let targets = SessionDiscoveryCoordinator.codexRolloutWatchTargets(
            for: sessions,
            healthyRealtimeCodexSessionIDs: []
        )

        #expect(targets.map(\.sessionID) == ["fallback"])
    }

    @Test
    func codexRolloutTargetsAllowCodexAppSessionsWhenRealtimeIsStale() {
        var session = codexSession(id: "app", transcriptPath: "/tmp/app.jsonl")
        session.isCodexAppSession = true

        let targets = SessionDiscoveryCoordinator.codexRolloutWatchTargets(
            for: [session],
            healthyRealtimeCodexSessionIDs: []
        )

        #expect(targets.map(\.sessionID) == ["app"])
    }

    @Test
    func codexRolloutTargetsSkipCodexAppSessionsWhenRealtimeIsHealthy() {
        var session = codexSession(id: "app", transcriptPath: "/tmp/app.jsonl")
        session.isCodexAppSession = true

        let targets = SessionDiscoveryCoordinator.codexRolloutWatchTargets(
            for: [session],
            healthyRealtimeCodexSessionIDs: ["app"]
        )

        #expect(targets.isEmpty)
    }

    @Test
    func codexAppFallbackSkipsOldUntrackedHistory() throws {
        let thread = try codexThread(id: "old", status: "notLoaded", updatedAt: 1_000)

        #expect(!CodexAppServerCoordinator.hasRecentUnsyncedFallbackCandidate(
            in: [thread],
            now: Date(timeIntervalSince1970: 2_000),
            isSessionTracked: { _ in false }
        ))
    }

    @Test
    func codexAppFallbackRunsForRecentUntrackedNonActiveThread() throws {
        let thread = try codexThread(id: "recent", status: "notLoaded", updatedAt: 1_950)

        #expect(CodexAppServerCoordinator.hasRecentUnsyncedFallbackCandidate(
            in: [thread],
            now: Date(timeIntervalSince1970: 2_000),
            isSessionTracked: { _ in false }
        ))
    }

    @Test
    func codexAppFallbackSkipsAlreadyTrackedThread() throws {
        let thread = try codexThread(id: "tracked", status: "notLoaded", updatedAt: 1_950)

        #expect(!CodexAppServerCoordinator.hasRecentUnsyncedFallbackCandidate(
            in: [thread],
            now: Date(timeIntervalSince1970: 2_000),
            isSessionTracked: { $0 == "tracked" }
        ))
    }
}

private func codexSession(id: String, transcriptPath: String) -> AgentSession {
    AgentSession(
        id: id,
        title: id,
        tool: .codex,
        phase: .running,
        summary: "Running",
        updatedAt: Date(timeIntervalSince1970: 1_000),
        codexMetadata: CodexSessionMetadata(transcriptPath: transcriptPath)
    )
}

private func codexThread(id: String, status: String, updatedAt: Int) throws -> CodexThread {
    let json = """
    {
      "id": "\(id)",
      "cwd": "/tmp/open-island",
      "name": null,
      "preview": "",
      "modelProvider": "openai",
      "createdAt": 1000,
      "updatedAt": \(updatedAt),
      "ephemeral": false,
      "path": "/tmp/rollout-\(id).jsonl",
      "status": { "type": "\(status)" },
      "source": "vscode",
      "turns": null
    }
    """

    return try JSONDecoder().decode(CodexThread.self, from: Data(json.utf8))
}
