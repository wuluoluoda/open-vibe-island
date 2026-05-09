import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct AppModelPersistenceScopeTests {
    @Test
    func sessionStartedScopesToEventTool() {
        let event = AgentEvent.sessionStarted(SessionStarted(
            sessionID: "codex",
            title: "Codex",
            tool: .codex,
            summary: "Running",
            timestamp: Date(timeIntervalSince1970: 1_000)
        ))

        #expect(AppModel.persistenceScopes(for: event, session: nil) == [.codex])
    }

    @Test
    func metadataEventsScopeToTheirStores() {
        #expect(AppModel.persistenceScopes(
            for: .claudeSessionMetadataUpdated(ClaudeSessionMetadataUpdated(
                sessionID: "claude",
                claudeMetadata: ClaudeSessionMetadata(),
                timestamp: Date(timeIntervalSince1970: 1_000)
            )),
            session: nil
        ) == [.claude])

        #expect(AppModel.persistenceScopes(
            for: .openCodeSessionMetadataUpdated(OpenCodeSessionMetadataUpdated(
                sessionID: "opencode",
                openCodeMetadata: OpenCodeSessionMetadata(),
                timestamp: Date(timeIntervalSince1970: 1_000)
            )),
            session: nil
        ) == [.openCode])

        #expect(AppModel.persistenceScopes(
            for: .cursorSessionMetadataUpdated(CursorSessionMetadataUpdated(
                sessionID: "cursor",
                cursorMetadata: CursorSessionMetadata(),
                timestamp: Date(timeIntervalSince1970: 1_000)
            )),
            session: nil
        ) == [.cursor])
    }

    @Test
    func sessionEventsUseCurrentSessionToolWhenPayloadHasNoTool() {
        let event = AgentEvent.activityUpdated(SessionActivityUpdated(
            sessionID: "cursor",
            summary: "Running",
            phase: .running,
            timestamp: Date(timeIntervalSince1970: 1_000)
        ))
        let session = AgentSession(
            id: "cursor",
            title: "Cursor",
            tool: .cursor,
            phase: .running,
            summary: "Running",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(AppModel.persistenceScopes(for: event, session: session) == [.cursor])
    }

    @Test
    func unknownSessionFallsBackToAllStores() {
        let event = AgentEvent.activityUpdated(SessionActivityUpdated(
            sessionID: "missing",
            summary: "Running",
            phase: .running,
            timestamp: Date(timeIntervalSince1970: 1_000)
        ))

        #expect(AppModel.persistenceScopes(for: event, session: nil) == SessionPersistenceScope.all)
    }

    @Test
    func toolsWithoutPersistenceStoresDoNotScheduleKnownStores() {
        let event = AgentEvent.sessionStarted(SessionStarted(
            sessionID: "gemini",
            title: "Gemini",
            tool: .geminiCLI,
            summary: "Running",
            timestamp: Date(timeIntervalSince1970: 1_000)
        ))

        #expect(AppModel.persistenceScopes(for: event, session: nil).isEmpty)
    }
}
