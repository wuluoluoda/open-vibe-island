import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct CodexOperationalStatusTests {
    @Test
    func interruptedCompletionUsesInterruptedStatus() {
        var session = AgentSession(
            id: "codex-1",
            title: "Codex · repo",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Turn interrupted.",
            updatedAt: .now
        )
        session.lastTurnInterrupted = true

        let status = session.codexOperationalStatus(signals: .default)
        #expect(status == .interrupted)
    }

    @Test
    func stalledStatusRequiresRunningAliveAndThreshold() {
        let now = Date(timeIntervalSince1970: 20_000)
        var session = AgentSession(
            id: "codex-1",
            title: "Codex · repo",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: now.addingTimeInterval(-13 * 60)
        )
        session.isProcessAlive = true

        let signals = CodexOperationalStatusSignals(
            now: now,
            bridgeConnectionState: .connected,
            codexAppServerConnectionState: .connected,
            stalledThreshold: 12 * 60,
            loopSuspectedEnabled: false,
            loopRepeatCount: 0,
            loopSuspectedThreshold: 4,
            recentCompletionWindow: 20 * 60
        )
        #expect(session.codexOperationalStatus(signals: signals) == .stalled)
    }

    @Test
    func reconnectingStatusUsesBridgeSignalForLiveSessions() {
        let now = Date(timeIntervalSince1970: 20_000)
        var session = AgentSession(
            id: "codex-1",
            title: "Codex · repo",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: now
        )
        session.isProcessAlive = true

        let signals = CodexOperationalStatusSignals(
            now: now,
            bridgeConnectionState: .reconnecting,
            codexAppServerConnectionState: .connected,
            stalledThreshold: 12 * 60,
            loopSuspectedEnabled: false,
            loopRepeatCount: 0,
            loopSuspectedThreshold: 4,
            recentCompletionWindow: 20 * 60
        )
        #expect(session.codexOperationalStatus(signals: signals) == .reconnecting)
    }

    @Test
    func connectingStatusUsesBridgeSignalForLiveSessions() {
        let now = Date(timeIntervalSince1970: 20_000)
        var session = AgentSession(
            id: "codex-1",
            title: "Codex · repo",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: now
        )
        session.isProcessAlive = true

        let signals = CodexOperationalStatusSignals(
            now: now,
            bridgeConnectionState: .connecting,
            codexAppServerConnectionState: .connected,
            stalledThreshold: 12 * 60,
            loopSuspectedEnabled: false,
            loopRepeatCount: 0,
            loopSuspectedThreshold: 4,
            recentCompletionWindow: 20 * 60
        )
        #expect(session.codexOperationalStatus(signals: signals) == .connecting)
    }

    @Test
    func loopSuspectedRespectsThresholdAndSwitch() {
        let now = Date(timeIntervalSince1970: 20_000)
        var session = AgentSession(
            id: "codex-1",
            title: "Codex · repo",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: now
        )
        session.isProcessAlive = true

        let enabledSignals = CodexOperationalStatusSignals(
            now: now,
            bridgeConnectionState: .connected,
            codexAppServerConnectionState: .connected,
            stalledThreshold: 12 * 60,
            loopSuspectedEnabled: true,
            loopRepeatCount: 4,
            loopSuspectedThreshold: 4,
            recentCompletionWindow: 20 * 60
        )
        let disabledSignals = CodexOperationalStatusSignals(
            now: now,
            bridgeConnectionState: .connected,
            codexAppServerConnectionState: .connected,
            stalledThreshold: 12 * 60,
            loopSuspectedEnabled: false,
            loopRepeatCount: 8,
            loopSuspectedThreshold: 4,
            recentCompletionWindow: 20 * 60
        )

        #expect(session.codexOperationalStatus(signals: enabledSignals) == .loopSuspected)
        #expect(session.codexOperationalStatus(signals: disabledSignals) == .running)
    }

    @Test
    func detachedStatusAppearsWhenAttachmentLost() {
        let now = Date(timeIntervalSince1970: 20_000)
        var session = AgentSession(
            id: "codex-1",
            title: "Codex · repo",
            tool: .codex,
            origin: .live,
            attachmentState: .detached,
            phase: .running,
            summary: "Running",
            updatedAt: now
        )
        session.isProcessAlive = true

        let signals = CodexOperationalStatusSignals(
            now: now,
            bridgeConnectionState: .connected,
            codexAppServerConnectionState: .connected,
            stalledThreshold: 12 * 60,
            loopSuspectedEnabled: true,
            loopRepeatCount: 8,
            loopSuspectedThreshold: 4,
            recentCompletionWindow: 20 * 60
        )
        #expect(session.codexOperationalStatus(signals: signals) == .detached)
    }
}
