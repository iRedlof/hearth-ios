import SwiftUI
import HearthKit

/// A reusable Home Assistant entity picker: loads `GET /api/states`, filters to one domain,
/// and reports the chosen entity id back (`""` = None). This is the iOS equivalent of the
/// Android settings entity pickers (alarm panel, lock, climate, …).
///
/// Lives in the app target: it performs a network call and presents navigation UI; the widget
/// extension never configures entities, it only reads the saved `HaConfig`.
struct EntityPickerView: View {
    let config: HaConfig
    let domain: String
    let title: String
    let allowNone: Bool
    let selected: String
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var entities: [HaEntity] = []
    @State private var phase: Phase = .loading

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    var body: some View {
        List {
            switch phase {
            case .loading:
                HStack(spacing: 10) { ProgressView(); Text("Loading entities…") }
                    .foregroundStyle(.secondary)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 10) {
                    Text(message).foregroundStyle(.red)
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                if allowNone { row(id: "", name: "None") }
                if entities.isEmpty {
                    Text("No \(title.lowercased()) entities found")
                        .foregroundStyle(.secondary)
                }
                ForEach(entities) { row(id: $0.id, name: $0.name) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder private func row(id: String, name: String) -> some View {
        Button {
            onPick(id)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).foregroundStyle(.primary)
                    if !id.isEmpty {
                        Text(id).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if id == selected {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                }
            }
        }
    }

    private func load() async {
        phase = .loading
        do {
            let json = try await HaClient(config).allStatesJson()
            entities = entitiesInDomain(parseEntities(json), domain)
            phase = .loaded
        } catch {
            phase = .failed(friendlyError(error))
        }
    }
}
