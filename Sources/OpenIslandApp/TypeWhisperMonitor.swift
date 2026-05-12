import Foundation

enum TypeWhisperModelLoadState: Equatable, Sendable {
    case notRunning
    case unloaded
    case loaded
}

struct TypeWhisperSnapshot: Equatable, Sendable {
    var updatedAt: Date
    var preferenceURL: URL
    var hasPreferences: Bool
    var appInstalled: Bool
    var isRunning: Bool
    var processID: Int32?
    var selectedEngine: String?
    var selectedModel: String?
    var modelAutoUnloadSeconds: Int?
    var apiServerEnabled: Bool
    var loadedModelFromPreferences: String?
    var setupWizardCompleted: Bool?
    var hybridHotkey: String?
    var memoryFootprintMegabytes: Double?
    var memoryCheckedAt: Date?
    var memoryError: String?
    var loadedSince: Date?

    static let unloadedFootprintThresholdMegabytes = 300.0
    static let loadedFootprintThresholdMegabytes = 1_024.0

    static var empty: TypeWhisperSnapshot {
        TypeWhisperSnapshot(
            updatedAt: .distantPast,
            preferenceURL: Self.defaultPreferenceURL,
            hasPreferences: false,
            appInstalled: false,
            isRunning: false,
            processID: nil,
            selectedEngine: nil,
            selectedModel: nil,
            modelAutoUnloadSeconds: nil,
            apiServerEnabled: false,
            loadedModelFromPreferences: nil,
            setupWizardCompleted: nil,
            hybridHotkey: nil,
            memoryFootprintMegabytes: nil,
            memoryCheckedAt: nil,
            memoryError: nil,
            loadedSince: nil
        )
    }

    static var defaultPreferenceURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.typewhisper.mac.plist")
    }

    var shouldSurface: Bool {
        appInstalled || hasPreferences || isRunning
    }

    var effectiveModelName: String? {
        loadedModelFromPreferences?.nonEmpty ?? selectedModel?.nonEmpty
    }

    var resolvedLoadState: TypeWhisperModelLoadState {
        guard isRunning else {
            return .notRunning
        }

        if let memoryFootprintMegabytes {
            if memoryFootprintMegabytes < Self.unloadedFootprintThresholdMegabytes {
                return .unloaded
            }
            if memoryFootprintMegabytes >= Self.loadedFootprintThresholdMegabytes {
                return .loaded
            }
        }

        if loadedModelFromPreferences?.nonEmpty != nil {
            return .loaded
        }

        return .unloaded
    }

    var isLoaded: Bool {
        resolvedLoadState == .loaded
    }

    var presentationKey: String {
        [
            shouldSurface.description,
            isRunning.description,
            String(processID ?? -1),
            "\(resolvedLoadState)",
            selectedEngine ?? "",
            effectiveModelName ?? "",
            modelAutoUnloadSeconds.map(String.init) ?? "",
            apiServerEnabled.description,
            memoryFootprintMegabytes.map { String(Int($0.rounded())) } ?? "",
            memoryError ?? "",
        ].joined(separator: "|")
    }
}

@MainActor
@Observable
final class TypeWhisperMonitor {
    var snapshot: TypeWhisperSnapshot = .empty {
        didSet {
            guard snapshot.presentationKey != oldValue.presentationKey else {
                return
            }
            onSnapshotChanged?()
        }
    }
    var energyProfile: EnergyProfile = .balanced
    var isRefreshingFootprint = false

    @ObservationIgnored
    private var monitorTask: Task<Void, Never>?

    @ObservationIgnored
    private var lastAutomaticFootprintDate: Date?

    @ObservationIgnored
    var onSnapshotChanged: (() -> Void)?

