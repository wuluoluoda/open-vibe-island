import AppKit
import Foundation
import OpenIslandCore

/// Manages the lifecycle of the Codex app-server connection.
///
/// Automatically starts the app-server subprocess when Codex.app is
/// detected, and tears it down when the app quits.  Converts incoming
/// app-server notifications into `AgentEvent`s that flow through the
/// standard `SessionState` reducer.
@Observable
@MainActor
final class CodexAppServerCoordinator {
    @ObservationIgnored
    private var client: CodexAppServerClient?

    @ObservationIgnored
    private var connectTask: Task<Void, Never>?

    @ObservationIgnored
    private var reconnectTask: Task<Void, Never>?

    @ObservationIgnored
    private var healthCheckTask: Task<Void, Never>?

    @ObservationIgnored
    private var hasConnectedOnce = false

    /// Callback to emit AgentEvents into AppModel.
    @ObservationIgnored
    var onEvent: ((AgentEvent) -> Void)?

    /// Callback to log status messages.
    @ObservationIgnored
    var onStatusMessage: ((String) -> Void)?

    /// Requests the rollout-file fallback path when app-server cannot provide
    /// a useful current-thread snapshot.
    @ObservationIgnored
    var onFallbackRefreshNeeded: (() -> Void)?

    /// Fires when connection lifecycle changes (connecting/reconnecting/etc).
    @ObservationIgnored
    var onConnectionStateChanged: ((RuntimeConnectionState) -> Void)?

    /// Returns `true` if a session with the given id is already tracked.
    /// Used to avoid re-emitting `sessionStarted` (which rebuilds the
    /// session and wipes richer state from hooks/rediscovery).
    @ObservationIgnored
    var isSessionTracked: ((String) -> Bool)?

    private(set) var isConnected = false
    private(set) var connectionState: RuntimeConnectionState = .disconnected {
        didSet {
            guard connectionState != oldValue else {
                return
            }
            onConnectionStateChanged?(connectionState)
        }
    }

    private static let reconnectDelay: Duration = .seconds(2)
    private static let maxReconnectDelay: Duration = .seconds(20)
    private static let healthCheckInterval: Duration = .seconds(15)

    // MARK: - Public API

