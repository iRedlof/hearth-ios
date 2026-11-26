import SwiftUI
import HearthKit

/// ChargePoint Alerts settings page — re-skins existing CP alert toggles into grouped sections.
/// Reuses SettingsRuntime.performCpEdit with the existing alert edit keys.
@MainActor
struct ChargePointAlertsPage: View {
    @State private var cp: SettingsCpState
    @State private var editError: String?
    @State private var editID = UUID()

    let runtime: any SettingsRuntime

    @Environment(\.colorScheme) private var scheme

    init(runtime: any SettingsRuntime = LiveSettingsRuntime.shared) {
        self.runtime = runtime
        let initial = runtime.loadCp()
        _cp = State(initialValue: initial)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Caption
                Text("In the order a charge happens.")
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(HearthColor.sub(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HearthMetrics.groupInset + 12)
                    .padding(.top, 20)

                // Every charge
                everyChargeGroup

                // While Auto runs
                whileAutoRunsGroup

                // Always sent
                alwaysSentGroup
            }
            .padding(.bottom, 20)
        }
        .background(HearthColor.page(scheme))
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            editID = UUID()
            cp = runtime.loadCp()
        }
        .alert("Couldn't update ChargePoint", isPresented: Binding(
            get: { editError != nil },
            set: { if !$0 { editError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editError ?? "")
        }
    }

    // MARK: - Every Charge Group

    @ViewBuilder
    private var everyChargeGroup: some View {
        HearthGroup("Every charge") {
            HearthRow(
                icon: "bell",
                hue: .red,
                title: "Your turn",
                subtitle: "Arrives faster with Faster offers"
            ) {
                HearthSwitch(isOn: Binding(
                    get: { cp.alerts.offer },
                    set: { perform(.alert(cpAlertEditKey(.yourTurn), $0)) }
                ))
            }
        }
    }

    // MARK: - While Auto Runs Group

    @ViewBuilder
    private var whileAutoRunsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            HearthGroup("While Auto runs") {
                HearthRow(
                    icon: "checkmark.circle",
                    hue: .green,
                    title: "Accepted & held",
                    subtitle: nil
                ) {
                    HearthSwitch(isOn: Binding(
                        get: { cp.alerts.accepted },
                        set: { perform(.alert(cpAlertEditKey(.acceptedHeld), $0)) }
                    ))
                }
                .disabled(!whileAutoRunsEnabled(autoOn: cp.auto))
                .opacity(whileAutoRunsEnabled(autoOn: cp.auto) ? 1.0 : 0.5)

                HearthRow(
                    icon: "clock.arrow.circlepath",
                    hue: .orange,
                    title: "Snoozed",
                    subtitle: nil
                ) {
                    HearthSwitch(isOn: Binding(
                        get: { cp.alerts.snoozed },
                        set: { perform(.alert(cpAlertEditKey(.snoozed), $0)) }
                    ))
                }
                .disabled(!whileAutoRunsEnabled(autoOn: cp.auto))
                .opacity(whileAutoRunsEnabled(autoOn: cp.auto) ? 1.0 : 0.5)

                HearthRow(
                    icon: "2.circle",
                    hue: .purple,
                    title: "Second offer",
                    subtitle: nil
                ) {
                    HearthSwitch(isOn: Binding(
                        get: { cp.alerts.second },
                        set: { perform(.alert(cpAlertEditKey(.secondOffer), $0)) }
                    ))
                }
                .disabled(!whileAutoRunsEnabled(autoOn: cp.auto))
                .opacity(whileAutoRunsEnabled(autoOn: cp.auto) ? 1.0 : 0.5)
            }

            if !whileAutoRunsEnabled(autoOn: cp.auto) {
                Text("Turn on Auto-waitlist to get these.")
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(HearthColor.sub(scheme))
                    .padding(.horizontal, HearthMetrics.groupInset + 12)
            }
        }
    }

    // MARK: - Always Sent Group

    @ViewBuilder
    private var alwaysSentGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            HearthGroup("Always sent") {
                HearthRow(
                    icon: "car",
                    hue: .blue,
                    title: "Drive now",
                    subtitle: nil
                )

                HearthRow(
                    icon: "arrow.uturn.left",
                    hue: .orange,
                    title: "Move your car",
                    subtitle: nil
                )

                HearthRow(
                    icon: "exclamationmark.triangle",
                    hue: .amber,
                    title: "Failed action",
                    subtitle: nil
                )

                HearthRow(
                    icon: "lock",
                    hue: .neutral,
                    title: "Signed out",
                    subtitle: nil
                )
            }

            Text("Hearth sends at most 2 reminders a charge and 1 commute nudge a day.")
                .font(HearthFont.subtitle.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .padding(.horizontal, HearthMetrics.groupInset + 12)
        }
    }

    // MARK: - Perform Edit

    private func perform(_ edit: SettingsCpEdit, expected supplied: CpSettingsOrigin? = nil) {
        performer.perform(edit, expected: supplied)
    }

    private var performer: CpEditPerformer {
        CpEditPerformer(runtime: runtime, cp: $cp, editError: $editError, editID: $editID)
    }
}