    func startMonitoringIfNeeded() {
        guard monitorTask == nil else {
            return
        }

        monitorTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.refresh()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.preferencePollingCadence(for: self.energyProfile))
                } catch {
                    break
                }
                guard !Task.isCancelled else {
                    break
                }
                await self.refresh()
            }
        }
    }

    func stopMonitoring(resetSnapshot: Bool = false) {
        monitorTask?.cancel()
        monitorTask = nil
        lastAutomaticFootprintDate = nil
        isRefreshingFootprint = false
        if resetSnapshot {
            snapshot = .empty
        }
    }

    func refreshFootprintNow() {
        Task { @MainActor [weak self] in
            await self?.refresh(forceFootprint: true)
        }
    }

    func refresh(forceFootprint: Bool = false, now: Date = Date()) async {
        guard !Task.isCancelled else {
            return
        }

        let previous = snapshot
        var next = await Task.detached(priority: .utility) {
            Self.collectBaseSnapshot(now: now)
        }.value

        guard !Task.isCancelled else {
            return
        }

        if Self.canReuseMemoryFootprint(previous: previous, next: next) {
            next.memoryFootprintMegabytes = previous.memoryFootprintMegabytes
            next.memoryCheckedAt = previous.memoryCheckedAt
            next.memoryError = previous.memoryError
        }

        let shouldCollectFootprint = Self.shouldCollectFootprint(
            force: forceFootprint,
            snapshot: next,
            lastCollectedAt: lastAutomaticFootprintDate,
            now: now,
            energyProfile: energyProfile
        )

        if shouldCollectFootprint, let processID = next.processID {
            isRefreshingFootprint = true
            let footprint = await Task.detached(priority: .utility) {
                Self.collectFootprint(processID: processID)
            }.value
            isRefreshingFootprint = false

            guard !Task.isCancelled else {
                return
            }

            switch footprint {
            case let .success(megabytes):
                next.memoryFootprintMegabytes = megabytes
                next.memoryCheckedAt = now
                next.memoryError = nil
            case let .failure(error):
                next.memoryFootprintMegabytes = nil
                next.memoryCheckedAt = now
                next.memoryError = error.localizedDescription
            }

            if !forceFootprint {
                lastAutomaticFootprintDate = now
            }
        }

        snapshot = Self.reconcileLoadedTiming(previous: previous, next: next, now: now)
    }

    nonisolated static func canReuseMemoryFootprint(
        previous: TypeWhisperSnapshot,
        next: TypeWhisperSnapshot
    ) -> Bool {
        next.isRunning
            && next.processID == previous.processID
            && next.selectedEngine == previous.selectedEngine
            && next.selectedModel == previous.selectedModel
            && next.loadedModelFromPreferences == previous.loadedModelFromPreferences
    }

    nonisolated static func preferencePollingCadence(for profile: EnergyProfile) -> Duration {
        switch profile {
        case .quiet:
            .seconds(60)
        case .balanced:
            .seconds(45)
        case .responsive:
            .seconds(30)
        }
    }

    nonisolated static func footprintPollingInterval(for profile: EnergyProfile) -> TimeInterval {
        switch profile {
        case .quiet, .balanced:
            10 * 60
        case .responsive:
            5 * 60
        }
    }

    nonisolated static func shouldCollectFootprint(
        force: Bool,
        snapshot: TypeWhisperSnapshot,
        lastCollectedAt: Date?,
        now: Date,
        energyProfile: EnergyProfile
    ) -> Bool {
        guard snapshot.isRunning else {
            return false
        }

        if force {
            return true
        }

        guard let lastCollectedAt else {
            return true
        }

        return now.timeIntervalSince(lastCollectedAt) >= footprintPollingInterval(for: energyProfile)
    }

    nonisolated static func reconcileLoadedTiming(
        previous: TypeWhisperSnapshot,
        next: TypeWhisperSnapshot,
        now: Date
    ) -> TypeWhisperSnapshot {
        var reconciled = next
        guard next.isLoaded else {
            reconciled.loadedSince = nil
            return reconciled
        }

        if previous.isLoaded, previous.processID == next.processID {
            reconciled.loadedSince = previous.loadedSince ?? now
        } else {
            reconciled.loadedSince = now
        }
        return reconciled
    }

    nonisolated static func parsePhysFootprintMegabytes(from output: String) -> Double? {
        for line in output.split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard text.lowercased().contains("phys_footprint:"),
                  let range = text.range(of: ":") else {
                continue
            }

            let valueText = String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let megabytes = parseMemoryMegabytes(from: valueText) {
                return megabytes
            }
        }

        return nil
    }

    nonisolated private static func collectBaseSnapshot(now: Date) -> TypeWhisperSnapshot {
        let preferenceURL = TypeWhisperSnapshot.defaultPreferenceURL
        let preferences = TypeWhisperPreferences.load(from: preferenceURL)
        let processID = runningProcessID()
        let appInstalled = FileManager.default.fileExists(atPath: "/Applications/TypeWhisper.app")

        return TypeWhisperSnapshot(
            updatedAt: now,
            preferenceURL: preferenceURL,
            hasPreferences: preferences.exists,
            appInstalled: appInstalled,
            isRunning: processID != nil,
            processID: processID,
            selectedEngine: preferences.selectedEngine,
            selectedModel: preferences.selectedModel,
            modelAutoUnloadSeconds: preferences.modelAutoUnloadSeconds,
            apiServerEnabled: preferences.apiServerEnabled ?? false,
            loadedModelFromPreferences: preferences.loadedModel,
            setupWizardCompleted: preferences.setupWizardCompleted,
            hybridHotkey: preferences.hybridHotkey,
            memoryFootprintMegabytes: nil,
            memoryCheckedAt: nil,
            memoryError: nil,
            loadedSince: nil
        )
    }

    nonisolated private static func runningProcessID() -> Int32? {
        guard let result = try? runProcess(
            "/usr/bin/pgrep",
            arguments: ["-x", "TypeWhisper"]
        ), result.exitStatus == 0 else {
            return nil
        }

        return result.output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .first
    }

    nonisolated private static func collectFootprint(processID: Int32) -> Result<Double, Error> {
        do {
            let result = try runProcess(
                "/usr/bin/footprint",
                arguments: ["-summary", "-pid", "\(processID)"]
            )
            guard let megabytes = parsePhysFootprintMegabytes(from: result.output) else {
                throw TypeWhisperMonitorError.unparseableFootprint
            }
            return .success(megabytes)
        } catch {
            return .failure(error)
        }
    }

    nonisolated private static func parseMemoryMegabytes(from valueText: String) -> Double? {
        let pattern = #"([0-9][0-9,]*(?:\.[0-9]+)?)\s*([KMGT]?)(?:B|iB)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(valueText.startIndex..<valueText.endIndex, in: valueText)
        guard let match = regex.firstMatch(in: valueText, range: range),
              let valueRange = Range(match.range(at: 1), in: valueText) else {
            return nil
        }

        let numericText = valueText[valueRange].replacingOccurrences(of: ",", with: "")
        guard let value = Double(numericText) else {
            return nil
        }

        let unit: String
        if match.range(at: 2).location != NSNotFound,
           let unitRange = Range(match.range(at: 2), in: valueText) {
            unit = String(valueText[unitRange]).uppercased()
        } else {
            unit = "M"
        }

        switch unit {
        case "T":
            return value * 1_024 * 1_024
        case "G":
            return value * 1_024
        case "K":
            return value / 1_024
        default:
            return value
        }
    }

    nonisolated private static func runProcess(
        _ executablePath: String,
        arguments: [String]
    ) throws -> (exitStatus: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        var combined = outputData
        combined.append(errorData)
        let output = String(data: combined, encoding: .utf8) ?? ""

        return (process.terminationStatus, output)
    }
}

