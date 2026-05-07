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
    func staleInterruptedFlagDoesNotOverrideNormalCompletionSummary() {
        let now = Date(timeIntervalSince1970: 20_000)
        var session = AgentSession(
            id: "codex-1",
            title: "Codex · repo",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Explained the attention indicator.",
            updatedAt: now
        )
        session.lastTurnInterrupted = true

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

        #expect(session.codexOperationalStatus(signals: signals) == .recentlyCompleted)
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
    func reconnectingDoesNotOverrideCompletedCodexAppSessions() {
        let now = Date(timeIntervalSince1970: 20_000)
        var session = AgentSession(
            id: "codex-app-completed",
            title: "Codex · repo",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Interrupted",
            updatedAt: now
        )
        session.isCodexAppSession = true
        session.lastTurnInterrupted = true

        let signals = CodexOperationalStatusSignals(
            now: now,
            bridgeConnectionState: .connected,
            codexAppServerConnectionState: .reconnecting,
            stalledThreshold: 12 * 60,
            loopSuspectedEnabled: false,
            loopRepeatCount: 0,
            loopSuspectedThreshold: 4,
            recentCompletionWindow: 20 * 60
        )

        #expect(session.codexOperationalStatus(signals: signals) == .interrupted)
    }

    @Test
    func reconnectingDoesNotOverrideInactiveRunningSessions() {
        let now = Date(timeIntervalSince1970: 20_000)
        var session = AgentSession(
            id: "codex-stale-running",
            title: "Codex · repo",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Old running session",
            updatedAt: now.addingTimeInterval(-20 * 60)
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

        #expect(session.codexOperationalStatus(signals: signals) == .stalled)
    }

    @Test
    func reconnectingDoesNotOverrideDetachedSessions() {
        let now = Date(timeIntervalSince1970: 20_000)
        var session = AgentSession(
            id: "codex-detached-running",
            title: "Codex · repo",
            tool: .codex,
            origin: .live,
            attachmentState: .detached,
            phase: .running,
            summary: "Detached",
            updatedAt: now
        )
        session.isCodexAppSession = true
        session.isProcessAlive = true

        let signals = CodexOperationalStatusSignals(
            now: now,
            bridgeConnectionState: .connected,
            codexAppServerConnectionState: .reconnecting,
            stalledThreshold: 12 * 60,
            loopSuspectedEnabled: false,
            loopRepeatCount: 0,
            loopSuspectedThreshold: 4,
            recentCompletionWindow: 20 * 60
        )

        #expect(session.codexOperationalStatus(signals: signals) == .detached)
    }

    @Test
    func codexAppThreadJumpTargetOverridesTerminalDetachFlicker() {
        let now = Date(timeIntervalSince1970: 20_000)
        var session = AgentSession(
            id: "codex-app-thread",
            title: "Codex · repo",
            tool: .codex,
            origin: .live,
            attachmentState: .detached,
            phase: .running,
            summary: "Running in Codex.app",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Codex.app",
                workspaceName: "repo",
                paneTitle: "Codex · repo",
                workingDirectory: "/tmp/repo",
                codexThreadID: "thread-1"
            )
        )
        session.isCodexAppSession = true
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

        #expect(session.codexOperationalStatus(signals: signals) == .running)
    }

    @Test
    func codexAppSessionWithoutThreadJumpTargetStaysDetached() {
        let now = Date(timeIntervalSince1970: 20_000)
        var session = AgentSession(
            id: "codex-app-detached",
            title: "Codex · repo",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Missing thread target",
            updatedAt: now
        )
        session.isCodexAppSession = true
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

        #expect(session.codexOperationalStatus(signals: signals) == .detached)
    }

    @Test
    func reconnectingUsesStableRadarSortPriority() {
        #expect(CodexOperationalStatus.reconnecting.priority > CodexOperationalStatus.detached.priority)
        #expect(CodexOperationalStatus.reconnecting.radarSortPriority < CodexOperationalStatus.detached.radarSortPriority)
        #expect(CodexOperationalStatus.connecting.radarSortPriority == CodexOperationalStatus.running.radarSortPriority)
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
