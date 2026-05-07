import Foundation
import OpenIslandCore

/// Extended runtime status used by the Codex-focused island surfaces.
///
/// Keep this model centralized so UI views read a single derived value rather
/// than re-implementing conditionals in multiple places.
enum CodexOperationalStatus: Equatable {
    case waitingApproval
    case waitingInput
    case reconnecting
    case connecting
    case interrupted
    case detached
    case stalled
    case loopSuspected
    case running
    case recentlyCompleted
    case completed

    /// Higher value means higher display priority.
    var priority: Int {
        switch self {
        case .waitingApproval: 1_000
        case .waitingInput: 900
        case .reconnecting: 800
        case .connecting: 790
        case .interrupted: 700
        case .detached: 650
        case .stalled: 600
        case .loopSuspected: 500
        case .running: 400
        case .recentlyCompleted: 300
        case .completed: 200
        }
    }

    /// Priority used for project-level radar ordering.
    ///
    /// Connecting/reconnecting are global transport hints and can briefly flicker
    /// while Codex.app/app-server reconnects.  Keep their visible label/color, but
    /// do not let that volatile global signal reorder projects ahead of stable
    /// per-session states such as interrupted or detached.
    var radarSortPriority: Int {
        switch self {
        case .reconnecting, .connecting:
            400
        default:
            priority
        }
    }

    var label: String {
        switch self {
        case .waitingApproval: "Waiting Approval"
        case .waitingInput: "Waiting Input"
        case .reconnecting: "Reconnecting"
        case .connecting: "Connecting"
        case .interrupted: "Interrupted"
        case .detached: "Detached"
        case .stalled: "Stalled"
        case .loopSuspected: "Loop Suspected"
        case .running: "Running"
        case .recentlyCompleted, .completed: "Completed"
        }
    }

    /// True for advisory statuses that should be rendered as weak hints.
    var isWeakWarning: Bool {
        switch self {
        case .stalled, .loopSuspected:
            true
        default:
            false
        }
    }

    var requiresUserAction: Bool {
        switch self {
        case .waitingApproval, .waitingInput, .reconnecting, .connecting, .interrupted, .detached:
            true
        case .stalled, .loopSuspected, .running, .recentlyCompleted, .completed:
            false
        }
    }
}

struct CodexOperationalStatusSignals {
    var now: Date
    var bridgeConnectionState: RuntimeConnectionState
    var codexAppServerConnectionState: RuntimeConnectionState
    var stalledThreshold: TimeInterval
    var loopSuspectedEnabled: Bool
    var loopRepeatCount: Int
    var loopSuspectedThreshold: Int
    var recentCompletionWindow: TimeInterval

    static let `default` = CodexOperationalStatusSignals(
        now: .now,
        bridgeConnectionState: .connected,
        codexAppServerConnectionState: .connected,
        stalledThreshold: 12 * 60,
        loopSuspectedEnabled: false,
        loopRepeatCount: 0,
        loopSuspectedThreshold: 4,
        recentCompletionWindow: 20 * 60
    )
}

extension AgentSession {
    /// Derive the extended Codex operational status.
    ///
    /// Trigger conditions:
    /// - `connecting/reconnecting`: Codex.app app-server or local bridge is in
    ///   a connecting state while this session is running and recently active.
    /// - `interrupted`: latest completed turn is explicitly marked interrupted
    ///   and the current completion summary still describes an interruption.
    /// - `detached`: session exists but terminal/thread attachment is lost.
    /// - `stalled`: running + process alive + no event update for threshold.
    /// - `loopSuspected`: repeated same command/failure fingerprint crossed
    ///   configured threshold (kept optional and conservative).
    func codexOperationalStatus(
        signals: CodexOperationalStatusSignals
    ) -> CodexOperationalStatus {
        switch phase {
        case .waitingForApproval:
            return .waitingApproval
        case .waitingForAnswer:
            return .waitingInput
        case .running, .completed:
            break
        }

        if phase == .completed && lastTurnInterrupted && summarySuggestsInterruption(summary) {
            return .interrupted
        }

        if isDetachedFromRuntime {
            return .detached
        }

        if shouldShowReconnecting(using: signals) {
            return .reconnecting
        }
        if shouldShowConnecting(using: signals) {
            return .connecting
        }

        if isRunningAndStalled(using: signals) {
            return .stalled
        }

        if signals.loopSuspectedEnabled
            && phase == .running
            && signals.loopRepeatCount >= signals.loopSuspectedThreshold {
            return .loopSuspected
        }

        if phase == .running {
            return .running
        }

        let completionAge = max(0, signals.now.timeIntervalSince(updatedAt))
        if completionAge <= signals.recentCompletionWindow {
            return .recentlyCompleted
        }

        return .completed
    }

    private func shouldShowConnecting(using signals: CodexOperationalStatusSignals) -> Bool {
        guard isActiveRunningSessionForConnectionSignal(using: signals) else {
            return false
        }

        if isCodexAppSession && tool == .codex {
            return signals.codexAppServerConnectionState == .connecting
        }

        return isTrackedLiveSession
            && signals.bridgeConnectionState == .connecting
    }

    private func shouldShowReconnecting(using signals: CodexOperationalStatusSignals) -> Bool {
        guard isActiveRunningSessionForConnectionSignal(using: signals) else {
            return false
        }

        if isCodexAppSession && tool == .codex {
            return signals.codexAppServerConnectionState == .reconnecting
        }

        return isTrackedLiveSession
            && signals.bridgeConnectionState == .reconnecting
    }

    private func isActiveRunningSessionForConnectionSignal(using signals: CodexOperationalStatusSignals) -> Bool {
        guard phase == .running else {
            return false
        }

        let inactiveAge = max(0, signals.now.timeIntervalSince(updatedAt))
        return inactiveAge < signals.stalledThreshold
    }

    private var isDetachedFromRuntime: Bool {
        if isCodexAppSession && tool == .codex {
            return jumpTarget?.codexThreadID == nil
                && phase != .completed
        }

        if attachmentState == .detached {
            return true
        }

        return isTrackedLiveSession
            && !isDemoSession
            && jumpTarget == nil
            && phase != .completed
    }

    private func isRunningAndStalled(using signals: CodexOperationalStatusSignals) -> Bool {
        guard phase == .running, isProcessAlive else {
            return false
        }

        return signals.now.timeIntervalSince(updatedAt) >= signals.stalledThreshold
    }

    private func summarySuggestsInterruption(_ summary: String) -> Bool {
        let normalized = summary.lowercased()
        return normalized.contains("interrupted")
            || normalized.contains("aborted")
            || normalized.contains("cancelled")
            || normalized.contains("canceled")
    }
}
