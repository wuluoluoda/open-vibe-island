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
    func codexRolloutTargetsSkipCodexAppSessions() {
        var session = codexSession(id: "app", transcriptPath: "/tmp/app.jsonl")
        session.isCodexAppSession = true

        let targets = SessionDiscoveryCoordinator.codexRolloutWatchTargets(
            for: [session],
            healthyRealtimeCodexSessionIDs: []
        )

        #expect(targets.isEmpty)
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
