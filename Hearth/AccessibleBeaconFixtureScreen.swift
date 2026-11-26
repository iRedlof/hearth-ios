#if DEBUG
import SwiftUI
import HearthKit

/// An app-native scroll/typography proof, deliberately disconnected from all command runtimes.
struct AccessibleBeaconFixtureScreen: View {
    let concept: AccessibleBeaconConcept
    @State private var showingReadings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Larger-text design").font(.title2.bold())
                    Text("At larger text sizes, the widget shows a summary. Open Controls or Readings for the full view.")
                    GeometryReader { geometry in
                        let compact = geometry.size.width < 349.6666666667
                        Button { showingReadings = true } label: {
                            AccessibleBeaconConceptView(concept: concept)
                                .frame(width: compact ? 333.6666666667 : 349.6666666667,
                                       height: compact ? 159 : 164.3333333333)
                                .clipShape(RoundedRectangle(cornerRadius: 22))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: 164.3333333333)
                    Text("Example data. This app preview is not a WidgetKit Home Screen capture.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }
            .navigationTitle("Beacon prototype")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingReadings) { destination }
        }
        .preferredColorScheme(.dark)
        .task {
            if ProcessInfo.processInfo.arguments.contains("-accessibleSheet") { showingReadings = true }
        }
    }

    private var destination: some View {
        NavigationStack {
            Form {
                Section {
                    Text(concept.identity).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                    Text(concept.primary).font(.headline)
                    Text("Design prototype. All controls below are inert examples.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if concept.carImage {
                        Image("CarPremium").resizable().scaledToFit()
                            .accessibilityLabel("Premium Model Y with full-width headlight bar")
                    }
                }
                if !concept.controls.isEmpty {
                    Section("Controls") {
                        ForEach(concept.controls) { control in
                            VStack(alignment: .leading, spacing: 6) {
                                Label(control.title, systemImage: control.symbol)
                                    .font(.body.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                if let reason = control.reason {
                                    Text(reason).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.vertical, 6)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                ForEach(concept.sections.filter { !$0.rows.isEmpty }) { section in
                    Section(section.title) {
                        ForEach(section.rows) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(row.label).font(.subheadline).foregroundStyle(.secondary)
                                Text(row.value.isEmpty ? "Unknown" : row.value)
                                    .font(.body).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .navigationTitle("Readings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { showingReadings = false } }
            }
        }
        .presentationDetents([.large])
    }
}
#endif
