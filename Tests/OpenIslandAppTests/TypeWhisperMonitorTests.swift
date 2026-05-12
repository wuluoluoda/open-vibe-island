import Foundation
import Testing
@testable import OpenIslandApp

struct TypeWhisperMonitorTests {
    @Test
    func lowFootprintOverridesStaleLoadedModelPreference() {
        let snapshot = typeWhisperSnapshot(
            loadedModel: "qwen3-asr-1.7b-6bit",
            memoryMegabytes: 26
        )

        #expect(snapshot.resolvedLoadState == .unloaded)
    }

    @Test
    func highFootprintMarksModelLoadedWithoutTrustingPreferenceOnly() {
        let snapshot = typeWhisperSnapshot(
            loadedModel: nil,
            memoryMegabytes: 2_048
        )

        #expect(snapshot.resolvedLoadState == .loaded)
    }

    @Test
    func loadedModelPreferenceProvidesLowEnergyLoadedSignalWhenMemoryIsUnknown() {
        let snapshot = typeWhisperSnapshot(
            loadedModel: "qwen3-asr-1.7b-6bit",
            memoryMegabytes: nil
        )

        #expect(snapshot.resolvedLoadState == .loaded)
    }

    @Test
    func nonRunningProcessWinsOverPreferencesAndMemory() {
        let snapshot = typeWhisperSnapshot(
            isRunning: false,
            loadedModel: "qwen3-asr-1.7b-6bit",
            memoryMegabytes: 2_048
        )

        #expect(snapshot.resolvedLoadState == .notRunning)
    }

    @Test
    func footprintParserHandlesCommonUnits() {
        #expect(TypeWhisperMonitor.parsePhysFootprintMegabytes(
            from: "phys_footprint: 2.0G\n"
        ) == 2_048)

        #expect(TypeWhisperMonitor.parsePhysFootprintMegabytes(
            from: "phys_footprint: 26M\n"
        ) == 26)

        #expect(TypeWhisperMonitor.parsePhysFootprintMegabytes(
            from: "phys_footprint: 512K\n"
        ) == 0.5)
    }

    @Test
    func footprintCadenceStaysLowFrequency() {
        #expect(TypeWhisperMonitor.preferencePollingCadence(for: .quiet) == .seconds(60))
        #expect(TypeWhisperMonitor.preferencePollingCadence(for: .balanced) == .seconds(45))
        #expect(TypeWhisperMonitor.preferencePollingCadence(for: .responsive) == .seconds(30))

        #expect(TypeWhisperMonitor.footprintPollingInterval(for: .quiet) == 600)
        #expect(TypeWhisperMonitor.footprintPollingInterval(for: .balanced) == 600)
        #expect(TypeWhisperMonitor.footprintPollingInterval(for: .responsive) == 300)
    }

    @Test
    func loadedSinceCarriesAcrossLoadedSamplesForSameProcess() {
        let firstLoadedAt = Date(timeIntervalSince1970: 1_000)
        let previous = typeWhisperSnapshot(
            loadedModel: "qwen3-asr-1.7b-6bit",
            memoryMegabytes: 2_048,
            loadedSince: firstLoadedAt
        )
        let next = typeWhisperSnapshot(
            loadedModel: "qwen3-asr-1.7b-6bit",
            memoryMegabytes: 2_048,
            loadedSince: nil
        )

        let reconciled = TypeWhisperMonitor.reconcileLoadedTiming(
            previous: previous,
            next: next,
            now: firstLoadedAt.addingTimeInterval(60)
        )

        #expect(reconciled.loadedSince == firstLoadedAt)
    }

    @Test
    func cachedFootprintOnlyReusesForSamePreferenceState() {
        let unloadedMemory = typeWhisperSnapshot(
            loadedModel: nil,
            memoryMegabytes: 26
        )
        let loadedPreference = typeWhisperSnapshot(
            loadedModel: "qwen3-asr-1.7b-6bit",
            memoryMegabytes: nil
        )
        let unchangedPreference = typeWhisperSnapshot(
            loadedModel: nil,
            memoryMegabytes: nil
        )

        #expect(!TypeWhisperMonitor.canReuseMemoryFootprint(
            previous: unloadedMemory,
            next: loadedPreference
        ))
        #expect(TypeWhisperMonitor.canReuseMemoryFootprint(
            previous: unloadedMemory,
            next: unchangedPreference
        ))
    }

    @Test
    @MainActor
    func stopMonitoringCanClearSnapshotForDisabledFeature() {
        let monitor = TypeWhisperMonitor()
        monitor.snapshot = typeWhisperSnapshot(
            loadedModel: "qwen3-asr-1.7b-6bit",
            memoryMegabytes: 2_048
        )

        monitor.stopMonitoring(resetSnapshot: true)

        #expect(monitor.snapshot == .empty)
        #expect(!monitor.isRefreshingFootprint)
    }
}

private func typeWhisperSnapshot(
    isRunning: Bool = true,
    loadedModel: String? = nil,
    memoryMegabytes: Double? = nil,
    loadedSince: Date? = nil
) -> TypeWhisperSnapshot {
    TypeWhisperSnapshot(
        updatedAt: Date(timeIntervalSince1970: 1_000),
        preferenceURL: TypeWhisperSnapshot.defaultPreferenceURL,
        hasPreferences: true,
        appInstalled: true,
        isRunning: isRunning,
        processID: isRunning ? 123 : nil,
        selectedEngine: "qwen3",
        selectedModel: "qwen3-asr-1.7b-6bit",
        modelAutoUnloadSeconds: 300,
        apiServerEnabled: false,
        loadedModelFromPreferences: loadedModel,
        setupWizardCompleted: true,
        hybridHotkey: "Option + Space",
        memoryFootprintMegabytes: memoryMegabytes,
        memoryCheckedAt: memoryMegabytes == nil ? nil : Date(timeIntervalSince1970: 1_000),
        memoryError: nil,
        loadedSince: loadedSince
    )
}