    /// Ensure a connection exists.  Called from the monitoring loop when
    /// Codex.app is detected as running.  Idempotent — does nothing if
    /// already connected or a connection attempt is in progress.
    func ensureConnected() {
        guard !isConnected, connectTask == nil else { return }
        connectionState = hasConnectedOnce ? .reconnecting : .connecting

        // Resolve the Codex.app bundle location dynamically — users may
        // have installed Codex outside `/Applications` (e.g. ~/Applications).
        guard let bundleURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.openai.codex"
        ) else {
            return
        }
        let codexPath = bundleURL
            .appendingPathComponent("Contents/Resources/codex")
            .path
        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            return
        }

        connectTask = Task { [weak self] in
            guard let self else { return }
            do {
                let newClient = CodexAppServerClient(codexPath: codexPath)
                newClient.onNotification = { [weak self] notification in
                    Task { @MainActor [weak self] in
                        self?.handleNotification(notification)
                    }
                }
                try await newClient.start()

                self.client = newClient
                self.isConnected = true
                self.connectionState = .connected
                self.hasConnectedOnce = true
                self.connectTask = nil
                self.reconnectTask?.cancel()
                self.reconnectTask = nil

                self.onStatusMessage?("Connected to Codex app-server.")

                // Fetch currently live threads and create sessions.
                await self.syncCurrentThreads()
                self.startHealthCheckLoop()
            } catch {
                self.connectTask = nil
                self.isConnected = false
                self.onStatusMessage?("Failed to connect to Codex app-server: \(error.localizedDescription)")
                if ProcessMonitoringCoordinator.isCodexDesktopAppRunning() {
                    self.connectionState = self.hasConnectedOnce ? .reconnecting : .connecting
                    self.scheduleReconnect()
                } else {
                    self.connectionState = .disconnected
                }
            }
        }
    }

    /// Disconnect and clean up.  Called when Codex.app is no longer running.
    func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        healthCheckTask?.cancel()
        healthCheckTask = nil
        client?.stop()
        client = nil
        isConnected = false
        connectionState = .disconnected
    }

    // MARK: - Thread sync

    private func syncCurrentThreads() async {
        guard let client else { return }
        do {
            let threads = try await currentThreads(from: client)
            var created = 0
            for thread in threads where !thread.ephemeral {
                // Skip threads already tracked — re-emitting sessionStarted
                // rebuilds the AgentSession and would wipe richer state
                // already accumulated from hooks or rediscovery.
                if isSessionTracked?(thread.id) == true { continue }
                emitSessionStarted(from: thread)
                created += 1
            }
            if created > 0 {
                onStatusMessage?("Synced \(created) new Codex thread(s) from app-server.")
            }
            if threads.isEmpty || created == 0 {
                onFallbackRefreshNeeded?()
            }
        } catch {
            onStatusMessage?("Failed to list current Codex threads: \(error.localizedDescription)")
            onFallbackRefreshNeeded?()
            handleConnectionLossIfNeeded(reason: "Codex app-server sync failed. Reconnecting…")
        }
    }

    private func currentThreads(from client: CodexAppServerClient) async throws -> [CodexThread] {
        var firstError: Error?
        let loadedThreads: [CodexThread]
        do {
            loadedThreads = try await client.listLoadedThreads()
        } catch {
            loadedThreads = []
            firstError = error
        }

        let allThreads: [CodexThread]
        do {
            allThreads = try await client.listThreads(limit: 120)
        } catch {
            allThreads = []
            if firstError == nil {
                firstError = error
            }
        }

        if loadedThreads.isEmpty, allThreads.isEmpty, let firstError {
            throw firstError
        }

        var threadsByID: [String: CodexThread] = [:]

        for thread in loadedThreads where !thread.ephemeral {
            threadsByID[thread.id] = thread
        }

        for thread in allThreads where !thread.ephemeral && thread.status.type == .active {
            threadsByID[thread.id] = thread
        }

        return threadsByID.values.sorted { lhs, rhs in
            if lhs.status.type == rhs.status.type {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.status.type == .active
        }
    }

    // MARK: - Notification handling

    private func handleNotification(_ notification: CodexAppServerNotification) {
        switch notification {
        case .threadStarted(let thread):
            guard !thread.ephemeral else { return }
            guard isSessionTracked?(thread.id) != true else { return }
            emitSessionStarted(from: thread)

        case .threadStatusChanged(let threadId, let status):
            switch status.type {
            case .active:
                if status.isWaitingOnApproval {
                    onEvent?(.permissionRequested(
                        PermissionRequested(
                            sessionID: threadId,
                            request: PermissionRequest(
                                title: "Approval Required",
                                summary: "Codex is waiting for approval.",
                                affectedPath: ""
                            ),
                            timestamp: .now
                        )
                    ))
                } else if status.isWaitingOnUserInput {
                    onEvent?(.questionAsked(
                        QuestionAsked(
                            sessionID: threadId,
                            prompt: QuestionPrompt(
                                title: "Codex is waiting for input.",
                                options: []
                            ),
                            timestamp: .now
                        )
                    ))
                } else {
                    onEvent?(.activityUpdated(
                        SessionActivityUpdated(
                            sessionID: threadId,
                            summary: "Codex is working…",
                            phase: .running,
                            timestamp: .now
                        )
                    ))
                }
            case .idle:
                // Idle means "between turns" in the same thread — the thread
                // is still open.  Only `thread/closed` truly ends a session.
                onEvent?(.activityUpdated(
                    SessionActivityUpdated(
                        sessionID: threadId,
                        summary: "Idle.",
                        phase: .completed,
                        timestamp: .now
                    )
                ))
            case .notLoaded, .systemError:
                break
            }

        case .threadClosed(let threadId):
            onEvent?(.sessionCompleted(
                SessionCompleted(
                    sessionID: threadId,
                    summary: "Codex thread closed.",
                    timestamp: .now,
                    isSessionEnd: true
                )
            ))

        case .threadNameUpdated:
            // Title updates don't have a dedicated AgentEvent and we can't
            // safely overwrite phase/summary here (would clobber running or
            // waiting-for-approval state).  Skip for now — the title is
            // populated at sessionStarted time which is usually enough.
            break

        case .turnStarted(let threadId, _):
            onEvent?(.activityUpdated(
                SessionActivityUpdated(
                    sessionID: threadId,
                    summary: "Codex is working…",
                    phase: .running,
                    timestamp: .now
                )
            ))

        case .turnCompleted(let threadId, let turn):
            // A turn completing doesn't end the thread — the user can send
            // another message.  Use activityUpdated(phase: .completed) so the
            // session stays visible as "Completed" rather than being torn
            // down.  `thread/closed` is the authoritative end signal.
            let summary: String
            switch turn.status {
            case .completed: summary = "Turn completed."
            case .interrupted: summary = "Turn interrupted."
            case .failed: summary = "Turn failed."
            case .inProgress: summary = "Turn in progress."
            }
            onEvent?(.activityUpdated(
                SessionActivityUpdated(
                    sessionID: threadId,
                    summary: summary,
                    phase: .completed,
                    timestamp: .now
                )
            ))

        case .unknown:
            break
        }
    }

    // MARK: - Helpers

    private func emitSessionStarted(from thread: CodexThread) {
        let workspaceName = CodexSessionDisplayResolver.workspaceName(for: thread.cwd)
        let title = CodexSessionDisplayResolver.sessionTitle(
            cwd: thread.cwd,
            threadName: thread.name,
            sessionID: thread.id
        )
        let summary = thread.preview.isEmpty ? "Codex session." : String(thread.preview.prefix(120))

        let phase: SessionPhase
        switch thread.status.type {
        case .active: phase = .running
        case .idle: phase = .completed
        case .notLoaded, .systemError: phase = .completed
        }

        onEvent?(.sessionStarted(
            SessionStarted(
                sessionID: thread.id,
                title: title,
                tool: .codex,
                origin: .live,
                initialPhase: phase,
                summary: summary,
                timestamp: .now,
                jumpTarget: JumpTarget(
                    terminalApp: "Codex.app",
                    workspaceName: workspaceName,
                    paneTitle: title,
                    workingDirectory: thread.cwd,
                    codexThreadID: thread.id
                ),
                codexMetadata: CodexSessionMetadata(
                    transcriptPath: thread.path,
                    initialUserPrompt: thread.preview.isEmpty ? nil : thread.preview
                )
            )
        ))
    }

    private func startHealthCheckLoop() {
        healthCheckTask?.cancel()
        healthCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: Self.healthCheckInterval)
                guard !Task.isCancelled else { return }
                guard self.isConnected, self.client != nil else { continue }

                await self.syncCurrentThreads()
                if !self.isConnected {
                    return
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else {
            return
        }

        reconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }

            var delay = Self.reconnectDelay
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                guard ProcessMonitoringCoordinator.isCodexDesktopAppRunning() else {
                    self.connectionState = .disconnected
                    self.reconnectTask = nil
                    return
                }

                self.connectTask = nil
                self.ensureConnected()

                if self.isConnected {
                    self.reconnectTask = nil
                    return
                }

                delay = min(delay * 2, Self.maxReconnectDelay)
            }
        }
    }

    private func handleConnectionLossIfNeeded(reason: String) {
        guard isConnected || connectTask != nil else {
            return
        }

        client?.stop()
        client = nil
        isConnected = false
        connectTask?.cancel()
        connectTask = nil
        healthCheckTask?.cancel()
        healthCheckTask = nil

        guard ProcessMonitoringCoordinator.isCodexDesktopAppRunning() else {
            connectionState = .disconnected
            return
        }

        connectionState = .reconnecting
        onStatusMessage?(reason)
        scheduleReconnect()
    }
}
