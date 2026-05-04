import SwiftUI
import OpenIslandCore

/// v6 Personalization tab.
///
/// Two concerns, one preview:
/// - **Right slot** — what shows on the right of the closed island.
/// - **Center label** — what shows in the middle on external displays.
///
/// Everything else (idle behavior, per-tool agent colors, spinner, custom
/// avatars) was cut in the v6 redesign round.
struct AppearanceSettingsPane: View {
    var model: AppModel
    @State private var previewMode: UnifiedBars.Mode = .idle
    @State private var previewLayout: V6ClosedLayout = .external
    @State private var previewAutoCycle: Bool = true

    private static let autoCycleOrder: [UnifiedBars.Mode] = [.idle, .running, .waiting]
    private static let autoCycleInterval: TimeInterval = 2.0

    private var lang: LanguageManager { model.lang }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                previewSection
                rightSlotSection
                centerLabelSection
                stateIndicatorSection
                sessionGroupSection
                sessionSortSection
                staleThresholdSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(red: 0.055, green: 0.055, blue: 0.06))
        .navigationTitle(lang.t("settings.tab.appearance"))
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        sectionHeader(title: lang.t("settings.appearance.preview"), note: nil)

        VStack(spacing: 14) {
            previewStage
            previewControls
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.115))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var previewStage: some View {
        let frameW: CGFloat = 420
        let frameH: CGFloat = 44
        let physicalNotchW: CGFloat = 180
        let pillHeight: CGFloat = 32

        return ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.16, blue: 0.19),
                    Color(red: 0.12, green: 0.12, blue: 0.14),
                ],
                startPoint: .top, endPoint: .bottom
            )

            if previewLayout == .macbook {
                // Physical hardware notch mock — pinned to the TOP of the
                // frame, same as the real physical cutout would sit at the
                // top of the display.
                V6ClosedPillShape()
                    .fill(Color.black)
                    .frame(width: physicalNotchW, height: pillHeight)
            }

            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                IslandPreviewPill(
                    mode: previewMode,
                    label: previewLabel,
                    rightSlot: previewRightContent,
                    layout: previewLayout,
                    physicalNotchWidth: physicalNotchW,
                    now: context.date
                )
            }
        }
        .frame(width: frameW, height: frameH)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var previewControls: some View {
        HStack(spacing: 10) {
            // Layout toggle
            Picker("", selection: $previewLayout) {
                Text(lang.t("settings.appearance.preview.external")).tag(V6ClosedLayout.external)
                Text(lang.t("settings.appearance.preview.macbook")).tag(V6ClosedLayout.macbook)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 160)

            Spacer(minLength: 8)

            // Auto-cycle toggle (default on — drives the state chips).
            monoChip(
                title: previewAutoCycle
                    ? lang.t("settings.appearance.state.auto.on")
                    : lang.t("settings.appearance.state.auto.off"),
                selected: previewAutoCycle
            ) {
                previewAutoCycle.toggle()
            }

            // Manual state chips — selecting one turns off auto-cycle.
            ForEach([UnifiedBars.Mode.idle, .running, .waiting], id: \.self) { mode in
                monoChip(title: title(for: mode), selected: !previewAutoCycle && previewMode == mode) {
                    previewAutoCycle = false
                    previewMode = mode
                }
            }
        }
        .onAppear(perform: restartAutoCycleTick)
        .onChange(of: previewAutoCycle) { _, on in
            if on { restartAutoCycleTick() }
        }
    }

    // Simple self-scheduling tick. We don't use `Timer.publish` so the
    // cycle halts cleanly when the pane disappears (the captured
    // `previewAutoCycle` state is read at each fire).
    private func restartAutoCycleTick() {
        guard previewAutoCycle else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoCycleInterval) {
            guard previewAutoCycle else { return }
            let order = Self.autoCycleOrder
            let current = order.firstIndex(of: previewMode) ?? 0
            let next = order[(current + 1) % order.count]
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45)) {
                previewMode = next
            }
            restartAutoCycleTick()
        }
    }

    // MARK: - 01 · Right slot

    @ViewBuilder
    private var rightSlotSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.rightSlot.title"),
            note: lang.t("settings.appearance.rightSlot.note")
        )

        HStack(spacing: 12) {
            rightSlotCard(.count,  icon: { CountBadgePreview(count: 3) },
                          title: lang.t("settings.appearance.rightSlot.count"))
            rightSlotCard(.agents, icon: { AgentsMiniGridPreview() },
                          title: lang.t("settings.appearance.rightSlot.agents"))
            rightSlotCard(.none,   icon: { Text("—")
                                      .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                      .foregroundStyle(V6Palette.paper.opacity(0.5)) },
                          title: lang.t("settings.appearance.rightSlot.none"))
        }
    }

    private func rightSlotCard<Content: View>(
        _ option: IslandRightSlot,
        @ViewBuilder icon: () -> Content,
        title: String
    ) -> some View {
        let selected = model.islandRightSlot == option
        return Button {
            model.islandRightSlot = option
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                    icon()
                }
                .frame(height: 56)

                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.07 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selected ? V6Palette.paper.opacity(0.9) : Color.white.opacity(0.08),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 02 · Center label

    @ViewBuilder
    private var centerLabelSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.centerLabel.title"),
            note: lang.t("settings.appearance.centerLabel.note")
        )

        HStack(spacing: 12) {
            centerLabelCard(.agentAction, sample: "Claude · editing")
            centerLabelCard(.sessionName,  sample: "open-island")
            centerLabelCard(.off,          sample: "—")
        }
    }

    private func centerLabelCard(_ option: IslandCenterLabel, sample: String) -> some View {
        let selected = model.islandCenterLabel == option
        let title: String = switch option {
        case .agentAction: lang.t("settings.appearance.centerLabel.agentAction")
        case .sessionName: lang.t("settings.appearance.centerLabel.sessionName")
        case .off:         lang.t("settings.appearance.centerLabel.off")
        }
        return Button {
            model.islandCenterLabel = option
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                    Text(sample)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(V6Palette.paper.opacity(option == .off ? 0.4 : 0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 12)
                }
                .frame(height: 56)

                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.07 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selected ? V6Palette.paper.opacity(0.9) : Color.white.opacity(0.08),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 03 · Session state

    @ViewBuilder
    private var stateIndicatorSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.stateIndicator.title"),
            note: lang.t("settings.appearance.stateIndicator.note")
        )

        HStack(spacing: 12) {
            stateIndicatorCard(.animatedDot)
            stateIndicatorCard(.bar)
            stateIndicatorCard(.glyph)
            stateIndicatorCard(.tint)
        }
    }

    private func stateIndicatorCard(_ option: IslandSessionStateIndicator) -> some View {
        optionCard(
            selected: model.islandSessionStateIndicator == option,
            title: title(for: option)
        ) {
            model.islandSessionStateIndicator = option
        } icon: {
            StateIndicatorPreview(option: option)
        }
    }

    // MARK: - 04 · Session grouping

    @ViewBuilder
    private var sessionGroupSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.sessionGroup.title"),
            note: lang.t("settings.appearance.sessionGroup.note")
        )

        HStack(spacing: 12) {
            ForEach(IslandSessionGroup.allCases) { option in
                optionCard(
                    selected: model.islandSessionGroup == option,
                    title: title(for: option)
                ) {
                    model.islandSessionGroup = option
                } icon: {
                    SessionGroupPreview(option: option)
                }
            }
        }
    }

    // MARK: - 05 · Session sorting

    @ViewBuilder
    private var sessionSortSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.sessionSort.title"),
            note: lang.t("settings.appearance.sessionSort.note")
        )

        HStack(spacing: 12) {
            ForEach(IslandSessionSort.allCases) { option in
                optionCard(
                    selected: model.islandSessionSort == option,
                    title: title(for: option)
                ) {
                    model.islandSessionSort = option
                } icon: {
                    SessionSortPreview(option: option)
                }
            }
        }
    }

    // MARK: - 06 · Done timeout

    @ViewBuilder
    private var staleThresholdSection: some View {
        sectionHeader(
            title: lang.t("settings.appearance.staleThreshold.title"),
            note: lang.t("settings.appearance.staleThreshold.note")
        )

        HStack(spacing: 12) {
            ForEach(IslandCompletedStaleThreshold.allCases) { option in
                optionCard(
                    selected: model.completedStaleThreshold == option,
                    title: title(for: option)
                ) {
                    model.completedStaleThreshold = option
                } icon: {
                    Text(title(for: option))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(V6Palette.paper.opacity(0.9))
                }
            }
        }
    }

    // MARK: - Helpers

    private func optionCard<Icon: View>(
        selected: Bool,
        title: String,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                    icon()
                }
                .frame(height: 56)

                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.07 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selected ? V6Palette.paper.opacity(0.9) : Color.white.opacity(0.08),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(title: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.55))
            if let note {
                Text(note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.38))
            }
        }
    }

    private func monoChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? V6Palette.ink : V6Palette.paper.opacity(0.7))
                .background(
                    Capsule().fill(
                        selected ? V6Palette.paper : Color.white.opacity(0.06)
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func title(for mode: UnifiedBars.Mode) -> String {
        switch mode {
        case .idle:    lang.t("settings.appearance.state.idle")
        case .running: lang.t("settings.appearance.state.running")
        case .waiting: lang.t("settings.appearance.state.waiting")
        }
    }

    private func title(for option: IslandSessionStateIndicator) -> String {
        switch option {
        case .animatedDot: lang.t("settings.appearance.stateIndicator.animatedDot")
        case .bar:         lang.t("settings.appearance.stateIndicator.bar")
        case .glyph:       lang.t("settings.appearance.stateIndicator.glyph")
        case .tint:        lang.t("settings.appearance.stateIndicator.tint")
        }
    }

    private func title(for option: IslandSessionGroup) -> String {
        switch option {
        case .none:    lang.t("settings.appearance.sessionGroup.none")
        case .state:   lang.t("settings.appearance.sessionGroup.state")
        case .agent:   lang.t("settings.appearance.sessionGroup.agent")
        case .project: lang.t("settings.appearance.sessionGroup.project")
        }
    }

    private func title(for option: IslandSessionSort) -> String {
        switch option {
        case .attention:  lang.t("settings.appearance.sessionSort.attention")
        case .lastUpdate: lang.t("settings.appearance.sessionSort.lastUpdate")
        }
    }

    private func title(for option: IslandCompletedStaleThreshold) -> String {
        switch option {
        case .twoMinutes:    lang.t("settings.appearance.staleThreshold.twoMinutes")
        case .fiveMinutes:   lang.t("settings.appearance.staleThreshold.fiveMinutes")
        case .tenMinutes:    lang.t("settings.appearance.staleThreshold.tenMinutes")
        case .twentyMinutes: lang.t("settings.appearance.staleThreshold.twentyMinutes")
        }
    }

    private var previewAgentCells: [AgentGridCell] {
        // Three Claude sessions, with one waiting when the preview mode is
        // `waiting` so the breathing tile is visible in the live preview.
        let claude = Color(hex: AgentTool.claudeCode.brandColorHex) ?? .white
        let waitingIdx = previewMode == .waiting ? 1 : -1
        return (0..<3).map { idx in
            if idx == waitingIdx {
                return .session(color: claude, state: .waiting)
            }
            return .session(color: claude, state: .running)
        }
    }

    private var previewLabel: String? {
        guard previewLayout == .external,
              model.islandCenterLabel != .off else { return nil }
        switch (previewMode, model.islandCenterLabel) {
        case (.idle, _):               return nil
        case (.waiting, _):            return "Permission needed"
        case (.running, .agentAction): return "Claude · editing"
        case (.running, .sessionName): return "open-island"
        case (.running, .off):         return nil
        }
    }

    private var previewRightContent: IslandRightSlotContent? {
        switch model.islandRightSlot {
        case .none: return nil
        case .count: return .count(3)
        case .agents:
            return .agents(previewAgentCells)
        }
    }
}

// MARK: - Small preview ornaments

private struct CountBadgePreview: View {
    let count: Int
    var body: some View {
        Text("×\(count)")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(V6Palette.paper)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(V6Palette.paper.opacity(0.14))
            )
            .overlay(
                Capsule().stroke(V6Palette.paper.opacity(0.35), lineWidth: 1)
            )
    }
}