private struct TypeWhisperPreferences: Equatable, Sendable {
    var exists: Bool
    var selectedEngine: String?
    var selectedModel: String?
    var modelAutoUnloadSeconds: Int?
    var apiServerEnabled: Bool?
    var loadedModel: String?
    var setupWizardCompleted: Bool?
    var hybridHotkey: String?

    static func load(from url: URL) -> TypeWhisperPreferences {
        guard let data = try? Data(contentsOf: url),
              let raw = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = raw as? [String: Any] else {
            return TypeWhisperPreferences(
                exists: false,
                selectedEngine: nil,
                selectedModel: nil,
                modelAutoUnloadSeconds: nil,
                apiServerEnabled: nil,
                loadedModel: nil,
                setupWizardCompleted: nil,
                hybridHotkey: nil
            )
        }

        return TypeWhisperPreferences(
            exists: true,
            selectedEngine: stringValue(dictionary["selectedEngine"]),
            selectedModel: stringValue(dictionary["selectedModel"]),
            modelAutoUnloadSeconds: intValue(dictionary["modelAutoUnloadSeconds"]),
            apiServerEnabled: boolValue(dictionary["apiServerEnabled"]),
            loadedModel: stringValue(dictionary["plugin.com.typewhisper.qwen3.loadedModel"]),
            setupWizardCompleted: boolValue(dictionary["setupWizardCompleted"]),
            hybridHotkey: stringValue(dictionary["hybridHotkey"])
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return trimmedNonEmpty(string)
        }
        if let data = value as? Data {
            return String(data: data, encoding: .utf8).flatMap(trimmedNonEmpty)
        }
        if let number = value as? NSNumber {
            return trimmedNonEmpty(number.stringValue)
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = stringValue(value) {
            return Int(string)
        }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = stringValue(value)?.lowercased() {
            switch string {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private static func trimmedNonEmpty(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum TypeWhisperMonitorError: LocalizedError {
    case unparseableFootprint

    var errorDescription: String? {
        switch self {
        case .unparseableFootprint:
            "Could not parse TypeWhisper phys_footprint."
        }
    }
}
