import AppKit
import Foundation

@MainActor
protocol CodexShelfFileActioning: Sendable {
    func openFile(at url: URL) -> Bool
    func revealFile(at url: URL) -> Bool
    func openDirectory(at url: URL) -> Bool
}

struct WorkspaceCodexShelfFileActions: CodexShelfFileActioning {
    func openFile(at url: URL) -> Bool {
        NSWorkspace.shared.open(url) || runOpen(arguments: [url.path])
    }

    func revealFile(at url: URL) -> Bool {
        runOpen(arguments: ["-R", url.path])
    }

    func openDirectory(at url: URL) -> Bool {
        NSWorkspace.shared.open(url) || runOpen(arguments: [url.path])
    }

    private func runOpen(arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
