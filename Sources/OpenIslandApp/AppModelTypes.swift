import AppKit
import CoreGraphics
import Foundation

enum NotchStatus: Equatable {
    case closed
    case opened
    case popping
}

enum NotchOpenReason: Equatable {
    case click
    case notification
    case boot
}

enum TrackedEventIngress {
    case bridge
    case rollout
}

enum SessionPersistenceScope: Hashable, Sendable {
    case codex
    case claude
    case openCode
    case cursor

    static let all: Set<SessionPersistenceScope> = [.codex, .claude, .openCode, .cursor]
}

enum EnergyProfile: Int, CaseIterable, Identifiable, Sendable {
    case quiet = 1
    case balanced = 2
    case responsive = 3

    var id: Int { rawValue }

    var activeMonitorCadence: Duration {
        switch self {
        case .quiet: .seconds(3)
        case .balanced: .seconds(2)
        case .responsive: .seconds(1)
        }
    }

    var quietMonitorCadence: Duration {
        switch self {
        case .quiet: .seconds(8)
        case .balanced: .seconds(5)
        case .responsive: .seconds(3)
        }
    }

    var idleMonitorCadence: Duration {
        switch self {
        case .quiet: .seconds(12)
        case .balanced: .seconds(8)
        case .responsive: .seconds(5)
        }
    }

    var jumpTargetCacheTTL: TimeInterval {
        switch self {
        case .quiet: 30
        case .balanced: 25
        case .responsive: 20
        }
    }

    var localizedDescriptionKey: String {
        switch self {
        case .quiet: "settings.energy.profile.quiet.desc"
        case .balanced: "settings.energy.profile.balanced.desc"
        case .responsive: "settings.energy.profile.responsive.desc"
        }
    }
}

enum EnergyModule: String, CaseIterable, Identifiable, Sendable {
    case jump
    case usage
    case attach
    case codexLog

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .jump: "settings.energy.module.jump"
        case .usage: "settings.energy.module.usage"
        case .attach: "settings.energy.module.attach"
        case .codexLog: "settings.energy.module.codexLog"
        }
    }

    func defaultProfile(for globalProfile: EnergyProfile) -> EnergyProfile {
        switch self {
        case .usage:
            globalProfile == .responsive ? .balanced : .quiet
        case .attach:
            globalProfile == .quiet ? .quiet : .balanced
        case .jump, .codexLog:
            globalProfile
        }
    }

    func descriptionKey(for profile: EnergyProfile) -> String {
        switch (self, profile) {
        case (.jump, .quiet): "settings.energy.jump.quiet.desc"
        case (.jump, .balanced): "settings.energy.jump.balanced.desc"
        case (.jump, .responsive): "settings.energy.jump.responsive.desc"
        case (.usage, .quiet): "settings.energy.usage.quiet.desc"
        case (.usage, .balanced): "settings.energy.usage.balanced.desc"
        case (.usage, .responsive): "settings.energy.usage.responsive.desc"
        case (.attach, .quiet): "settings.energy.attach.quiet.desc"
        case (.attach, .balanced): "settings.energy.attach.balanced.desc"
        case (.attach, .responsive): "settings.energy.attach.responsive.desc"
        case (.codexLog, .quiet): "settings.energy.codexLog.quiet.desc"
        case (.codexLog, .balanced): "settings.energy.codexLog.balanced.desc"
        case (.codexLog, .responsive): "settings.energy.codexLog.responsive.desc"
        }
    }
}

enum RuntimeConnectionState: String, Sendable {
    case disconnected
    case connecting
    case reconnecting
    case connected

    var isConnectingLike: Bool {
        switch self {
        case .connecting, .reconnecting:
            true
        case .disconnected, .connected:
            false
        }
    }
}

// MARK: - Island appearance

enum IslandAppearanceMode: String, CaseIterable, Identifiable {
    case `default`
    case custom

    var id: String { rawValue }
}

enum IslandClosedDisplayStyle: String, CaseIterable, Identifiable {
    case minimal
    case detailed

    var id: String { rawValue }
}

enum IslandPixelShapeStyle: String, CaseIterable, Identifiable {
    case bars
    case steps
    case blocks
    case custom

    var id: String { rawValue }
}
