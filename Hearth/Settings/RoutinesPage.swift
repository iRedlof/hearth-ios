import SwiftUI
import HearthKit

/// Routines settings page matching the approved v2 Android mock.
/// Enables learning, shows learned routines, and handles off-confirm dialog.
@MainActor
struct RoutinesPage: View {
    @State private var enabled: Bool
    @State private var routines: [RoutineEntry] = []
    @State private var showOffConfirm: Bool = false
    @Environment(\.colorScheme) private var scheme

    init() {
        _enabled = State(initialValue: HouseFeaturesStore.routinesEnabled)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Toggle row
                HearthGroup {
                    HearthRow(
                        icon: "arrow.triangle.2.circlepath",
                        hue: .purple,
                        title: "Learn my routines",
                        subtitle: "Shows a one-tap suggestion on your widget near the usual time"
                    ) {
                        HearthSwitch(isOn: Binding(
                            get: { enabled },
                            set: { newValue in
                                if !newValue && !routines.isEmpty {
                                    // Show off-confirm dialog
                                    showOffConfirm = true
                                } else {
                                    enabled = newValue
                                    HouseFeaturesStore.routinesEnabled = newValue
                                }
                            }
                        ))
                    }
                }
                .padding(.top, 20)

                // Disclaimer (always visible per 5b lesson)
                Text("Never runs on its own. Stays on this phone.")
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(HearthColor.sub(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HearthMetrics.groupInset + 12)

                // Learned section or learning state
                if enabled {
                    if routines.isEmpty {
                        learningStateCard
                    } else {
                        learnedSection
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .background(HearthColor.page(scheme))
        .navigationTitle("Routines")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Forget \(routines.count) routine\(routines.count == 1 ? "" : "s")?",
            isPresented: $showOffConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Turn off", role: .destructive) {
                enabled = false
                HouseFeaturesStore.routinesEnabled = false
                ActionHistoryStore.save([])
                routines = []
            }
        } message: {
            Text("Turning off learning forgets what Hearth learned. You can turn it on again later.")
        }
        .onAppear {
            loadRoutines()
        }
    }

    // MARK: - Subviews

    private var learningStateCard: some View {
        HearthGroup {
            VStack(spacing: 16) {
                IconTile(systemName: "arrow.triangle.2.circlepath", hue: .purple)
                    .padding(.top, 8)

                Text("Learning...")
                    .font(HearthFont.cardHeading.font)
                    .foregroundStyle(HearthColor.ink(scheme))

                Text("A suggestion appears once you've done two or more of the same things together, at about the same time, on 4 of the last 7 weekdays (or 4 of the last 7 weekend days).")
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(HearthColor.sub(scheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, HearthMetrics.groupInset)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    private var learnedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("LEARNED")
                .font(HearthFont.groupLabel.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .padding(.horizontal, HearthMetrics.groupInset + 12)

            ForEach(routines) { routine in
                routineCard(routine)
            }
        }
    }

    private func routineCard(_ routine: RoutineEntry) -> some View {
        let (surfaceName, surfaceIcon) = surfaceForRoutine(routine)

        return HearthGroup {
            VStack(alignment: .leading, spacing: HearthMetrics.groupInset * 0.75) {
                // Header: big time + X button
                HStack {
                    Text(formatTime(routine.medianTime))
                        .font(HearthFont.iconHero.font)
                        .foregroundStyle(HearthColor.ink(scheme))

                    Spacer()

                    Button {
                        removeRoutine(routine)
                    } label: {
                        Image(systemName: "xmark")
                            .font(HearthFont.iconSmall.font)
                            .foregroundStyle(HearthColor.sub(scheme))
                            .frame(width: 28, height: 28)
                    }
                }

                // Frequency subtitle
                Text(RoutinesViewLogic.dayPatternSubtitle(pattern: routine.dayPattern, occurrenceCount: routine.occurrences.count))
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(HearthColor.sub(scheme))

                // Day pills
                dayPillsRow(routine.dayPattern)

                // Action pills
                actionPillsRow(routine.entityIDs)

                // Appears on row
                HStack(spacing: 8) {
                    Image(systemName: surfaceIcon)
                        .font(HearthFont.iconSmall.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                    Text("Appears on \(surfaceName) around \(formatTime(routine.medianTime))")
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                }
                .padding(.top, 4)

                // Same as Goodnight key row (if applicable)
                if routine.matchesGoodnightKey {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.stars")
                            .font(HearthFont.iconSmall.font)
                            .foregroundStyle(HearthColor.sub(scheme))
                        Text("Same as Goodnight key")
                            .font(HearthFont.subtitle.font)
                            .foregroundStyle(HearthColor.sub(scheme))
                    }
                }
            }
            .padding(HearthMetrics.groupInset)
        }
    }

    private func dayPillsRow(_ pattern: RoutineEntry.DayPattern) -> some View {
        let activeIndices = RoutinesViewLogic.activeDayIndices(for: pattern)
        return HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { dayIndex in
                dayPill(dayIndex: dayIndex, isActive: activeIndices.contains(dayIndex))
            }
        }
    }

    private func dayPill(dayIndex: Int, isActive: Bool) -> some View {
        let initial = ["S", "M", "T", "W", "T", "F", "S"][dayIndex]
        return Text(initial)
            .font(HearthFont.pill.font)
            .foregroundStyle(isActive ? HearthColor.ink(scheme) : HearthColor.sub(scheme))
            .frame(width: HearthMetrics.buttonHSmall, height: HearthMetrics.buttonHSmall)
            .background(isActive ? HearthColor.tint(scheme) : Color.clear)
            .clipShape(Circle())
    }

    private func actionPillsRow(_ entityIDs: [String]) -> some View {
        let names = entityIDs.map { entityName(from: $0) }
        return HStack(spacing: 8) {
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                actionPill(name)
            }
        }
    }

    private func actionPill(_ name: String) -> some View {
        HStack(spacing: 6) {
            iconForAction(name)
            Text(name)
                .font(HearthFont.pill.font)
        }
        .foregroundStyle(HearthColor.ink(scheme))
        .padding(.horizontal, HearthMetrics.groupInset * 0.75)
        .padding(.vertical, 6)
        .background(HearthColor.tint(scheme))
        .clipShape(Capsule())
    }

    private func iconForAction(_ name: String) -> some View {
        let iconName = iconNameForAction(name)
        return Image(systemName: iconName)
            .font(HearthFont.iconSmall.font)
    }

    // MARK: - Helpers

    /// Derives the surface name and icon from the routine's actions (I3 fix).
    /// Returns (surfaceName, iconName) based on the dominant entity domain.
    private func surfaceForRoutine(_ routine: RoutineEntry) -> (String, String) {
        let domains = routine.entityIDs.compactMap { entityID -> String? in
            entityID.split(separator: ".").first.map(String.init)
        }

        // Priority: lights > alarm > lock > garage
        if domains.contains("light") {
            return ("Lights", "lightbulb")
        } else if domains.contains("alarm_control_panel") {
            return ("Home alarm", "shield")
        } else if domains.contains("lock") {
            return ("Locks", "lock")
        } else if domains.contains("cover") {
            return ("Garage", "garage.closed")
        } else {
            return ("Home", "house")
        }
    }

    private func loadRoutines() {
        let history = ActionHistoryStore.load()
        let goodnightActionSet = GoodnightStore.load().actionSet()
        routines = RoutinesSuggester.suggestedRoutines(from: history, now: Date(), goodnightActionSet: goodnightActionSet)
    }

    private func removeRoutine(_ routine: RoutineEntry) {
        // Remove all occurrences of this routine's entity set from history
        var history = ActionHistoryStore.load()
        let targetSignature = routine.entityIDs.sorted().joined(separator: "|")
        history.removeAll { record in
            let recordSignature = record.entityIDs.sorted().joined(separator: "|")
            return recordSignature == targetSignature
        }
        ActionHistoryStore.save(history)
        loadRoutines()
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)
        return date.formatted(formatter)
    }

    private func entityName(from entityID: String) -> String {
        // Simple name extraction: "light.kitchen" → "Kitchen off", "cover.garage_1" → "Close Garage"
        let parts = entityID.split(separator: ".")
        guard parts.count >= 2 else { return entityID }

        let domain = String(parts[0])
        let rawName = String(parts[1])
        // Strip numeric suffix for cleaner names (garage_1 → Garage)
        let cleanName = rawName.replacingOccurrences(of: "_\\d+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized

        switch domain {
        case "light":
            return "\(cleanName) off"
        case "cover":
            return "Close \(cleanName)"
        case "lock":
            return "Lock \(cleanName)"
        case "alarm_control_panel":
            return "Arm night"
        default:
            return cleanName
        }
    }

    private func iconNameForAction(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("off") {
            return "lightbulb.fill"  // Mock shows lightbulb for off
        } else if lower.contains("close") {
            return "garage.closed"
        } else if lower.contains("lock") {
            return "lock.fill"
        } else if lower.contains("arm") {
            return "shield.fill"  // Mock shows filled shield for arm
        } else {
            return "square.fill"
        }
    }
}

// MARK: - Previews

#Preview("Routines — Enabled with Routines") {
    NavigationStack {
        RoutinesPagePreview(state: .enabledWithRoutines)
            .navigationBarTitleDisplayMode(.inline)
    }
    .preferredColorScheme(.light)
}

#Preview("Routines — Learning") {
    NavigationStack {
        RoutinesPagePreview(state: .learning)
            .navigationBarTitleDisplayMode(.inline)
    }
    .preferredColorScheme(.light)
}

