import Foundation

public enum CodexSessionDisplayResolver {
    public static func workspaceName(for cwd: String) -> String {
        WorkspaceNameResolver.workspaceName(for: cwd)
    }

    public static func sessionTitle(
        cwd: String,
        threadName: String? = nil,
        sessionID: String? = nil
    ) -> String {
        let workspaceName = workspaceName(for: cwd)
        if let displayName = humanReadableThreadName(threadName, sessionID: sessionID) {
            return displayName
        }

        return "Codex · \(workspaceName)"
    }

    public static func paneTitle(
        cwd: String,
        threadName: String? = nil,
        sessionID: String? = nil
    ) -> String {
        humanReadableThreadName(threadName, sessionID: sessionID)
            ?? "Codex · \(workspaceName(for: cwd))"
    }

    private static func humanReadableThreadName(_ value: String?, sessionID: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let sessionID, trimmed.caseInsensitiveCompare(sessionID) == .orderedSame {
            return nil
        }

        if looksLikeSessionIdentifier(trimmed) {
            return nil
        }

        return trimmed
    }

    private static func looksLikeSessionIdentifier(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        if lowercased.hasPrefix("session-") || lowercased.hasPrefix("thread-") {
            return true
        }

        let scalars = Array(lowercased.unicodeScalars)
        guard scalars.count >= 24 else {
            return false
        }

        let allowed = CharacterSet(charactersIn: "0123456789abcdef-")
        let matchingCount = scalars.filter { allowed.contains($0) }.count
        return Double(matchingCount) / Double(scalars.count) > 0.85
    }
}
