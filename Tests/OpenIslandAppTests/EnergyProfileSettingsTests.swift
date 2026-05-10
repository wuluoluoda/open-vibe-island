import Foundation
import Testing
@testable import OpenIslandApp

struct EnergyProfileSettingsTests {
    @Test
    func moduleDefaultsFollowGlobalProfile() {
        #expect(EnergyModule.jump.defaultProfile(for: .quiet) == .quiet)
        #expect(EnergyModule.jump.defaultProfile(for: .balanced) == .balanced)
        #expect(EnergyModule.jump.defaultProfile(for: .responsive) == .responsive)

        #expect(EnergyModule.usage.defaultProfile(for: .quiet) == .quiet)
        #expect(EnergyModule.usage.defaultProfile(for: .balanced) == .quiet)
        #expect(EnergyModule.usage.defaultProfile(for: .responsive) == .balanced)

        #expect(EnergyModule.attach.defaultProfile(for: .quiet) == .quiet)
        #expect(EnergyModule.attach.defaultProfile(for: .balanced) == .balanced)
        #expect(EnergyModule.attach.defaultProfile(for: .responsive) == .balanced)
    }

    @Test
    func moduleDescriptionKeysAreStable() {
        #expect(EnergyModule.jump.descriptionKey(for: .balanced) == "settings.energy.jump.balanced.desc")
        #expect(EnergyModule.usage.descriptionKey(for: .quiet) == "settings.energy.usage.quiet.desc")
        #expect(EnergyModule.attach.descriptionKey(for: .responsive) == "settings.energy.attach.responsive.desc")
        #expect(EnergyModule.codexLog.descriptionKey(for: .balanced) == "settings.energy.codexLog.balanced.desc")
        #expect(EnergyModule.hover.descriptionKey(for: .quiet) == "settings.energy.hover.quiet.desc")
    }

    @Test
    func usageRefreshIntervalsMatchProfiles() {
        let balancedInterval: Duration? = .seconds(300)
        let responsiveInterval: Duration? = .seconds(60)

        #expect(HookInstallationCoordinator.usageRefreshInterval(for: .quiet) == nil)
        #expect(HookInstallationCoordinator.usageRefreshInterval(for: .balanced) == balancedInterval)
        #expect(HookInstallationCoordinator.usageRefreshInterval(for: .responsive) == responsiveInterval)
    }
}
