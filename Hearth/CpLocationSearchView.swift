import SwiftUI
import MapKit
import WidgetKit
import HearthKit

/// Search an address / building / ZIP, geocode it (MapKit), query ChargePoint's map for stations
/// around it, group them into locations, and let the user pick one. The chosen location (with its
/// bounds) is persisted so the widget can show plug counts and Join. Mirrors Android's location search.
struct CpLocationSearchView: View {
    var onPicked: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [CpLocation] = []
    @State private var phase: Phase = .idle

    private enum Phase: Equatable { case idle, searching, failed(String) }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Address, building or ZIP", text: $query)
                        .textInputAutocapitalization(.words)
                        .onSubmit { Task { await search() } }
                    Button("Search") { Task { await search() } }.disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            switch phase {
            case .searching:
                HStack(spacing: 10) { ProgressView(); Text("Searching…") }.foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).foregroundStyle(.red)
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
        .navigationTitle("ChargePoint location")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pick(_ loc: CpLocation) {
        CpSessionStore.saveLocation(loc)
        WidgetCenter.shared.reloadAllTimelines()
        onPicked()
        dismiss()
    }

    private func search() async {
        phase = .searching
        results = []
        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            let response = try await MKLocalSearch(request: request).start()
            guard let coord = response.mapItems.first?.placemark.coordinate else {
                phase = .failed("Couldn't find that place")
                return
            }
            let session = CpSessionStore.load()
            let client = CpClient(token: session.token, userId: session.userId,
                                  onToken: { CpSessionStore.saveToken($0) })
            let stationsJson = try await client.stations(cpBounds(lat: coord.latitude, lon: coord.longitude))
            let found = cpLocations(cpStationsFrom(stationsJson))
            results = found
            phase = found.isEmpty ? .failed("No ChargePoint stations near there") : .idle
        } catch {
            phase = .failed(friendlyError(error))
        }
    }
}
