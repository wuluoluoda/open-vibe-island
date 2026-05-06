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
    case hover
    case notification
    case boot
}

enum TrackedEventIngress {
    case bridge
    case rollout
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
