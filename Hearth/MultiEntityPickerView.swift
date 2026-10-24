import SwiftUI
import HearthKit

/// Multi-select entity picker (e.g. room sensors across `sensor` + `binary_sensor`). Reports the
/// full selected id list — in the list's display order — on each toggle. iOS parity for Android's
/// multi-pick settings rows.
struct MultiEntityPickerView: View {
    let config: HaConfig
    let domains: [String]
    let title: String
    let onChange: ([String]) -> Void

    @State private var selected: Set<String>
    @State private var entities: [HaEntity] = []
    @State private var phase: Phase = .loading

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    init(config: HaConfig, domains: [String], title: String, selected: [String],
         onChange: @escaping ([String]) -> Void) {
        self.config = config; self.domains = domains; self.title = title; self.onChange = onChange
        _selected = State(initialValue: Set(selected))
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
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func row(_ e: HaEntity) -> some View {
        Button {
            if selected.contains(e.id) { selected.remove(e.id) } else { selected.insert(e.id) }
            onChange(entities.map(\.id).filter { selected.contains($0) })   // stable display order
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
            let json = try await HaClient(config).allStatesJson()
            entities = entitiesInDomains(parseEntities(json), domains)
            phase = .loaded
        } catch {
            phase = .failed(friendlyError(error))
        }
    }
}
