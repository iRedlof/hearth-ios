import SwiftUI
import HearthKit

/// Multi-select entity picker. Saved order and missing IDs survive another toggle.
@MainActor
struct MultiEntityPickerView: View {
    let config: HaConfig
    let domains: [String]
    let title: String
    let runtime: any SettingsRuntime
    let onChange: ([String]) throws -> Void
    let doorsOnly: Bool
    let limit: Int?
    private let requestScope: String?

    @State private var selected: Set<String>
    @State private var selectedOrder: [String]
    @State private var entities: [HaEntity] = []
    @State private var phase: Phase = .loading
    @State private var limitBlocked = false
    @State private var saveError: String?

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    init(config: HaConfig, domains: [String], title: String, selected: [String],
         doorsOnly: Bool = false, limit: Int? = nil,
         runtime: any SettingsRuntime = LiveSettingsRuntime.shared,
         onChange: @escaping ([String]) throws -> Void) {
        self.config = config; self.domains = domains; self.title = title; self.onChange = onChange
        self.doorsOnly = doorsOnly
        self.limit = limit
        self.runtime = runtime
        let current = runtime.loadHa()
        requestScope = haSameConnection(current?.config, config) ? current?.scope : nil
        _selected = State(initialValue: Set(selected))
        _selectedOrder = State(initialValue: preserveSelectionOrder(selected, selected: Set(selected), available: []))
    }

    var body: some View {
        List {
            Section {
                Text(selectionCount)
                    .accessibilityIdentifier("settings.picker.count")
                if let limit, selected.count >= limit {
                    Text("Remove a selected item before adding another. Existing selections stay until you remove them.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if limitBlocked {
                    Text("Remove a selected item before adding another.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            switch phase {
            case .loading:
                HStack(spacing: 10) { ProgressView(); Text("Loading entities…") }.foregroundStyle(.secondary)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 10) {
                    Text(message).foregroundStyle(.red)
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                if entities.isEmpty { Text("No matching entities found").foregroundStyle(.secondary) }
                ForEach(entities) { row($0) }
            }
            if !missingSelections.isEmpty {
                Section(phase == .loaded ? "Not currently found" : "Saved selections") {
                    ForEach(missingSelections, id: \.self) { id in row(HaEntity(id: id, name: id)) }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Couldn't save settings", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(saveError ?? "") }
    }

    private func row(_ e: HaEntity) -> some View {
        Button {
            guard settingsDiscoveryCurrent(config: config, scope: requestScope, current: runtime.loadHa()) else {
                phase = .failed("Your account changed. Reopen Settings to continue.")
                return
            }
            let edit = selectionAfterToggle(selectedOrder, id: e.id, available: entities.map(\.id), limit: limit)
            limitBlocked = edit.blockedByLimit
            guard !edit.blockedByLimit else { return }
            do {
                try onChange(edit.ids)
                selectedOrder = edit.ids
                selected = Set(edit.ids)
            } catch { saveError = friendlyError(error) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.name).foregroundStyle(.primary)
                    Text(e.id).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selected.contains(e.id) {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                }
            }
        }
        .accessibilityIdentifier("settings.picker.\(e.id)")
        .accessibilityValue(selected.contains(e.id) ? "Selected" : "Not selected")
    }

    private var selectionCount: String {
        guard let limit else { return "\(selected.count) selected" }
        return selected.count > limit ? "\(selected.count) selected · Limit \(limit)" :
            "\(selected.count) of \(limit) selected"
    }

    private var missingSelections: [String] {
        selectedOrder.filter { id in
            selected.contains(id) && (phase != .loaded || !entities.contains { $0.id == id })
        }
    }

    private func load() async {
        phase = .loading
        do {
            let discovery = try await runtime.discoverHa(config: config, scope: requestScope,
                purpose: .entities(domains, doorsOnly: doorsOnly))
            guard let completed = runtime.loadHa(), completed.scope == requestScope,
                  let currentConfig = completed.config, haSameConnection(currentConfig, config) else {
                throw HaError("Your account changed. Reopen Settings to continue.")
            }
            guard let data = discovery.statesJSON.data(using: .utf8),
                  let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw HaError("Unexpected entity list")
            }
            let eligible = doorsOnly ? rows.filter {
                guard let data = try? JSONSerialization.data(withJSONObject: $0),
                      let value = String(data: data, encoding: .utf8) else { return false }
                return isDoorEligible(value)
            } : rows
            let filtered = String(data: try JSONSerialization.data(withJSONObject: eligible), encoding: .utf8) ?? "[]"
            entities = entitiesInDomains(parseEntities(filtered), domains)
            if doorsOnly {
                selectedOrder = currentConfig.doorIds
                selected = Set(selectedOrder)
            }
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(friendlyError(error))
        }
    }
}