private struct AgentsMiniGridPreview: View {
    var body: some View {
        let claude = Color(hex: AgentTool.claudeCode.brandColorHex) ?? .white
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(claude)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

private struct StateIndicatorPreview: View {
    let option: IslandSessionStateIndicator

    var body: some View {
        HStack(spacing: 8) {
            indicator
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(V6Palette.paper.opacity(option == .tint ? 0.55 : 0.22))
                .frame(width: 58, height: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(option == .tint ? Color(hex: AgentTool.codex.brandColorHex)?.opacity(0.22) ?? Color.white.opacity(0.08) : Color.clear)
        )
    }

    @ViewBuilder
    private var indicator: some View {
        let color = Color(hex: AgentTool.codex.brandColorHex) ?? V6Palette.paper
        switch option {
        case .animatedDot:
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.55), radius: 5)
        case .bar:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 4, height: 28)
        case .glyph:
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
        case .tint:
            Circle()
                .fill(V6Palette.paper.opacity(0.72))
                .frame(width: 10, height: 10)
        }
    }
}

private struct SessionGroupPreview: View {
    let option: IslandSessionGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch option {
            case .none:
                previewLine(width: 72, color: V6Palette.paper.opacity(0.42))
                previewLine(width: 54, color: V6Palette.paper.opacity(0.28))
                previewLine(width: 64, color: V6Palette.paper.opacity(0.22))
            case .state:
                groupBlock(width: 52)
                groupBlock(width: 70)
            case .agent:
                agentBlock(color: Color(hex: AgentTool.claudeCode.brandColorHex) ?? .white)
                agentBlock(color: Color(hex: AgentTool.codex.brandColorHex) ?? .white)
            case .project:
                groupBlock(width: 76)
                groupBlock(width: 46)
            }
        }
        .frame(width: 84, alignment: .leading)
    }

    private func previewLine(width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: width, height: 5)
    }

    private func groupBlock(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            previewLine(width: width * 0.48, color: V6Palette.paper.opacity(0.48))
            previewLine(width: width, color: V6Palette.paper.opacity(0.22))
        }
    }

    private func agentBlock(color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            previewLine(width: 54, color: V6Palette.paper.opacity(0.25))
        }
    }
}

private struct SessionSortPreview: View {
    let option: IslandSessionSort

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    Text(rows[index].rank)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(V6Palette.paper.opacity(0.55))
                        .frame(width: 12, alignment: .leading)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(rows[index].color)
                        .frame(width: rows[index].width, height: 5)
                }
            }
        }
        .frame(width: 82, alignment: .leading)
    }

    private var rows: [(rank: String, width: CGFloat, color: Color)] {
        switch option {
        case .attention:
            return [
                ("!", 62, Color(hex: AgentTool.claudeCode.brandColorHex) ?? .white),
                ("2", 48, V6Palette.paper.opacity(0.28)),
                ("3", 58, V6Palette.paper.opacity(0.2)),
            ]
        case .lastUpdate:
            return [
                ("1", 64, V6Palette.paper.opacity(0.38)),
                ("2", 56, V6Palette.paper.opacity(0.3)),
                ("3", 42, V6Palette.paper.opacity(0.22)),
            ]
        }
    }
}
