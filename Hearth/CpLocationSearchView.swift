import SwiftUI
import MapKit
import WidgetKit
import HearthKit

/// A query captures Settings ownership before geocoding; its results retain that owner through picking.
struct CpLocationSearchView: View {
    let expected: CpSettingsOrigin?
    var onPicked: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [CpLocation] = []
    @State private var owner: CpDiscoveryOwner?
    @State private var phase: Phase = .idle
    private enum Phase: Equatable { case idle, searching, failed(String) }

    init(expected: CpSettingsOrigin? = nil, onPicked: @escaping () -> Void) {
        self.expected = expected ?? (try? CpSessionStore.context().settingsOrigin)
        self.onPicked = onPicked
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Address, building or ZIP", text: $query)
                        .textInputAutocapitalization(.words).onSubmit { Task { await search() } }
                    Button("Search") { Task { await search() } }
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || expected == nil)
                }
            }
            switch phase {
            case .searching:
                HStack(spacing: 10) { ProgressView(); Text("Searching…") }.foregroundStyle(.secondary)
            case .failed(let message): Text(message).foregroundStyle(.red)
            case .idle:
                if !results.isEmpty {
                    Section("ChargePoint locations near there") {
                        ForEach(results, id: \.name) { loc in
                            Button { pick(loc) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(loc.title).foregroundStyle(.primary)
                                    Text("\(loc.fullAddress) · \(loc.deviceIds.count) chargers")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("ChargePoint location").navigationBarTitleDisplayMode(.inline)
        .onChange(of: query) { _, _ in owner = nil; results = []; phase = .idle }
    }

    private func pick(_ loc: CpLocation) {
        do {
            guard let owner, try CpSessionStore.repository().store.finishDiscovery(owner: owner, location: loc) != nil else {
                phase = .failed("Details changed · Search again"); return
            }
            WidgetCenter.shared.reloadAllTimelines()
            onPicked(); dismiss()
        } catch { phase = .failed(friendlyError(error)) }
    }

    @MainActor private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        var attempted: CpDiscoveryOwner?
        do {
            guard !text.isEmpty, let expected,
                  let captured = try CpSessionStore.repository().store.beginDiscovery(expected: expected) else {
                phase = .failed("Details changed · Reopen location search"); return
            }
            attempted = captured
            owner = captured; phase = .searching; results = []
            let request = MKLocalSearch.Request(); request.naturalLanguageQuery = text
            let response = try await MKLocalSearch(request: request).start()
            guard owner == captured else { return }
            guard let coord = response.mapItems.first?.placemark.coordinate else {
                phase = .failed("Couldn't find that place"); return
            }
            let stations = try await CpSessionStore.runtime().discover(owner: captured,
                bounds: cpBounds(lat: coord.latitude, lon: coord.longitude))
            guard owner == captured else { return }
            results = cpLocations(stations)
            phase = results.isEmpty ? .failed("No ChargePoint stations near there") : .idle
        } catch {
            guard owner == attempted, query.trimmingCharacters(in: .whitespaces) == text else { return }
            phase = .failed(friendlyError(error))
        }
    }
}
