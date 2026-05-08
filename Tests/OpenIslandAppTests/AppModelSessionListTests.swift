import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct AppModelSessionListTests {
    @Test
    func islandListSessionsOnlyIncludeLiveAttachedSessions() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()

        var liveSession = AgentSession(
            id: "live-session",
            title: "Claude · active",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "active",
                paneTitle: "claude ~/active",
                workingDirectory: "/tmp/active",
                terminalSessionID: "ghostty-1"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/live.jsonl",
                currentTool: "Task"
            )
        )
        liveSession.isProcessAlive = true

        model.state = SessionState(
            sessions: [
                liveSession,
                AgentSession(
                    id: "recent-session",
                    title: "Claude · recent",
                    tool: .claudeCode,
                    origin: .live,
                    attachmentState: .stale,
                    phase: .completed,
                    summary: "Finished",
                    updatedAt: now.addingTimeInterval(-300),
                    jumpTarget: JumpTarget(
                        terminalApp: "Ghostty",
                        workspaceName: "recent",
                        paneTitle: "claude ~/recent",
                        workingDirectory: "/tmp/recent",
                        terminalSessionID: "ghostty-2"
                    ),
                    claudeMetadata: ClaudeSessionMetadata(
                        transcriptPath: "/tmp/recent.jsonl",
                        lastAssistantMessage: "Finished"
                    )
                ),
            ]
        )

        #expect(model.surfacedSessions.map(\.id) == ["live-session"])
        #expect(model.recentSessions.map(\.id) == ["recent-session"])
        #expect(model.islandListSessions.map(\.id) == ["live-session"])
    }

    @Test
    func islandListDeduplicatesSessionsSharingTheSameLiveGhosttyTerminal() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()

        var runningLive = AgentSession(
            id: "running-live",
            title: "Codex · open-island",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Current live turn",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-split-1"
            )
        )
        runningLive.isProcessAlive = true

        var oldTurnSameSplit = AgentSession(
            id: "old-turn-same-split",
            title: "Codex · open-island",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Historical turn on the same split",
            updatedAt: now.addingTimeInterval(-90),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-split-1"
            )
        )
        oldTurnSameSplit.isProcessAlive = true

        var otherLive = AgentSession(
            id: "other-live",
            title: "Codex · open-island",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Another live split",
            updatedAt: now.addingTimeInterval(-30),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-split-2"
            )
        )
        otherLive.isProcessAlive = true

        model.state = SessionState(
            sessions: [runningLive, oldTurnSameSplit, otherLive]
        )

        #expect(model.surfacedSessions.map(\.id) == ["running-live", "other-live"])
        #expect(model.recentSessions.map(\.id).contains("old-turn-same-split"))
        #expect(model.liveSessionCount == 2)
        #expect(model.liveRunningCount == 1)
        #expect(model.liveAttentionCount == 0)
    }

    @Test
    func sessionBootstrapPlaceholderAppearsWhileStartupResolutionIsPending() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.isResolvingInitialLiveSessions = true
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "recovered-session",
                    title: "Codex · open-island",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .stale,
                    phase: .running,
                    summary: "Recovered from cache",
                    updatedAt: now
                ),
            ]
        )

        #expect(model.liveSessionCount == 0)
        #expect(model.shouldShowSessionBootstrapPlaceholder)
    }

    @Test
    func sessionBootstrapPlaceholderClearsOnceALiveSessionIsConfirmed() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.isResolvingInitialLiveSessions = true

        var liveSession = AgentSession(
            id: "live-session",
            title: "Codex · open-island",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: now
        )
        liveSession.isProcessAlive = true

        model.state = SessionState(sessions: [liveSession])

        #expect(model.liveSessionCount == 1)
        #expect(!model.shouldShowSessionBootstrapPlaceholder)
    }

    @Test
    func jumpToSessionClosesOverlayBeforeTerminalJumpFinishes() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel { _ in
            Thread.sleep(forTimeInterval: 0.25)
            return "Focused the matching Ghostty terminal."
        }
        model.notchStatus = .opened
        model.notchOpenReason = .click
        model.islandSurface = .sessionList()

        let session = AgentSession(
            id: "live-session",
            title: "Codex · open-island",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-1"
            )
        )

        model.jumpToSession(session)

        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
        #expect(model.islandSurface == .sessionList())

        let expected = "Focused the matching Ghostty terminal."
        for _ in 0..<20 {
            if model.lastActionMessage == expected { break }
            try await Task.sleep(for: .milliseconds(100))
        }

        #expect(model.lastActionMessage == expected)
    }

    @Test
    func rolloutEventsDoNotPromoteRecoveredSessionsToAttachedDuringColdStart() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.isResolvingInitialLiveSessions = true
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "recovered-session",
                    title: "Codex · open-island",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .stale,
                    phase: .running,
                    summary: "Recovered from cache",
                    updatedAt: now
                ),
            ]
        )

        model.applyTrackedEvent(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: "recovered-session",
                    summary: "Reading recent rollout lines.",
                    phase: .running,
                    timestamp: now.addingTimeInterval(1)
                )
            ),
            updateLastActionMessage: false,
            ingress: .rollout
        )

        #expect(model.liveSessionCount == 0)
        #expect(model.state.session(id: "recovered-session")?.attachmentState == .stale)
        #expect(model.shouldShowSessionBootstrapPlaceholder)
    }

    @Test
    func bridgeEventsStillPromoteSessionsToAttached() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "live-session",
                    title: "Codex · open-island",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .stale,
                    phase: .running,
                    summary: "Recovered from cache",
                    updatedAt: now
                ),
            ]
        )

        model.applyTrackedEvent(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: "live-session",
                    summary: "Bridge says the agent is running.",
                    phase: .running,
                    timestamp: now.addingTimeInterval(1)
                )
            ),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        #expect(model.liveSessionCount == 1)
        #expect(model.state.session(id: "live-session")?.attachmentState == .attached)
    }

    @Test
    func rolloutCompletionDoesNotPresentNotificationDuringColdStart() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.isResolvingInitialLiveSessions = true
        model.notchStatus = .closed
        model.notchOpenReason = nil
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "recovered-session",
                    title: "Codex · open-island",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .stale,
                    phase: .running,
                    summary: "Recovered from cache",
                    updatedAt: now
                ),
            ]
        )

        model.applyTrackedEvent(
            .sessionCompleted(
                SessionCompleted(
                    sessionID: "recovered-session",
                    summary: "Recovered rollout finished.",
                    timestamp: now.addingTimeInterval(1)
                )
            ),
            updateLastActionMessage: false,
            ingress: .rollout
        )

        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
        #expect(model.islandSurface == .sessionList())
    }

    @Test
    func bridgeNotificationIsSuppressedWhenSessionIsAlreadyFrontmost() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel(
            isNotificationSessionAlreadyFrontmost: { session in
                session.id == "frontmost-session"
            }
        )
        model.notchStatus = .closed
        model.notchOpenReason = nil
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "frontmost-session",
                    title: "Codex · open-island",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .attached,
                    phase: .running,
                    summary: "Already focused in the front terminal.",
                    updatedAt: now
                ),
            ]
        )

        model.applyTrackedEvent(
            .permissionRequested(
                PermissionRequested(
                    sessionID: "frontmost-session",
                    request: PermissionRequest(
                        title: "Edit",
                        summary: "main.swift",
                        affectedPath: "/tmp/main.swift"
                    ),
                    timestamp: now.addingTimeInterval(1)
                )
            ),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        for _ in 0..<20 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
        #expect(model.islandSurface == .sessionList())
    }

    @Test
    func bridgeNotificationStillPresentsWhenSessionIsNotFrontmost() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel(
            isNotificationSessionAlreadyFrontmost: { _ in false }
        )
        model.notchStatus = .closed
        model.notchOpenReason = nil
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "background-session",
                    title: "Codex · open-island",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .attached,
                    phase: .running,
                    summary: "Needs approval.",
                    updatedAt: now
                ),
            ]
        )

        model.applyTrackedEvent(
            .permissionRequested(
                PermissionRequested(
                    sessionID: "background-session",
                    request: PermissionRequest(
                        title: "Edit",
                        summary: "main.swift",
                        affectedPath: "/tmp/main.swift"
                    ),
                    timestamp: now.addingTimeInterval(1)
                )
            ),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        for _ in 0..<20 {
            if model.notchStatus == .opened {
                break
            }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .notification)
        #expect(model.islandSurface == .sessionList(actionableSessionID: "background-session"))
    }

    @Test
    func hoverOpenedSessionListAutoCollapsesOnPointerExit() {
        let model = AppModel()
        model.notchStatus = .opened
        model.notchOpenReason = .hover
        model.islandSurface = .sessionList()

        #expect(model.shouldAutoCollapseOnMouseLeave)

        model.handlePointerExitedIslandSurface()

        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
        #expect(model.islandSurface == .sessionList())
    }

    @Test
    func closeTransitionSetsStateImmediatelyAndClearsPending() {
        let model = AppModel()
        model.notchStatus = .opened
        model.notchOpenReason = .hover
        model.islandSurface = .sessionList()

        model.notchClose()

        // State changes immediately; pending clears synchronously in tests
        // (no panel → fadeOutAndClose calls completion inline).
        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
        #expect(!model.isOverlayCloseTransitionPending)
    }

    @Test
    func clickedSessionListDoesNotAutoCollapseOnPointerExit() {
        let model = AppModel()
        model.notchStatus = .opened
        model.notchOpenReason = .click
        model.islandSurface = .sessionList()

        #expect(!model.shouldAutoCollapseOnMouseLeave)

        model.notePointerInsideIslandSurface()
        model.handlePointerExitedIslandSurface()

        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .click)
        #expect(model.islandSurface == .sessionList())
    }

    @Test
    func idleEdgeModeOnlyAppliesWhileCollapsed() {
        let model = AppModel()
        let originalSetting = model.hideIdleIslandToEdge
        defer { model.hideIdleIslandToEdge = originalSetting }
        model.hideIdleIslandToEdge = true

        model.notchStatus = .closed
        #expect(model.showsIdleEdgeWhenCollapsed)

        model.notchStatus = .opened
        #expect(!model.showsIdleEdgeWhenCollapsed)
    }

    @Test
    func completionNotificationRequiresSurfaceEntryBeforePointerExitCollapse() {
        let model = AppModel()
        // Add a completed session so autoDismissesWhenPresentedAsNotification can check phase
        model.applyTrackedEvent(
            .sessionStarted(SessionStarted(
                sessionID: "session-1",
                title: "Test",
                tool: .codex,
                summary: "Done",
                timestamp: .now
            )),
            updateLastActionMessage: false
        )
        model.applyTrackedEvent(
            .sessionCompleted(SessionCompleted(
                sessionID: "session-1",
                summary: "Done",
                timestamp: .now
            )),
            updateLastActionMessage: false
        )
        model.notchStatus = .opened
        model.notchOpenReason = .notification
        model.islandSurface = .sessionList(actionableSessionID: "session-1")

        #expect(model.shouldAutoCollapseOnMouseLeave)

        model.handlePointerExitedIslandSurface()

        #expect(model.notchStatus == .opened)
        #expect(model.notchOpenReason == .notification)

        model.notePointerInsideIslandSurface()
        model.handlePointerExitedIslandSurface()

        #expect(model.notchStatus == .closed)
        #expect(model.notchOpenReason == nil)
    }

    @Test
    func mergeDiscoveredClaudeSessionsPreservesRegistryJumpTargetAndAddsTranscriptMetadata() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "claude-session",
                    title: "Claude · open-island",
                    tool: .claudeCode,
                    origin: .live,
                    attachmentState: .stale,
                    phase: .completed,
                    summary: "Recovered from registry",
                    updatedAt: now.addingTimeInterval(-60),
                    jumpTarget: JumpTarget(
                        terminalApp: "Ghostty",
                        workspaceName: "open-island",
                        paneTitle: "claude ~/open-island",
                        workingDirectory: "/tmp/open-island",
                        terminalSessionID: "ghostty-claude",
                        terminalTTY: "/dev/ttys002"
                    )
                ),
            ]
        )

        let merged = model.discovery.mergeDiscoveredSessions([
            AgentSession(
                id: "claude-session",
                title: "Claude · open-island",
                tool: .claudeCode,
                origin: .live,
                attachmentState: .stale,
                phase: .running,
                summary: "Recovered from transcript",
                updatedAt: now,
                jumpTarget: JumpTarget(
                    terminalApp: "Unknown",
                    workspaceName: "open-island",
                    paneTitle: "Claude deadbeef",
                    workingDirectory: "/tmp/open-island"
                ),
                claudeMetadata: ClaudeSessionMetadata(
                    transcriptPath: "/tmp/claude.jsonl",
                    lastUserPrompt: "Check the Claude session registry.",
                    currentTool: "Task"
                )
            ),
        ])

        #expect(merged.count == 1)
        #expect(merged.first?.jumpTarget?.terminalApp == "Ghostty")
        #expect(merged.first?.jumpTarget?.terminalSessionID == "ghostty-claude")
        #expect(merged.first?.claudeMetadata?.transcriptPath == "/tmp/claude.jsonl")
        #expect(merged.first?.claudeMetadata?.lastUserPrompt == "Check the Claude session registry.")
        #expect(merged.first?.phase == .running)
    }

    @Test
    func mergedWithSyntheticClaudeSessionsAddsGhosttyClaudeProcessWhenNoTrackedSessionExists() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()

        let merged = model.monitoring.mergedWithSyntheticClaudeSessions(
            existingSessions: [],
            activeProcesses: [
                .init(
                    tool: .claudeCode,
                    sessionID: nil,
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys002",
                    terminalApp: "Ghostty"
                ),
            ],
            now: now
        )

        #expect(merged.count == 1)
        #expect(merged.first?.id.hasPrefix("claude-process:") == true)
        #expect(merged.first?.attachmentState == .attached)
        #expect(merged.first?.jumpTarget?.terminalApp == "Ghostty")
        #expect(merged.first?.jumpTarget?.terminalTTY == "/dev/ttys002")
    }

    @Test
    func sanitizeCrossToolGhosttyJumpTargetsClearsClaudeMisbinding() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        let misboundClaudeSession = AgentSession(
            id: "e45d5e87-66d0-4f67-8399-6ebc02f3d453",
            title: "Claude · open-island",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .running,
            summary: "Running",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-codex"
            )
        )

        let sanitized = model.monitoring.sanitizeCrossToolGhosttyJumpTargets(in: [misboundClaudeSession])

        #expect(sanitized.first?.jumpTarget?.terminalSessionID == nil)
        #expect(sanitized.first?.jumpTarget?.paneTitle == "Claude e45d5e87")
    }

    @Test
    func mergedWithSyntheticClaudeSessionsSkipsSyntheticWhenAttachedClaudeAlreadyRepresentsGroup() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        let existing = AgentSession(
            id: "e45d5e87-66d0-4f67-8399-6ebc02f3d453",
            title: "Claude · open-island",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "open-island · hi · e45d5e87",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-claude"
            )
        )

        let merged = model.monitoring.mergedWithSyntheticClaudeSessions(
            existingSessions: [existing],
            activeProcesses: [
                .init(
                    tool: .claudeCode,
                    sessionID: nil,
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys002",
                    terminalApp: "Ghostty"
                ),
            ],
            now: now
        )

        #expect(merged.map(\.id) == [existing.id])
    }

    @Test
    func mergedWithSyntheticClaudeSessionsSkipsSyntheticWhenStaleClaudeSessionMatchesActiveProcess() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        let existing = AgentSession(
            id: "e45d5e87-66d0-4f67-8399-6ebc02f3d453",
            title: "Claude · open-island-readme",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .completed,
            summary: "Recovered transcript",
            updatedAt: now.addingTimeInterval(-120),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island-readme",
                paneTitle: "Claude e45d5e87",
                workingDirectory: "/tmp/open-island-readme"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/claude-session.jsonl",
                lastUserPrompt: "整理 readme。"
            )
        )

        let merged = model.monitoring.mergedWithSyntheticClaudeSessions(
            existingSessions: [existing],
            activeProcesses: [
                .init(
                    tool: .claudeCode,
                    sessionID: existing.id,
                    workingDirectory: "/tmp/open-island-readme",
                    terminalTTY: "/dev/ttys008",
                    terminalApp: "Ghostty"
                ),
            ],
            now: now
        )

        #expect(merged.map(\.id) == [existing.id])
    }


    /// Regression test: `measuredNotificationContentHeight` MUST be cleared when the
    /// surface changes to a different session, to avoid sizing the new card with stale
    /// measurements from the previous one.
    @Test
    @MainActor
    func approvalCardMeasuredHeightClearedWhenSurfaceSessionChanges() {
        let model = AppModel()

        var sessionA = AgentSession(
            id: "approval-session-A",
            title: "Claude · proj-A",
            tool: .claudeCode,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Approve edit A",
            updatedAt: .now,
            permissionRequest: PermissionRequest(
                title: "Edit",
                summary: "file_a.swift",
                affectedPath: "/tmp/file_a.swift"
            )
        )
        sessionA.isProcessAlive = true

        var sessionB = AgentSession(
            id: "approval-session-B",
            title: "Claude · proj-B",
            tool: .claudeCode,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Approve edit B",
            updatedAt: .now,
            permissionRequest: PermissionRequest(
                title: "Edit",
                summary: "file_b.swift",
                affectedPath: "/tmp/file_b.swift"
            )
        )
        sessionB.isProcessAlive = true

        model.state = SessionState(sessions: [sessionA, sessionB])

        let surfaceA = IslandSurface.sessionList(actionableSessionID: "approval-session-A")
        model.notchStatus = .opened
        model.notchOpenReason = .notification
        model.islandSurface = surfaceA
        model.measuredNotificationContentHeight = 320

        model.notchClose()

        let surfaceB = IslandSurface.sessionList(actionableSessionID: "approval-session-B")
        model.notchOpen(reason: .notification, surface: surfaceB)

        #expect(
            model.measuredNotificationContentHeight == 0,
            "Switching to a different session's card must clear the stale measurement from the previous session to prevent wrong initial panel sizing."
        )
    }

    @Test
    func recoveredSessionMatchesLiveGhosttyProcessByCWDWhenMultipleCandidatesExist() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        let recoveredSessions = [
            AgentSession(
                id: "e45d5e87-66d0-4f67-8399-6ebc02f3d453",
                title: "Claude · open-island",
                tool: .claudeCode,
                origin: .live,
                attachmentState: .stale,
                phase: .completed,
                summary: "Recovered transcript",
                updatedAt: now.addingTimeInterval(-10_800),
                jumpTarget: JumpTarget(
                    terminalApp: "Unknown",
                    workspaceName: "open-island",
                    paneTitle: "Claude e45d5e87",
                    workingDirectory: "/tmp/open-island"
                )
            ),
            AgentSession(
                id: "c9a48d05-c1f9-4e39-ab66-19edef0c2bc9",
                title: "Claude · open-island",
                tool: .claudeCode,
                origin: .live,
                attachmentState: .stale,
                phase: .completed,
                summary: "Recovered transcript",
                updatedAt: now.addingTimeInterval(-64_800),
                jumpTarget: JumpTarget(
                    terminalApp: "Unknown",
                    workspaceName: "open-island",
                    paneTitle: "Claude c9a48d05",
                    workingDirectory: "/tmp/open-island"
                )
            ),
        ]
        let activeProcesses: [ActiveProcessSnapshot] = [
            .init(
                tool: .claudeCode,
                sessionID: nil,
                workingDirectory: "/tmp/open-island",
                terminalTTY: "/dev/ttys002",
                terminalApp: "Ghostty"
            ),
        ]

        let merged = model.monitoring.mergedWithSyntheticClaudeSessions(
            existingSessions: recoveredSessions,
            activeProcesses: activeProcesses,
            now: now
        )

        // With relaxed CWD matching, recovered session matches the process
        // so no synthetic session is created.
        #expect(merged.count == 2)
        #expect(merged.allSatisfy { !$0.id.hasPrefix("claude-process:") })

        let probe = TerminalSessionAttachmentProbe()
        let resolutions = probe.sessionResolutions(
            for: merged,
            ghosttyAvailability: .unavailable(appIsRunning: true),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            activeProcesses: activeProcesses,
            now: now
        )

        model.state = SessionState(sessions: merged)
        _ = model.state.reconcileAttachmentStates(resolutions.mapValues(\.attachmentState))
        _ = model.state.reconcileJumpTargets(
            resolutions.reduce(into: [String: JumpTarget]()) { partialResult, entry in
                if let correctedJumpTarget = entry.value.correctedJumpTarget {
                    partialResult[entry.key] = correctedJumpTarget
                }
            }
        )

        let claudeSessions = model.state.sessions.filter { $0.tool == .claudeCode }
        #expect(claudeSessions.count == 2)
    }

    @Test
    func codexShelfIgnoresReferencedPathsThatWereNotChangedByCodex() throws {
        let now = Date(timeIntervalSince1970: 3_900)
        let model = AppModel(codexShelfEnabledOverride: true)
        let fileManager = FileManager.default

        let workspaceURL = fileManager.temporaryDirectory
            .appendingPathComponent("open-island-shelf-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceURL) }

        let relativePath = "Sources/ShelfFeature.swift"
        let fileURL = workspaceURL.appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "struct ShelfFeature {}".write(to: fileURL, atomically: true, encoding: .utf8)

        var session = AgentSession(
            id: "codex-shelf-session",
            title: "Codex · shelf-project",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working on shelf panel",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "shelf-project",
                paneTitle: "codex ~/shelf-project",
                workingDirectory: workspaceURL.path
            )
        )
        session.isProcessAlive = true
        model.state = SessionState(sessions: [session])

        model.applyTrackedEvent(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: session.id,
                    summary: "Updated \(relativePath).",
                    phase: .running,
                    timestamp: now.addingTimeInterval(1)
                )
            )
        )

        #expect(model.codexShelfItems.isEmpty)
    }

    @Test
    func codexShelfTracksFilesModifiedAfterSessionBaseline() throws {
        let now = Date(timeIntervalSince1970: 3_920)
        let model = AppModel(codexShelfEnabledOverride: true)
        let fileManager = FileManager.default

        let workspaceURL = fileManager.temporaryDirectory
            .appendingPathComponent("open-island-shelf-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceURL) }

        let fileURL = workspaceURL.appendingPathComponent("Sources/ShelfFeature.swift")
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "struct ShelfFeature {}".write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-60)],
            ofItemAtPath: fileURL.path
        )

        model.applyTrackedEvent(
            .sessionStarted(
                SessionStarted(
                    sessionID: "codex-shelf-session",
                    title: "Codex · shelf-project",
                    tool: .codex,
                    origin: .live,
                    summary: "Working on shelf panel",
                    timestamp: now,
                    jumpTarget: JumpTarget(
                        terminalApp: "Ghostty",
                        workspaceName: "shelf-project",
                        paneTitle: "codex ~/shelf-project",
                        workingDirectory: workspaceURL.path
                    )
                )
            )
        )

        try "struct ShelfFeature { let value = 1 }".write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(30)],
            ofItemAtPath: fileURL.path
        )

        model.applyTrackedEvent(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: "codex-shelf-session",
                    summary: "Finished the shelf model update.",
                    phase: .running,
                    timestamp: now.addingTimeInterval(31)
                )
            )
        )

        let shelfItems = model.codexShelfItems
        #expect(shelfItems.count == 1)
        #expect(shelfItems.first?.fileName == "ShelfFeature.swift")
        #expect(shelfItems.first?.artifactType == .code)
        #expect(shelfItems.first?.source == .modified)
        #expect(shelfItems.first?.projectName == "shelf-project")
        #expect(shelfItems.first?.path == fileURL.standardizedFileURL.path)
    }

    @Test
    func codexShelfThrottlesActivityWorkspaceScans() throws {
        let now = Date(timeIntervalSince1970: 3_925)
        let model = AppModel(codexShelfEnabledOverride: true)
        let fileManager = FileManager.default

        let workspaceURL = fileManager.temporaryDirectory
            .appendingPathComponent("open-island-shelf-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceURL) }

        let fileURL = workspaceURL.appendingPathComponent("Sources/ShelfFeature.swift")
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "struct ShelfFeature {}".write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-60)],
            ofItemAtPath: fileURL.path
        )

        model.applyTrackedEvent(
            .sessionStarted(
                SessionStarted(
                    sessionID: "codex-shelf-throttle",
                    title: "Codex · shelf-project",
                    tool: .codex,
                    origin: .live,
                    summary: "Working on shelf panel",
                    timestamp: now,
                    jumpTarget: JumpTarget(
                        terminalApp: "Ghostty",
                        workspaceName: "shelf-project",
                        paneTitle: "codex ~/shelf-project",
                        workingDirectory: workspaceURL.path
                    )
                )
            )
        )

        try "struct ShelfFeature { let value = 1 }".write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(2)],
            ofItemAtPath: fileURL.path
        )

        model.applyTrackedEvent(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: "codex-shelf-throttle",
                    summary: "Still updating shelf files.",
                    phase: .running,
                    timestamp: now.addingTimeInterval(2)
                )
            )
        )

        #expect(model.codexShelfItems.isEmpty)

        model.applyTrackedEvent(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: "codex-shelf-throttle",
                    summary: "Finished updating shelf files.",
                    phase: .running,
                    timestamp: now.addingTimeInterval(11)
                )
            )
        )

        #expect(model.codexShelfItems.count == 1)
        #expect(model.codexShelfItems.first?.path == fileURL.standardizedFileURL.path)
    }

    @Test
    func codexShelfCompletionBypassesActivityScanThrottle() throws {
        let now = Date(timeIntervalSince1970: 3_926)
        let model = AppModel(codexShelfEnabledOverride: true)
        let fileManager = FileManager.default

        let workspaceURL = fileManager.temporaryDirectory
            .appendingPathComponent("open-island-shelf-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceURL) }

        let fileURL = workspaceURL.appendingPathComponent("Sources/ShelfFeature.swift")
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "struct ShelfFeature {}".write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-60)],
            ofItemAtPath: fileURL.path
        )

        model.applyTrackedEvent(
            .sessionStarted(
                SessionStarted(
                    sessionID: "codex-shelf-completion",
                    title: "Codex · shelf-project",
                    tool: .codex,
                    origin: .live,
                    summary: "Working on shelf panel",
                    timestamp: now,
                    jumpTarget: JumpTarget(
                        terminalApp: "Ghostty",
                        workspaceName: "shelf-project",
                        paneTitle: "codex ~/shelf-project",
                        workingDirectory: workspaceURL.path
                    )
                )
            )
        )

        try "struct ShelfFeature { let value = 1 }".write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(2)],
            ofItemAtPath: fileURL.path
        )

        model.applyTrackedEvent(
            .sessionCompleted(
                SessionCompleted(
                    sessionID: "codex-shelf-completion",
                    summary: "Finished shelf update.",
                    timestamp: now.addingTimeInterval(3)
                )
            )
        )

        #expect(model.codexShelfItems.count == 1)
        #expect(model.codexShelfItems.first?.path == fileURL.standardizedFileURL.path)
    }

    @Test
    func codexShelfHidesDebugLogsByDefault() throws {
        let now = Date(timeIntervalSince1970: 3_930)
        let model = AppModel(codexShelfEnabledOverride: true)
        let fileManager = FileManager.default

        let workspaceURL = fileManager.temporaryDirectory
            .appendingPathComponent("open-island-shelf-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceURL) }

        model.applyTrackedEvent(
            .sessionStarted(
                SessionStarted(
                    sessionID: "codex-shelf-debug",
                    title: "Codex · shelf-project",
                    tool: .codex,
                    origin: .live,
                    summary: "Working on shelf panel",
                    timestamp: now,
                    jumpTarget: JumpTarget(
                        terminalApp: "Ghostty",
                        workspaceName: "shelf-project",
                        paneTitle: "codex ~/shelf-project",
                        workingDirectory: workspaceURL.path
                    )
                )
            )
        )

        let logURL = workspaceURL.appendingPathComponent("debug.log")
        try "debug".write(to: logURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(10)],
            ofItemAtPath: logURL.path
        )

        model.applyTrackedEvent(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: "codex-shelf-debug",
                    summary: "Collected debug output.",
                    phase: .running,
                    timestamp: now.addingTimeInterval(11)
                )
            )
        )

        #expect(model.codexShelfItems.isEmpty)
    }

    @Test
    func codexShelfIgnoresNonCodexSessions() throws {
        let now = Date(timeIntervalSince1970: 3_950)
        let model = AppModel(codexShelfEnabledOverride: true)
        let fileManager = FileManager.default

        let workspaceURL = fileManager.temporaryDirectory
            .appendingPathComponent("open-island-shelf-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceURL) }

        let fileURL = workspaceURL.appendingPathComponent("main.swift")
        try "print(\"hello\")".write(to: fileURL, atomically: true, encoding: .utf8)

        var session = AgentSession(
            id: "claude-shelf-session",
            title: "Claude · shelf-project",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working on docs",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "shelf-project",
                paneTitle: "claude ~/shelf-project",
                workingDirectory: workspaceURL.path
            )
        )
        session.isProcessAlive = true
        model.state = SessionState(sessions: [session])

        model.applyTrackedEvent(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: session.id,
                    summary: "Updated main.swift",
                    phase: .running,
                    timestamp: now.addingTimeInterval(1)
                )
            )
        )

        #expect(model.codexShelfItems.isEmpty)
        #expect(model.codexShelfProjects.isEmpty)
    }

    @Test
    func codexShelfDoesNotScanWhenBetaDisabled() throws {
        let now = Date(timeIntervalSince1970: 3_960)
        let model = AppModel(codexShelfEnabledOverride: false)
        let fileManager = FileManager.default

        let workspaceURL = fileManager.temporaryDirectory
            .appendingPathComponent("open-island-shelf-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceURL) }

        let fileURL = workspaceURL.appendingPathComponent("main.swift")
        try "print(\"hello\")".write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-60)],
            ofItemAtPath: fileURL.path
        )

        model.applyTrackedEvent(
            .sessionStarted(
                SessionStarted(
                    sessionID: "codex-shelf-beta-off",
                    title: "Codex · shelf-project",
                    tool: .codex,
                    origin: .live,
                    summary: "Working on docs",
                    timestamp: now,
                    jumpTarget: JumpTarget(
                        terminalApp: "Ghostty",
                        workspaceName: "shelf-project",
                        paneTitle: "codex ~/shelf-project",
                        workingDirectory: workspaceURL.path
                    )
                )
            )
        )

        try "print(\"updated\")".write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(10)],
            ofItemAtPath: fileURL.path
        )

        model.applyTrackedEvent(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: "codex-shelf-beta-off",
                    summary: "Finished updating code.",
                    phase: .running,
                    timestamp: now.addingTimeInterval(11)
                )
            )
        )

        #expect(model.codexShelfItems.isEmpty)
        #expect(model.codexShelfProjects.isEmpty)
    }

    @Test
    func codexShelfCanBeDisabledViaFeatureToggle() throws {
        let now = Date(timeIntervalSince1970: 3_975)
        let model = AppModel(codexShelfEnabledOverride: true)
        let fileManager = FileManager.default

        let workspaceURL = fileManager.temporaryDirectory
            .appendingPathComponent("open-island-shelf-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceURL) }

        let fileURL = workspaceURL.appendingPathComponent("main.swift")
        try "print(\"hello\")".write(to: fileURL, atomically: true, encoding: .utf8)

        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-60)],
            ofItemAtPath: fileURL.path
        )

        model.applyTrackedEvent(
            .sessionStarted(
                SessionStarted(
                    sessionID: "codex-shelf-toggle",
                    title: "Codex · shelf-project",
                    tool: .codex,
                    origin: .live,
                    summary: "Working on docs",
                    timestamp: now,
                    jumpTarget: JumpTarget(
                        terminalApp: "Ghostty",
                        workspaceName: "shelf-project",
                        paneTitle: "codex ~/shelf-project",
                        workingDirectory: workspaceURL.path
                    )
                )
            )
        )

        try "print(\"updated\")".write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(10)],
            ofItemAtPath: fileURL.path
        )

        model.applyTrackedEvent(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: "codex-shelf-toggle",
                    summary: "Finished updating code.",
                    phase: .running,
                    timestamp: now.addingTimeInterval(11)
                )
            )
        )

        #expect(model.codexShelfItems.count == 1)
        model.codexShelfEnabled = false
        #expect(model.codexShelfItems.isEmpty)
    }

    @Test
    func codexRadarCanBeDisabledViaFeatureToggle() {
        let now = Date(timeIntervalSince1970: 3_990)
        let model = AppModel()

        var session = AgentSession(
            id: "codex-radar-toggle",
            title: "Codex · radar-repo",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running radar task",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "radar-repo",
                paneTitle: "codex ~/radar-repo",
                workingDirectory: "/tmp/radar-repo"
            )
        )
        session.isProcessAlive = true
        model.state = SessionState(sessions: [session])

        #expect(model.codexRadarProjects.count == 1)
        model.codexRadarEnabled = false
        #expect(model.codexRadarProjects.isEmpty)
    }

    @Test
    func codexRadarAggregatesByProjectAndPrioritizesActionableProject() {
        let now = Date(timeIntervalSince1970: 4_000)
        let model = AppModel()

        var approvalSession = AgentSession(
            id: "codex-approval",
            title: "Codex · project-alpha",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Needs approval",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "project-alpha",
                paneTitle: "codex ~/project-alpha",
                workingDirectory: "/tmp/project-alpha"
            ),
            codexMetadata: CodexSessionMetadata(lastUserPrompt: "Ship alpha patch")
        )
        approvalSession.isProcessAlive = true

        var runningAlpha = AgentSession(
            id: "codex-alpha-running",
            title: "Codex · project-alpha",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running alpha task",
            updatedAt: now.addingTimeInterval(-20),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "project-alpha",
                paneTitle: "codex ~/project-alpha",
                workingDirectory: "/tmp/project-alpha"
            ),
            codexMetadata: CodexSessionMetadata(lastUserPrompt: "Refine alpha task")
        )
        runningAlpha.isProcessAlive = true

        var runningBeta = AgentSession(
            id: "codex-beta-running",
            title: "Codex · project-beta",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running beta task",
            updatedAt: now.addingTimeInterval(-5),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "project-beta",
                paneTitle: "codex ~/project-beta",
                workingDirectory: "/tmp/project-beta"
            ),
            codexMetadata: CodexSessionMetadata(lastUserPrompt: "Keep beta running")
        )
        runningBeta.isProcessAlive = true

        model.state = SessionState(sessions: [runningBeta, approvalSession, runningAlpha])

        let radar = model.codexRadarProjects
        #expect(radar.count == 2)
        #expect(radar.first?.projectName == "project-alpha")
        #expect(radar.first?.topStatus == .waitingApproval)
        #expect(radar.first?.runningTaskCount == 1)
        #expect(radar.first?.actionableTaskCount == 1)
        #expect(radar.first?.latestSummary == "Ship alpha patch")
        #expect(radar.first?.primarySessionID == "codex-approval")
    }

    @Test
    func codexRadarUsesRunningProjectWhenNoActionableRiskExists() {
        let now = Date(timeIntervalSince1970: 4_500)
        let model = AppModel()

        var running = AgentSession(
            id: "codex-running",
            title: "Codex · radar-repo",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "radar-repo",
                paneTitle: "codex ~/radar-repo",
                workingDirectory: "/tmp/radar-repo"
            )
        )
        running.isProcessAlive = true

        var completed = AgentSession(
            id: "codex-completed",
            title: "Codex · old-repo",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Done",
            updatedAt: now.addingTimeInterval(-500),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "old-repo",
                paneTitle: "codex ~/old-repo",
                workingDirectory: "/tmp/old-repo"
            )
        )
        completed.isProcessAlive = true

        model.state = SessionState(sessions: [completed, running])

        let radar = model.codexRadarProjects
        #expect(radar.count == 2)
        #expect(radar.first?.projectName == "radar-repo")
        #expect(radar.first?.topStatus == .running)
    }

    @Test
    func openShelfItemInvokesConfiguredFileAction() throws {
        let fileURL = try makeTemporaryShelfFile(named: "codex-shelf-open.txt")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let actions = FakeCodexShelfFileActions()
        let model = AppModel(codexShelfFileActions: actions)
        let item = shelfItem(path: fileURL.path)

        model.openShelfItem(item)

        #expect(actions.openedFiles == [fileURL.standardizedFileURL])
        #expect(model.lastActionMessage == "Opened codex-shelf-open.txt.")
    }

    @Test
    func revealShelfItemInvokesConfiguredFinderAction() throws {
        let fileURL = try makeTemporaryShelfFile(named: "codex-shelf-reveal.txt")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let actions = FakeCodexShelfFileActions()
        let model = AppModel(codexShelfFileActions: actions)
        let item = shelfItem(path: fileURL.path)

        model.revealShelfItemInFinder(item)

        #expect(actions.revealedFiles == [fileURL.standardizedFileURL])
        #expect(model.lastActionMessage == "Revealed codex-shelf-reveal.txt in Finder.")
    }

    private func makeTemporaryShelfFile(named name: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent(name)
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("shelf".utf8))
        return fileURL
    }

    private func shelfItem(path: String) -> CodexShelfItem {
        CodexShelfItem(
            id: path.lowercased(),
            path: path,
            fileName: URL(fileURLWithPath: path).lastPathComponent,
            artifactType: .code,
            source: .modified,
            projectName: "open-vibe-island",
            sourceSessionID: "codex-session",
            discoveredAt: Date(timeIntervalSince1970: 5_000),
            modifiedAt: Date(timeIntervalSince1970: 5_000)
        )
    }
}

@MainActor
private final class FakeCodexShelfFileActions: CodexShelfFileActioning, @unchecked Sendable {
    var openedFiles: [URL] = []
    var revealedFiles: [URL] = []
    var openedDirectories: [URL] = []

    func openFile(at url: URL) -> Bool {
        openedFiles.append(url)
        return true
    }

    func revealFile(at url: URL) -> Bool {
        revealedFiles.append(url)
        return true
    }

    func openDirectory(at url: URL) -> Bool {
        openedDirectories.append(url)
        return true
    }
}
