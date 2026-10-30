import SwiftUI
import HearthKit

/// Multi-select entity picker (e.g. room sensors across `sensor` + `binary_sensor`). Reports the
/// Existing selection order and missing IDs survive another toggle.
struct MultiEntityPickerView: View {
    let config: HaConfig
    let domains: [String]
    let title: String
    let onChange: ([String]) -> Void
    let doorsOnly: Bool
    private let requestScope: String?

    @State private var selected: Set<String>
    @State private var selectedOrder: [String]
    @State private var entities: [HaEntity] = []
    @State private var phase: Phase = .loading

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    init(config: HaConfig, domains: [String], title: String, selected: [String],
         doorsOnly: Bool = false,
         onChange: @escaping ([String]) -> Void) {
        self.config = config; self.domains = domains; self.title = title; self.onChange = onChange
        self.doorsOnly = doorsOnly
        let current = HaConfigStore.context()
        requestScope = haSameConnection(current?.config, config) ? current?.scope : nil
        _selected = State(initialValue: Set(selected))
        _selectedOrder = State(initialValue: selected)
    }

    var body: some View {
        List {
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
                let missing = selectedOrder.filter { id in selected.contains(id) && !entities.contains { $0.id == id } }
                if !missing.isEmpty {
                    Section("Not currently found") {
                        ForEach(missing, id: \.self) { id in row(HaEntity(id: id, name: id)) }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func row(_ e: HaEntity) -> some View {
        Button {
            if selected.contains(e.id) { selected.remove(e.id) } else { selected.insert(e.id) }
            selectedOrder = preserveSelectionOrder(selectedOrder, selected: selected, available: entities.map(\.id))
            onChange(selectedOrder)
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
    }

    private func load() async {
        phase = .loading
        do {
            guard let current = HaConfigStore.context(), current.scope == requestScope,
                  let latest = current.config, haSameConnection(latest, config) else {
                throw HaError("Your account changed. Reopen Settings to continue.")
            }
            let json = try await HaClient(latest).allStatesJson()
            guard let completed = HaConfigStore.context(), completed.scope == requestScope,
                  let currentConfig = completed.config, haSameConnection(currentConfig, config) else {
                throw HaError("Your account changed. Reopen Settings to continue.")
            }
            guard let data = json.data(using: .utf8),
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
        } catch {
            phase = .failed(friendlyError(error))
        }
    }
}
