import SwiftUI
import HearthKit

/// Full controls are bound to the immutable opening, with fresh journal authority for each action.
struct ThermostatControlsScreen: View {
    @ObservedObject var model: ThermostatControlsModel
    let onClose: () -> Void
    let onSettings: () -> Void
    let onReconnect: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var signal = RefreshSignal.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let session = model.session {
                        identity(session)
                        if let message = recovery(session) {
                            Text(message).fixedSize(horizontal: false, vertical: true)
                        }
                        if let error = model.error { Text(error).foregroundStyle(.secondary) }
                        targets(session.shownEnvelope, origin: session.controlOrigin)
                        if let origin = session.controlOrigin { controls(session.shownEnvelope, origin: origin) }
                        if session.status == .current {
                            Button { model.refresh() } label: {
                                Label(model.checking ? "Checking Home Assistant…" : "Refresh", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.bordered)
                                .disabled(model.checking || session.shownEnvelope.evidence.operation?.pending == true)
                            Text("Refresh checks Home Assistant. Opening this screen uses saved readings.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        if session.shownEnvelope.presentation.recovery == .authentication {
                            Button("Sign in again", action: onReconnect).frame(minHeight: 44)
                        }
                        readings(session.shownEnvelope.presentation)
                    } else {
                        Text(model.explanation ?? "Opening saved readings…")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Open Settings", action: onSettings).frame(minHeight: 44)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
            .navigationTitle("Thermostat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose).frame(minHeight: 44)
            } }
            .confirmationDialog(model.picker?.title ?? "", isPresented: Binding(
                get: { model.picker != nil }, set: { if !$0 { model.dismissPicker() } }
            ), titleVisibility: .visible, presenting: model.picker) { pick in
                ForEach(pick.options, id: \.self) { option in
                    Button(option.replacingOccurrences(of: "_", with: " ").capitalized) { model.select(pick, option: option) }
                        .frame(minHeight: 44)
                }
                Button("Cancel", role: .cancel) { model.dismissPicker() }.frame(minHeight: 44)
            }
        }
        .task { model.open() }
        .onChange(of: scenePhase) { if scenePhase == .active { model.revalidate() } }
        .onChange(of: signal.tick) { model.revalidate() }
        .onDisappear { model.close() }
    }
    private func identity(_ session: ThermostatRouteSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.shownEnvelope.snapshot.name).font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(session.openingTicket.evidence.entityID).font(.callout).foregroundStyle(.secondary)
            if let date = thermostatSavedObservation(session.shownEnvelope.presentation) {
                Text("Saved reading · \(thermostatObservationText(date))")
                    .accessibilityLabel("Saved reading, \(thermostatObservationText(date))")
            } else { Text("No saved reading") }
        }
    }
    private func recovery(_ session: ThermostatRouteSession) -> String? {
        switch session.status {
        case .expired: return "These saved readings have expired. Open Live and use Refresh."
        case .selectionChanged: return "The selected thermostat or sensors changed. These readings remain read-only."
        case .sharedStoreUnavailable: return "Shared storage is unavailable. These are the saved readings; controls are unavailable."
        case .unavailable: return "These saved readings are unavailable."
        case .current: break
        }
        switch session.shownEnvelope.presentation.recovery {
        case .setup: return "Choose a thermostat in Settings."
        case .authentication: return "Sign in again to check this thermostat."
        case .readFailed: return session.shownEnvelope.snapshot.error ?? "Couldn't check Home Assistant."
        case .readingsNotSaved: return "Couldn't save these readings. Refresh to retry."
        case .operationNotSaved: return "Couldn't save the update. Refresh to check your thermostat."
        case .sharedStoreUnavailable: return "Shared storage is unavailable."
        case .selectionChanged: return "Details changed. These readings are read-only."
        case .none: break
        }
        if case .pending = session.shownEnvelope.presentation.operation { return "Update pending. Refresh is unavailable while the update is pending." }
        if case .failed(let operation) = session.shownEnvelope.presentation.operation { return operation.error }
        return nil
    }
    @ViewBuilder private func targets(_ envelope: ThermostatLiveEnvelope, origin: ClimateControlOrigin?) -> some View {
        let facts = thermostatTargetFacts(envelope.presentation)
        let snap = envelope.snapshot
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(facts, id: \.kind) { fact in
                    target(fact, origin: origin,
                        canDown: fact.kind == .heat ? snap.canAdjustHeatDown : fact.kind == .cool ? snap.canAdjustCoolDown : false,
                        canUp: fact.kind == .heat ? snap.canAdjustHeatUp : fact.kind == .cool ? snap.canAdjustCoolUp : false)
                }
            }
        }
    }
    @ViewBuilder private func controls(_ envelope: ThermostatLiveEnvelope, origin: ClimateControlOrigin) -> some View {
        let snap = envelope.snapshot
        if snap.canPickMode || snap.canPickFan || snap.canResume {
            VStack(alignment: .leading, spacing: 12) {
                if snap.canPickMode {
                    Button { model.choose(kind: "mode") } label: {
                        Text("Mode · \(envelope.presentation.state?.mode ?? snap.mode)")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.bordered)
                }
                if snap.canPickFan {
                    Button { model.choose(kind: "fan") } label: {
                        Text("Fan · \(envelope.presentation.state?.fanMode ?? "Choose")")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.bordered)
                }
                if snap.canResume {
                    Button("Resume") { model.act("resume", origin: origin) }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).buttonStyle(.bordered)
                }
            }.disabled(model.checking)
        }
    }
    private func target(_ fact: ThermostatTargetFact, origin: ClimateControlOrigin?,
                        canDown: Bool, canUp: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            targetValue(fact)
            if let origin, canDown || canUp {
                HStack {
                    Button("Lower") { model.act(fact.kind == .heat ? "heatDown" : "coolDown", origin: origin) }
                        .frame(maxWidth: .infinity, minHeight: 44).disabled(!canDown)
                    Button("Raise") { model.act(fact.kind == .heat ? "heatUp" : "coolUp", origin: origin) }
                        .frame(maxWidth: .infinity, minHeight: 44).disabled(!canUp)
                }.buttonStyle(.bordered).disabled(model.checking)
            }
        }
    }
    private func targetValue(_ fact: ThermostatTargetFact) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(fact.kind.title) · \(fact.valueText())").font(.headline)
            Text(fact.reportedUnit.map { "Reported unit · \($0)" } ?? "Unit not reported")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
    private func readings(_ presentation: ThermostatPresentation) -> some View {
        let otherTargets = thermostatOtherReportedTargets(presentation)
        return VStack(alignment: .leading, spacing: 18) {
            Text("Readings").font(.headline)
            facet(presentation.room)
            if let humidity = presentation.humidity { Text("Relative humidity · \(humidity.formatted())%") }
            if let state = presentation.state {
                Text("HVAC mode · \(state.mode)")
                Text("HVAC action · \(state.action ?? "Not reported")")
                if let fan = state.fanMode { Text("Fan mode · \(fan)") }
            }
            if !otherTargets.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Other reported targets").font(.headline)
                    Text("Read only").font(.callout).foregroundStyle(.secondary)
                    ForEach(otherTargets, id: \.kind) { targetValue($0) }
                }
            }
            ForEach(presentation.sensors, id: \.entityID) { facet($0) }
            if !presentation.unfetchedSensorIDs.isEmpty {
                Text("Not fetched · \(presentation.unfetchedSensorIDs.joined(separator: ", ")). Only the first three selected sensors are checked.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func facet(_ reading: ThermostatReadingFacet) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(reading.name).font(.headline)
            Text(value(reading)).font(.title3)
            Text(availability(reading.availability))
            Text(reading.reportedUnit.map { "Reported unit · \($0)" } ?? "Unit not reported")
            Text("Home Assistant · \(reading.entityID)").font(.callout).foregroundStyle(.secondary)
            if let checked = reading.checkedAt { Text("Checked · \(thermostatObservationText(checked))") }
            if let changed = reading.lastChanged { Text("Changed · \(thermostatObservationText(changed))") }
            if let failure = reading.failure {
                Text("Check failed · \(failure.message)").foregroundStyle(.secondary)
                Text("Attempt · \(thermostatObservationText(failure.checkedAt))").font(.callout)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func value(_ reading: ThermostatReadingFacet) -> String {
        switch reading.value {
        case .number(let number): number.formatted() + (reading.reportedUnit.map { " \($0)" } ?? "")
        case .text(let text): text + (reading.reportedUnit.map { " \($0)" } ?? "")
        case nil: "—"
        }
    }
    private func availability(_ availability: ThermostatReadingAvailability) -> String {
        switch availability {
        case .current: "Current saved observation"
        case .lastKnown: "Last known"
        case .unavailable: "Unavailable"
        case .noReading: "No reading"
        }
    }
}