#Preview("Routines — Disabled") {
    NavigationStack {
        RoutinesPagePreview(state: .disabled)
            .navigationBarTitleDisplayMode(.inline)
    }
    .preferredColorScheme(.light)
}

#Preview("Routines — Dark Mode") {
    NavigationStack {
        RoutinesPagePreview(state: .enabledWithRoutines)
            .navigationBarTitleDisplayMode(.inline)
    }
    .preferredColorScheme(.dark)
}

// Preview wrapper with controlled state
private struct RoutinesPagePreview: View {
    enum PreviewState {
        case disabled
        case learning
        case enabledWithRoutines
    }

    let state: PreviewState
    @State private var enabled: Bool
    @State private var routines: [RoutineEntry]
    @Environment(\.colorScheme) private var scheme

    init(state: PreviewState) {
        self.state = state
        switch state {
        case .disabled:
            _enabled = SwiftUI.State(initialValue: false)
            _routines = SwiftUI.State(initialValue: [])
        case .learning:
            _enabled = SwiftUI.State(initialValue: true)
            _routines = SwiftUI.State(initialValue: [])
        case .enabledWithRoutines:
            _enabled = SwiftUI.State(initialValue: true)
            let now = Date()
            _routines = SwiftUI.State(initialValue: [
                RoutineEntry(
                    id: "routine1",
                    medianTime: Calendar.current.date(bySettingHour: 22, minute: 30, second: 0, of: now) ?? now,
                    entityIDs: ["light.kitchen", "light.den", "cover.garage_1", "alarm_control_panel.panel"],
                    occurrences: Array(repeating: now, count: 6),
                    dayPattern: .weeknights,
                    matchesGoodnightKey: true
                ),
                RoutineEntry(
                    id: "routine2",
                    medianTime: Calendar.current.date(bySettingHour: 7, minute: 45, second: 0, of: now) ?? now,
                    entityIDs: ["light.porch", "lock.back_door"],
                    occurrences: Array(repeating: now, count: 11),
                    dayPattern: .everyDay,
                    matchesGoodnightKey: false
                )
            ])
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HearthGroup {
                    HearthRow(
                        icon: "arrow.triangle.2.circlepath",
                        hue: .purple,
                        title: "Learn my routines",
                        subtitle: "Shows a one-tap suggestion on your widget near the usual time"
                    ) {
                        HearthSwitch(isOn: $enabled)
                    }
                }
                .padding(.top, 20)

                Text("Never runs on its own. Stays on this phone.")
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(HearthColor.sub(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HearthMetrics.groupInset + 12)

                if enabled {
                    if routines.isEmpty {
                        HearthGroup {
                            VStack(spacing: 16) {
                                IconTile(systemName: "arrow.triangle.2.circlepath", hue: .purple)
                                    .padding(.top, 8)

                                Text("Learning...")
                                    .font(HearthFont.cardHeading.font)
                                    .foregroundStyle(HearthColor.ink(scheme))

                                Text("A suggestion appears after Hearth sees you do the same steps several times.")
                                    .font(HearthFont.subtitle.font)
                                    .foregroundStyle(HearthColor.sub(scheme))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("LEARNED")
                                .font(HearthFont.groupLabel.font)
                                .foregroundStyle(HearthColor.sub(scheme))
                                .padding(.horizontal, HearthMetrics.groupInset + 12)

                            ForEach(routines) { routine in
                                routineCardPreview(routine)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .background(HearthColor.page(scheme))
        .navigationTitle("Routines")
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)
        return date.formatted(formatter)
    }

    /// Preview-compatible routine card rendering (N4 fix: reuses real card structure).
    private func routineCardPreview(_ routine: RoutineEntry) -> some View {
        let (surfaceName, surfaceIcon) = surfaceForRoutinePreview(routine)

        return HearthGroup {
            VStack(alignment: .leading, spacing: HearthMetrics.groupInset * 0.75) {
                // Header: big time + X button
                HStack {
                    Text(formatTime(routine.medianTime))
                        .font(HearthFont.iconHero.font)
                        .foregroundStyle(HearthColor.ink(scheme))
                    Spacer()
                    Image(systemName: "xmark")
                        .font(HearthFont.iconSmall.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                }

                Text(RoutinesViewLogic.dayPatternSubtitle(pattern: routine.dayPattern, occurrenceCount: routine.occurrences.count))
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(HearthColor.sub(scheme))

                // Day pills
                dayPillsRowPreview(routine.dayPattern)

                // Action pills
                actionPillsRowPreview(routine.entityIDs)

                // Appears on row
                HStack(spacing: 8) {
                    Image(systemName: surfaceIcon)
                        .font(HearthFont.iconSmall.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                    Text("Appears on \(surfaceName) around \(formatTime(routine.medianTime))")
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                }
                .padding(.top, 4)

                // Same as Goodnight key row
                if routine.matchesGoodnightKey {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.stars")
                            .font(HearthFont.iconSmall.font)
                            .foregroundStyle(HearthColor.sub(scheme))
                        Text("Same as Goodnight key")
                            .font(HearthFont.subtitle.font)
                            .foregroundStyle(HearthColor.sub(scheme))
                    }
                }
            }
            .padding(HearthMetrics.groupInset)
        }
    }

    private func surfaceForRoutinePreview(_ routine: RoutineEntry) -> (String, String) {
        let domains = routine.entityIDs.compactMap { entityID -> String? in
            entityID.split(separator: ".").first.map(String.init)
        }

        if domains.contains("light") {
            return ("Lights", "lightbulb")
        } else if domains.contains("alarm_control_panel") {
            return ("Home alarm", "shield")
        } else if domains.contains("lock") {
            return ("Locks", "lock")
        } else if domains.contains("cover") {
            return ("Garage", "garage.closed")
        } else {
            return ("Home", "house")
        }
    }

    private func dayPillsRowPreview(_ pattern: RoutineEntry.DayPattern) -> some View {
        let activeIndices = RoutinesViewLogic.activeDayIndices(for: pattern)
        return HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { dayIndex in
                dayPillPreview(dayIndex: dayIndex, isActive: activeIndices.contains(dayIndex))
            }
        }
    }

    private func dayPillPreview(dayIndex: Int, isActive: Bool) -> some View {
        let initial = ["S", "M", "T", "W", "T", "F", "S"][dayIndex]
        return Text(initial)
            .font(HearthFont.pill.font)
            .foregroundStyle(isActive ? HearthColor.ink(scheme) : HearthColor.sub(scheme))
            .frame(width: HearthMetrics.buttonHSmall, height: HearthMetrics.buttonHSmall)
            .background(isActive ? HearthColor.tint(scheme) : Color.clear)
            .clipShape(Circle())
    }

    private func actionPillsRowPreview(_ entityIDs: [String]) -> some View {
        let names = entityIDs.map { entityNamePreview(from: $0) }
        return HStack(spacing: 8) {
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                actionPillPreview(name)
            }
        }
    }

    private func actionPillPreview(_ name: String) -> some View {
        HStack(spacing: 6) {
            iconForActionPreview(name)
            Text(name)
                .font(HearthFont.pill.font)
        }
        .foregroundStyle(HearthColor.ink(scheme))
        .padding(.horizontal, HearthMetrics.groupInset * 0.75)
        .padding(.vertical, 6)
        .background(HearthColor.tint(scheme))
        .clipShape(Capsule())
    }

    private func iconForActionPreview(_ name: String) -> some View {
        let iconName = iconNameForActionPreview(name)
        return Image(systemName: iconName)
            .font(HearthFont.iconSmall.font)
    }

    private func entityNamePreview(from entityID: String) -> String {
        let parts = entityID.split(separator: ".")
        guard parts.count >= 2 else { return entityID }

        let domain = String(parts[0])
        let rawName = String(parts[1])
        let cleanName = rawName.replacingOccurrences(of: "_\\d+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized

        switch domain {
        case "light":
            return "\(cleanName) off"
        case "cover":
            return "Close \(cleanName)"
        case "lock":
            return "Lock \(cleanName)"
        case "alarm_control_panel":
            return "Arm night"
        default:
            return cleanName
        }
    }

    private func iconNameForActionPreview(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("off") {
            return "lightbulb.fill"
        } else if lower.contains("close") {
            return "garage.closed"
        } else if lower.contains("lock") {
            return "lock.fill"
        } else if lower.contains("arm") {
            return "shield.fill"
        } else {
            return "square.fill"
        }
    }
}
