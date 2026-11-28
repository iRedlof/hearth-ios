import SwiftUI
import UIKit
import HearthKit

/// ChargePoint settings page — status-first pushed page re-skinning existing CP logic.
/// Reuses SettingsRuntime.performCpEdit, CpSessionStore, CpSignInView, CpLocationSearchView.
@MainActor
struct ChargePointPage: View {
    @State private var cp: SettingsCpState
    @State private var editError: String?
    @State private var editID = UUID()
    @State private var showSignIn = false
    @State private var showLocation = false
    @State private var showSignInAgain = false
    @State private var showFasterOffers = false
    @State private var showSignOutConfirm = false
    @State private var nameDraft: String = ""
    @State private var nameOrigin: CpSettingsOrigin?
    @FocusState private var nameFocused: Bool

    let runtime: any SettingsRuntime
    let initialRoute: CpSetupRoute?

    @Environment(\.colorScheme) private var scheme

    init(initialRoute: CpSetupRoute? = nil, runtime: any SettingsRuntime = LiveSettingsRuntime.shared) {
        self.initialRoute = initialRoute
        self.runtime = runtime
        let initial = runtime.loadCp()
        _cp = State(initialValue: initial)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Connection Hero
                ConnectionHero(
                    presentation: cpHeroPresentation(connectionStatus),
                    title: "ChargePoint",
                    detail: heroDetail,
                    showsSide: connectionStatus == .needsSignIn
                ) {
                    ctaButton
                }
                .padding(.top, 20)
                .padding(.horizontal, HearthMetrics.groupInset)

                if !cp.session.isSignedIn {
                    // Not set up / needs sign in
                    setupCard
                } else {
                    // Connected
                    accountGroup
                    waitlistGroup
                    alertsGroup
                    morningCommuteGroup
                    widgetGroup
                    signOutButton
                }

                // Always available — the diagnostics the phone needs to explain a ChargePoint failure.
                diagnosticsGroup
            }
            .padding(.bottom, 20)
        }
        .background(HearthColor.page(scheme))
        .navigationTitle("ChargePoint")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            editID = UUID()
            cp = runtime.loadCp()
            nameDraft = cp.location?.label ?? ""

            // Auto-show sheet based on initialRoute
            if let route = initialRoute {
                switch route {
                case .signin:
                    showSignIn = true
                case .location:
                    showLocation = true
                }
            }
        }
        .sheet(isPresented: $showSignIn) {
            NavigationStack {
                CpSignInView(expected: cp.origin) {
                    cp = runtime.loadCp()
                    showSignIn = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showSignIn = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showSignInAgain) {
            NavigationStack {
                CpSignInView(expected: cp.origin) {
                    cp = runtime.loadCp()
                    showSignInAgain = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showSignInAgain = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showLocation) {
            NavigationStack {
                CpLocationSearchView(expected: cp.origin) {
                    cp = runtime.loadCp()
                    showLocation = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showLocation = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showFasterOffers) {
            FasterOffersSheet()
        }
        .alert("Sign out of ChargePoint?", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) {
                perform(.signOut)
            }
        } message: {
            Text("Your ChargePoint widgets will stop until you sign in again.")
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

    // MARK: - Connection Status

    private var connectionStatus: CpConnectionStatus {
        cpConnectionStatus(for: cp.session)
    }

    private var heroDetail: String {
        guard let location = cp.location else {
            return "Not set up"
        }
        // Show the place name (guard empty label)
        let place = location.label.isEmpty ? location.name : location.label
        return place
    }

    // MARK: - CTA Button

    @ViewBuilder
    private var ctaButton: some View {
        let status = connectionStatus

        switch status {
        case .connected:
            EmptyView()

        case .needsSignIn:
            Button("Sign in again") {
                showSignInAgain = true
            }
            .hearthInk()

        case .notSetUp:
            EmptyView()
        }
    }

    // MARK: - Setup Card

    @ViewBuilder
    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Show unavailable message if applicable
            if cp.unavailable {
                Text("ChargePoint unavailable")
                    .font(HearthFont.cardHeading.font)
                    .foregroundStyle(HearthColor.red(scheme))
                Text("Shared storage unavailable. Open sign in to reset.")
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(HearthColor.sub(scheme))
            }

            // Show "Stop Auto" if signed out but auto still on
            if cp.auto {
                Text("Auto is on")
                    .font(HearthFont.cardHeading.font)
                    .foregroundStyle(HearthColor.ink(scheme))
                Text("Sign in to continue, or stop Auto.")
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(HearthColor.sub(scheme))
                Button {
                    perform(.auto(.pause, cp.renderedOrigin))
                } label: {
                    Text("Stop Auto")
                        .font(HearthFont.rowTitle.font)
                        .foregroundStyle(HearthColor.onAccent(scheme))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(HearthColor.red(scheme))
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
            }

            Text("Set up in 2 steps")
                .font(HearthFont.cardHeading.font)
                .foregroundStyle(HearthColor.ink(scheme))
                .padding(.top, cp.unavailable || cp.auto ? 12 : 0)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Text("1")
                        .font(HearthFont.iconMedium.font.weight(.semibold))
                        .foregroundStyle(HearthColor.sub(scheme))
                        .frame(width: 32, height: 32)
                        .background(HearthColor.tint(scheme))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sign in to ChargePoint")
                            .font(HearthFont.rowTitle.font)
                            .foregroundStyle(HearthColor.ink(scheme))
                    }

                    Spacer()

                    Button {
                        showSignIn = true
                    } label: {
                        Text("Sign in")
                            .font(HearthFont.rowTitle.font)
                            .foregroundStyle(HearthColor.onAccent(scheme))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(HearthColor.ink(scheme))
                            .clipShape(Capsule())
                    }
                }

                Rectangle()
                    .fill(HearthColor.line(scheme))
                    .frame(height: 1)
                    .padding(.leading, 44)

                HStack(spacing: 12) {
                    Text("2")
                        .font(HearthFont.iconMedium.font.weight(.semibold))
                        .foregroundStyle(HearthColor.sub(scheme))
                        .frame(width: 32, height: 32)
                        .background(HearthColor.tint(scheme))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pick your place")
                            .font(HearthFont.rowTitle.font)
                            .foregroundStyle(HearthColor.ink(scheme))
                    }

                    Spacer()
                }
            }
        }
        .padding(HearthMetrics.pagePadding)
        .background(HearthColor.card(scheme))
        .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius))
        .padding(.horizontal, HearthMetrics.groupInset)
    }

    // MARK: - Account Group

    @ViewBuilder
    private var accountGroup: some View {
        HearthGroup("Account") {
            Button {
                showLocation = true
            } label: {
                HearthRow(
                    icon: "mappin.circle",
                    hue: .blue,
                    title: "Place",
                    subtitle: locationSubtitle
                )
            }
            .buttonStyle(.plain)

            if cp.location != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name (optional)")
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                        .padding(.horizontal, HearthMetrics.groupInset + 12)
                    TextField("", text: $nameDraft, prompt: Text("Office charger"))
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .onSubmit { nameFocused = false }
                        .onChange(of: nameFocused) { _, editing in
                            if editing { nameOrigin = cp.origin } else { saveName() }
                        }
                        .padding(.horizontal, HearthMetrics.groupInset + 12)
                }
                .padding(.vertical, 8)
            }

            HearthRow(
                icon: "checkmark.circle",
                hue: .green,
                title: "Sign-in",
                subtitle: signInSubtitle
            )
        }
    }

    private var locationSubtitle: String {
        guard let location = cp.location else {
            return "Not set"
        }
        let displayName = location.label.isEmpty ? location.name : location.label
        let chargerCount = location.deviceIds.count
        let chargerText = chargerCount == 1 ? "charger" : "chargers"
        return "\(displayName) · \(chargerCount) \(chargerText)"
    }

    private var signInSubtitle: String {
        let token = cp.session.token
        guard !token.isEmpty else {
            return "Not signed in"
        }
        guard let minutesLeft = CpToken.minutesLeft(token: token, now: Date()) else {
            return "Signed in"
        }
        if minutesLeft < 60 {
            return "Good for \(minutesLeft) min · then sign in again"
        } else {
            let hoursLeft = minutesLeft / 60
            let hourText = hoursLeft == 1 ? "hour" : "hours"
            return "Good for \(hoursLeft) \(hourText) · then sign in again"
        }
    }

    // MARK: - Waitlist Group

    @ViewBuilder
    private var waitlistGroup: some View {
        HearthGroup("Waitlist") {
            HearthRow(
                icon: "clock.arrow.2.circlepath",
                hue: .purple,
                title: "Auto-waitlist",
                subtitle: cp.auto ? "On" : "Off"
            ) {
                HearthSwitch(isOn: Binding(
                    get: { cp.auto },
                    set: { on in
                        perform(.auto(on ? (cp.autoControl == .join ? .join : .resume) : .pause, cp.renderedOrigin))
                    }
                ))
            }
            .disabled(!cp.auto && (cp.autoControl == .disabled || cp.renderedOrigin == nil))

            Button {
                // TODO Phase 5: Navigate to morning commute settings
            } label: {
                HearthRow(
                    icon: "sunrise",
                    hue: .orange,
                    title: "Morning commute",
                    subtitle: !cp.auto ? "Turn on Auto-waitlist first" : nil,
                    subtitleWarn: !cp.auto
                ) {
                    if cp.auto {
                        Image(systemName: "chevron.right")
                            .font(HearthFont.callout.font.weight(.semibold))
                            .foregroundStyle(HearthColor.sub(scheme))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!cp.auto)

            Button {
                showFasterOffers = true
            } label: {
                HearthRow(
                    icon: "bolt",
                    hue: .amber,
                    title: "Faster offers",
                    subtitle: nil
                ) {
                    HomeChevron()
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Alerts Group

    @ViewBuilder
    private var alertsGroup: some View {
        HearthGroup("Alerts") {
            NavigationLink {
                ChargePointAlertsPage(runtime: runtime)
            } label: {
                HearthRow(
                    icon: "bell",
                    hue: .red,
                    title: "Alerts",
                    subtitle: alertsSummary
                ) {
                    HomeChevron()
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var alertsSummary: String {
        let count = [cp.alerts.offer, cp.alerts.accepted, cp.alerts.snoozed, cp.alerts.second].filter { $0 }.count
        // "2 every charge · 3 while Auto runs" style from brief
        // For now, simplified to just count
        if count == 0 {
            return "All off"
        } else if count == 4 {
            return "All on"
        } else {
            return "\(count) of 4 on"
        }
    }

    // MARK: - Morning Commute Group

    @ViewBuilder
    private var morningCommuteGroup: some View {
        HearthGroup("Morning commute") {
            NavigationLink {
                MorningCommutePage()
            } label: {
                HearthRow(
                    icon: "car",
                    hue: .neutral,
                    title: "Morning commute",
                    subtitle: commuteSubtitle
                ) {
                    HomeChevron()
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var commuteSubtitle: String {
        CommuteStore.enabled ? "Auto-join on weekday mornings" : "Off"
    }

    // MARK: - Widget Group

    @ViewBuilder
    private var widgetGroup: some View {
        HearthGroup("Widget") {
            HearthRow(
                icon: "square.grid.2x2",
                hue: .neutral,
                title: cp.location?.label ?? "Office charger",
                subtitle: "Shows waitlist status and charging"
            )
        }
    }

    // MARK: - Sign Out Button

    @ViewBuilder
    private var signOutButton: some View {
        Button {
            showSignOutConfirm = true
        } label: {
            Text("Sign out")
                .font(HearthFont.rowTitle.font)
                .foregroundStyle(HearthColor.red(scheme))
        }
        .padding(.horizontal, HearthMetrics.groupInset)
        .padding(.top, 8)
    }

    // MARK: - Diagnostics

    private var diagnosticsInput: CpDiagnosticsInput {
        let session = cp.session
        let minutesLeft = session.token.isEmpty ? nil : CpToken.minutesLeft(token: session.token, now: Date())
        let attempt = cp.lastFailure.map { failure in
            CpDiagnosticsAttempt(at: failure.attemptedAt.formatted(date: .omitted, time: .shortened),
                                 host: failure.host, status: failure.status,
                                 reason: failure.presentation.reason,
                                 request: failure.request, detail: failure.detail)
        }
        let info = Bundle.main.infoDictionary
        return CpDiagnosticsInput(
            tokenPresent: !session.token.isEmpty,
            userIDPresent: session.userId != 0,
            expired: session.expired,
            minutesLeft: minutesLeft,
            lastAttempt: attempt,
            lastAction: cp.lastAction,
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "—",
            build: info?["CFBundleVersion"] as? String ?? "—"
        )
    }

    @ViewBuilder
    private var diagnosticsGroup: some View {
        let text = cpDiagnosticsText(diagnosticsInput)
        HearthGroup("Diagnostics") {
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(HearthColor.sub(scheme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Text("Copy diagnostics")
                        .font(HearthFont.rowTitle.font)
                        .foregroundStyle(HearthColor.ink(scheme))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, HearthMetrics.groupInset + 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Edit Helpers

    private func perform(_ edit: SettingsCpEdit, expected supplied: CpSettingsOrigin? = nil) {
        performer.perform(edit, expected: supplied)
    }

    private var performer: CpEditPerformer {
        CpEditPerformer(runtime: runtime, cp: $cp, editError: $editError, editID: $editID)
    }

    private func saveName() {
        guard nameDraft != cp.location?.label else { return }
        guard let origin = nameOrigin else { return }
        nameOrigin = nil
        perform(.locationName(nameDraft), expected: origin)
    }
}

// MARK: - Faster Offers Sheet

@MainActor
private struct FasterOffersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "bolt.circle.fill")
                            .font(HearthFont.iconHero.font)
                            .foregroundStyle(HearthColor.amber(scheme))

                        Text("Faster Offers")
                            .font(HearthFont.pageTitle.font)
                    }
                    .padding(.top, 20)

                    // Explanation
                    HearthGroup {
                        HearthRow(
                            icon: "clock",
                            hue: .orange,
                            title: "Quick response",
                            subtitle: "Auto-waitlist accepts or snoozes offers within seconds"
                        )

                        HearthRow(
                            icon: "sparkles",
                            hue: .purple,
                            title: "Beat the crowd",
                            subtitle: "Faster than manual tap — improves your odds"
                        )

                        HearthRow(
                            icon: "battery.100",
                            hue: .green,
                            title: "Runs in background",
                            subtitle: "No need to keep the app open"
                        )
                    }

                    Text("Auto-waitlist runs when your ChargePoint widget refreshes. On iOS, this happens automatically throughout the day.")
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(HearthColor.sub(scheme))
                        .padding(.horizontal, HearthMetrics.groupInset + 12)
                }
                .padding(.horizontal, HearthMetrics.groupInset)
                .padding(.bottom, 20)
            }
            .background(HearthColor.page(scheme))
            .navigationTitle("Faster Offers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Connected - Light") {
    NavigationStack {
        ChargePointPage(runtime: MockCpRuntime(
            session: CpSession(token: "mock", userId: 1, email: "user@example.com"),
            location: CpLocation(name: "Office Building", address: "123 Main St", deviceIds: [1, 2, 3, 4], bounds: cpBounds(lat: 0, lon: 0), label: "Office"),
            auto: true,
            alerts: CpAlertPrefs(offer: true, accepted: true, snoozed: false, second: true),
            autoControl: .stop
        ))
    }
    .preferredColorScheme(.light)
}

#Preview("Connected - Dark") {
    NavigationStack {
        ChargePointPage(runtime: MockCpRuntime(
            session: CpSession(token: "mock", userId: 1, email: "user@example.com"),
            location: CpLocation(name: "Office Building", address: "123 Main St", deviceIds: [1, 2, 3, 4], bounds: cpBounds(lat: 0, lon: 0), label: "Office"),
            auto: true,
            alerts: CpAlertPrefs(offer: true, accepted: true, snoozed: false, second: true),
            autoControl: .stop
        ))
    }
    .preferredColorScheme(.dark)
}

#Preview("Needs Sign-in - Light") {
    NavigationStack {
        ChargePointPage(runtime: MockCpRuntime(
            session: CpSession(token: "", userId: 1, email: "user@example.com", expired: true),
            location: CpLocation(name: "Office Building", address: "123 Main St", deviceIds: [1, 2], bounds: cpBounds(lat: 0, lon: 0), label: "Office"),
            auto: false,
            alerts: CpAlertPrefs(offer: false, accepted: false, snoozed: false, second: false),
            autoControl: .signin
        ))
    }
    .preferredColorScheme(.light)
}

#Preview("Not Set Up - Light") {
    NavigationStack {
        ChargePointPage(runtime: MockCpRuntime(
            session: CpSession(),
            location: nil,
            auto: false,
            alerts: CpAlertPrefs(offer: false, accepted: false, snoozed: false, second: false),
            autoControl: .disabled
        ))
    }
    .preferredColorScheme(.light)
}

#Preview("Auto OFF - Light") {
    NavigationStack {
        ChargePointPage(runtime: MockCpRuntime(
            session: CpSession(token: "mock", userId: 1, email: "user@example.com"),
            location: CpLocation(name: "Office Building", address: "123 Main St", deviceIds: [1, 2], bounds: cpBounds(lat: 0, lon: 0), label: "Office"),
            auto: false,
            alerts: CpAlertPrefs(offer: true, accepted: true, snoozed: false, second: true),
            autoControl: .resume
        ))
    }
    .preferredColorScheme(.light)
}

// MARK: - Mock Runtime

@MainActor
private final class MockCpRuntime: SettingsRuntime {
    var cp: SettingsCpState

    init(session: CpSession, location: CpLocation?, auto: Bool, alerts: CpAlertPrefs, autoControl: CpAutoControl) {
        self.cp = SettingsCpState(
            session: session,
            location: location,
            auto: auto,
            alerts: alerts,
            origin: nil,  // Not needed for preview
            renderedOrigin: nil,  // Not needed for preview
            autoControl: autoControl
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
        case .auto(let desired, _):
            cp.auto = desired != .pause
            return cp
        case .signOut:
            cp.session = CpSession()
            return cp
        default:
            return cp
        }
    }
    func openSetupRoute(_ route: SettingsSetupRoute) -> SettingsSetupDestination { .live }
    func refreshWidgets(kinds: Set<String>) {}
}
