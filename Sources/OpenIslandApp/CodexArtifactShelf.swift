import Foundation
import OpenIslandCore

enum CodexShelfArtifactType: String, Equatable, Sendable {
    case code
    case document
    case image
    case log
    case patch
    case report
    case generic

    var label: String {
        switch self {
        case .code:
            "Code"
        case .document:
            "Doc"
        case .image:
            "Image"
        case .log:
            "Log"
        case .patch:
            "Patch"
        case .report:
            "Report"
        case .generic:
            "File"
        }
    }

    var symbolName: String {
        switch self {
        case .code:
            "chevron.left.forwardslash.chevron.right"
        case .document:
            "doc.text"
        case .image:
            "photo"
        case .log:
            "list.bullet.rectangle"
        case .patch:
            "square.and.pencil"
        case .report:
            "text.badge.checkmark"
        case .generic:
            "doc"
        }
    }

    static func infer(
        fromPath path: String
    ) -> CodexShelfArtifactType {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "swift", "m", "mm", "h", "c", "cc", "cpp", "hpp", "rs", "go", "py", "js", "jsx", "ts", "tsx", "java", "kt", "kts", "rb", "php", "cs", "scala", "sh", "zsh", "bash", "json", "yaml", "yml", "toml", "xml", "plist", "md", "txt":
            return .code
        case "ppt", "pptx", "doc", "docx", "pdf", "xls", "xlsx", "csv", "tsv":
            return .document
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svg":
            return .image
        case "log", "out", "trace":
            return .log
        case "patch", "diff":
            return .patch
        case "report":
            return .report
        default:
            break
        }

        let lowerPath = path.lowercased()
        if lowerPath.contains("report") || lowerPath.contains("summary") {
            return .report
        }
        if lowerPath.contains("screenshot") || lowerPath.contains("screen-shot") {
            return .image
        }
        return .generic
    }
}

enum CodexShelfArtifactSource: String, Equatable, Sendable {
    case created
    case modified
    case generated
    case debug
    case referenced

    var label: String {
        switch self {
        case .created:
            "Created"
        case .modified:
            "Modified"
        case .generated:
            "Generated"
        case .debug:
            "Debug Log"
        case .referenced:
            "Referenced"
        }
    }

    var isVisibleByDefault: Bool {
        switch self {
        case .created, .modified, .generated:
            true
        case .debug, .referenced:
            false
        }
    }
}

struct CodexShelfItem: Identifiable, Equatable, Sendable {
    let id: String
    let path: String
    let fileName: String
    let artifactType: CodexShelfArtifactType
    let source: CodexShelfArtifactSource
    let projectName: String
    let sourceSessionID: String
    let discoveredAt: Date
    let modifiedAt: Date
}

enum CodexShelfPathExtractor {
    static func extractCandidatePaths(
        from event: AgentEvent,
        session: AgentSession
    ) -> [String] {
        var texts: [String] = []
        var explicitPaths: [String] = []

        switch event {
        case let .permissionRequested(payload):
            if !payload.request.summary.isEmpty {
                texts.append(payload.request.summary)
            }
            if !payload.request.affectedPath.isEmpty {
                explicitPaths.append(payload.request.affectedPath)
            }
        case let .activityUpdated(payload):
            texts.append(payload.summary)
        case let .sessionCompleted(payload):
            texts.append(payload.summary)
        case let .sessionMetadataUpdated(payload):
            if let preview = payload.codexMetadata.currentCommandPreview, !preview.isEmpty {
                texts.append(preview)
            }
            if let assistant = payload.codexMetadata.lastAssistantMessage, !assistant.isEmpty {
                texts.append(assistant)
            }
        default:
            break
        }

        if let preview = session.currentCommandPreviewText, !preview.isEmpty {
            texts.append(preview)
        }
        texts.append(session.summary)
        if let assistant = session.lastAssistantMessageText, !assistant.isEmpty {
            texts.append(assistant)
        }

        var candidates = explicitPaths
        for text in texts {
            candidates.append(contentsOf: extractPathLikeTokens(from: text))
        }

        return deduplicated(candidates)
    }

    static func resolveExistingFilePath(
        from candidate: String,
        workingDirectory: String?
    ) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let fm = FileManager.default
        let expanded = (trimmed as NSString).expandingTildeInPath

        if let fileURLPath = pathFromFileURLString(expanded),
           fileExists(fileURLPath, fileManager: fm) {
            return standardizedPath(fileURLPath)
        }

        if expanded.hasPrefix("/") {
            return fileExists(expanded, fileManager: fm) ? standardizedPath(expanded) : nil
        }

        if let workingDirectory, !workingDirectory.isEmpty {
            let joined = URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: workingDirectory))
                .standardizedFileURL
                .path
            if fileExists(joined, fileManager: fm) {
                return joined
            }
        }

        return nil
    }
}

private extension CodexShelfPathExtractor {
    static func extractPathLikeTokens(from text: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines
        let quoteAndPunctuation = CharacterSet(charactersIn: "\"'`()[]{}<>,;")
        let trailingNoise = CharacterSet(charactersIn: ".,:!?")

        return text
            .components(separatedBy: separators)
            .compactMap { rawToken -> String? in
                var token = rawToken
                    .trimmingCharacters(in: quoteAndPunctuation)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                while let lastScalar = token.unicodeScalars.last,
                      trailingNoise.contains(lastScalar) {
                    token.removeLast()
                }

                guard looksLikePath(token) else {
                    return nil
                }
                return token
            }
    }

    static func looksLikePath(_ token: String) -> Bool {
        guard !token.isEmpty else {
            return false
        }
        if token.hasPrefix("$") || token.hasPrefix("-") {
            return false
        }
        if token.hasPrefix("http://") || token.hasPrefix("https://") {
            return false
        }
        if token.hasPrefix("file://") {
            return true
        }
        if token.hasPrefix("/") || token.hasPrefix("~/") {
            return true
        }

        if token.contains("/") {
            return true
        }

        let ext = URL(fileURLWithPath: token).pathExtension
        return !ext.isEmpty
    }

    static func pathFromFileURLString(_ token: String) -> String? {
        guard token.hasPrefix("file://"),
              let url = URL(string: token),
              url.isFileURL else {
            return nil
        }
        return url.path
    }

    static func fileExists(_ path: String, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    static func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let key = value.lowercased()
            if seen.insert(key).inserted {
                result.append(value)
            }
        }
        return result
    }
}
