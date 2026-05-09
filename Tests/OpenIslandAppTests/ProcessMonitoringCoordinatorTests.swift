import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct ProcessMonitoringCoordinatorTests {
    @Test
    func monitorSleepDurationStaysFastDuringStartup() {
        #expect(ProcessMonitoringCoordinator.monitorSleepDuration(
            for: [],
            isResolvingInitialLiveSessions: true
        ) == .seconds(2))
    }

    @Test
    func monitorSleepDurationBacksOffWhenIdle() {
        #expect(ProcessMonitoringCoordinator.monitorSleepDuration(
            for: [],
            isResolvingInitialLiveSessions: false
        ) == .seconds(8))
    }

    @Test
    func monitorSleepDurationStaysFastForActiveWork() {
        #expect(ProcessMonitoringCoordinator.monitorSleepDuration(
            for: [
                AgentSession(
                    id: "running",
                    title: "Running",
                    tool: .codex,
                    phase: .running,
                    summary: "Working",
                    updatedAt: .now
                ),
            ],
            isResolvingInitialLiveSessions: false
        ) == .seconds(2))
    }

    @Test
    func monitorSleepDurationUsesQuietCadenceForCompletedSessions() {
        #expect(ProcessMonitoringCoordinator.monitorSleepDuration(
            for: [
                AgentSession(
                    id: "completed",
                    title: "Completed",
                    tool: .codex,
                    phase: .completed,
                    summary: "Done",
                    updatedAt: .now
                ),
            ],
            isResolvingInitialLiveSessions: false
        ) == .seconds(5))
    }
}
