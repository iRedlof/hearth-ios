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
        HearthGroup {
            VStack(alignment: .leading, spacing: 12) {
                // Header: big time + X button
                HStack {
                    Text(formatTime(routine.medianTime))
                        .font(.system(size: 48, weight: .regular, design: .default))
                        .foregroundStyle(HearthColor.ink(scheme))

                    Spacer()

                    Button {
                        removeRoutine(routine)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
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
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 14))
                        .foregroundStyle(HearthColor.sub(scheme))
                    Text("Appears on Home alarm around \(formatTime(routine.medianTime))")
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                }
                .padding(.top, 4)

                // Same as Goodnight key row (if applicable)
                if routine.matchesGoodnightKey {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.stars")
                            .font(.system(size: 14))
                            .foregroundStyle(HearthColor.sub(scheme))
                        Text("Same as Goodnight key")
                            .font(HearthFont.subtitle.font)
                            .foregroundStyle(HearthColor.sub(scheme))
                    }
                }
            }
            .padding(16)
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
            .frame(width: 32, height: 32)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(HearthColor.tint(scheme))
        .clipShape(Capsule())
    }

    private func iconForAction(_ name: String) -> some View {
        let iconName = iconNameForAction(name)
        return Image(systemName: iconName)
            .font(.system(size: 14))
    }

    // MARK: - Helpers

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
        // Simple name extraction: "light.kitchen" → "Kitchen off"
        let parts = entityID.split(separator: ".")
        guard parts.count >= 2 else { return entityID }

        let domain = String(parts[0])
        let name = String(parts[1]).replacingOccurrences(of: "_", with: " ").capitalized

        switch domain {
        case "light":
            return "\(name) off"
        case "cover":
            return "Close \(name)"
        case "lock":
            return "Lock \(name)"
        case "alarm_control_panel":
            return "Arm night"
        default:
            return name
        }
    }

    private func iconNameForAction(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("off") {
            return "light.beacon.max.fill"
        } else if lower.contains("close") {
            return "garage.closed"
        } else if lower.contains("lock") {
            return "lock.fill"
        } else if lower.contains("arm") {
            return "shield.checkered"
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
                                HearthGroup {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            Text(formatTime(routine.medianTime))
                                                .font(.system(size: 48, weight: .regular, design: .default))
                                                .foregroundStyle(HearthColor.ink(scheme))
                                            Spacer()
                                            Image(systemName: "xmark")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundStyle(HearthColor.sub(scheme))
                                        }
                                        Text(RoutinesViewLogic.dayPatternSubtitle(pattern: routine.dayPattern, occurrenceCount: routine.occurrences.count))
                                            .font(HearthFont.subtitle.font)
                                            .foregroundStyle(HearthColor.sub(scheme))
                                        Text("Day pills and action pills would go here")
                                            .font(HearthFont.subtitle.font)
                                            .foregroundStyle(HearthColor.sub(scheme))
                                    }
                                    .padding(16)
                                }
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
}