// MARK: - Previews

#Preview("Auto ON - Light") {
    NavigationStack {
        ChargePointAlertsPage(runtime: MockCpAlertsRuntime(
            auto: true,
            alerts: CpAlertPrefs(offer: true, accepted: true, snoozed: false, second: true)
        ))
    }
    .preferredColorScheme(.light)
}

#Preview("Auto ON - Dark") {
    NavigationStack {
        ChargePointAlertsPage(runtime: MockCpAlertsRuntime(
            auto: true,
            alerts: CpAlertPrefs(offer: true, accepted: true, snoozed: false, second: true)
        ))
    }
    .preferredColorScheme(.dark)
}

#Preview("Auto OFF - Light") {
    NavigationStack {
        ChargePointAlertsPage(runtime: MockCpAlertsRuntime(
            auto: false,
            alerts: CpAlertPrefs(offer: true, accepted: false, snoozed: false, second: false)
        ))
    }
    .preferredColorScheme(.light)
}

#Preview("Auto OFF - Dark") {
    NavigationStack {
        ChargePointAlertsPage(runtime: MockCpAlertsRuntime(
            auto: false,
            alerts: CpAlertPrefs(offer: true, accepted: false, snoozed: false, second: false)
        ))
    }
    .preferredColorScheme(.dark)
}

// MARK: - Mock Runtime

@MainActor
private final class MockCpAlertsRuntime: SettingsRuntime {
    var cp: SettingsCpState

    init(auto: Bool, alerts: CpAlertPrefs) {
        self.cp = SettingsCpState(
            session: CpSession(token: "mock", userId: 1, email: "user@example.com"),
            location: CpLocation(name: "Office Building", address: "123 Main St", deviceIds: [1, 2], bounds: cpBounds(lat: 0, lon: 0), label: "Office"),
            auto: auto,
            alerts: alerts,
            origin: nil,
            renderedOrigin: nil,
            autoControl: .stop
        )
    }

    func loadHa() -> HaStoreSnapshot? { nil }
    func saveHaEdit(expectedScope: String?, edit: SettingsHaEdit) throws -> HaConfig? { nil }
    func discoverHa(config: HaConfig, scope: String?, purpose: SettingsDiscoveryPurpose) async throws -> SettingsDiscovery {
        throw HaError("Mock")
    }
    func loadCp() -> SettingsCpState { cp }
    func performCpEdit(_ edit: SettingsCpEdit, expected: CpSettingsOrigin?) async throws -> SettingsCpState {
        switch edit {
        case .alert(let key, let on):
            // Update the corresponding alert in cp.alerts
            if key == "offer" {
                cp.alerts.offer = on
            } else if key == "accepted" {
                cp.alerts.accepted = on
            } else if key == "snoozed" {
                cp.alerts.snoozed = on
            } else if key == "second" {
                cp.alerts.second = on
            }
            return cp
        default:
            return cp
        }
    }
    func openSetupRoute(_ route: SettingsSetupRoute) -> SettingsSetupDestination { .live }
    func refreshWidgets(kinds: Set<String>) {}
}
