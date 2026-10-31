import SwiftUI
import HearthKit

/// A reusable Home Assistant entity picker: loads `GET /api/states`, filters to one domain,
/// and reports the chosen entity id back (`""` = None). This is the iOS equivalent of the
/// Android settings entity pickers (alarm panel, lock, climate, …).
///
/// Lives in the app target: it performs a network call and presents navigation UI; the widget
/// extension never configures entities, it only reads the saved `HaConfig`.
@MainActor
struct EntityPickerView: View {
    let config: HaConfig
    let domain: String
    let title: String
    let allowNone: Bool
    let selected: String
    let runtime: any SettingsRuntime
    let onPick: (HaEntity) throws -> Void
    private let requestScope: String?

    @Environment(\.dismiss) private var dismiss
    @State private var entities: [HaEntity] = []
    @State private var phase: Phase = .loading
    @State private var saveError: String?

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    init(config: HaConfig, domain: String, title: String, allowNone: Bool,
         selected: String, runtime: any SettingsRuntime = LiveSettingsRuntime.shared,
         onPick: @escaping (HaEntity) throws -> Void) {
        self.config = config; self.domain = domain; self.title = title
        self.allowNone = allowNone; self.selected = selected; self.onPick = onPick
        self.runtime = runtime
        let current = runtime.loadHa()
        requestScope = haSameConnection(current?.config, config) ? current?.scope : nil
    }

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
        .alert("Couldn't save settings", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(saveError ?? "") }
    }

    @ViewBuilder private func row(id: String, name: String) -> some View {
        Button {
            guard settingsDiscoveryCurrent(config: config, scope: requestScope, current: runtime.loadHa()) else {
                phase = .failed("Your account changed. Reopen Settings to continue.")
                return
            }
            do {
                try onPick(HaEntity(id: id, name: name))
                dismiss()
            } catch { saveError = friendlyError(error) }
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
        .accessibilityIdentifier("settings.picker.\(id.isEmpty ? "none" : id)")
        .accessibilityValue(id == selected ? "Selected" : "Not selected")
    }

    private func load() async {
        phase = .loading
        do {
            let discovery = try await runtime.discoverHa(config: config, scope: requestScope,
                                                         purpose: .entity(domain))
            entities = entitiesInDomain(discovery.entities, domain)
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(friendlyError(error))
        }
    }
}
