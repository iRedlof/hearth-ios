import SwiftUI
import HearthKit

/// Each provider has independent setup and account ownership. Settings itself is always available.
@MainActor
struct SettingsView: View {
    @State private var config: HaConfig?
    let runtime: any SettingsRuntime
    let onChange: (HaConfig?) -> Void
    let onOpenGallery: () -> Void

    init(config: HaConfig?, runtime: any SettingsRuntime = LiveSettingsRuntime.shared,
         onChange: @escaping (HaConfig?) -> Void, onOpenGallery: @escaping () -> Void = {}) {
        _config = State(initialValue: config)
        self.runtime = runtime
        self.onChange = onChange
        self.onOpenGallery = onOpenGallery
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        HomeAssistantPage(config: config, runtime: runtime) { next in
                            self.config = next
                            onChange(next)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "house")
                                .font(.system(size: 20, weight: .regular))
                                .symbolRenderingMode(.monochrome)
                                .frame(width: 24, height: 24)
                            Text("Home Assistant").font(.body)
                        }
                        .frame(minHeight: 48)
                    }
                    .accessibilityIdentifier("settings.ha")

                    NavigationLink {
                        ChargePointPage(runtime: runtime)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bolt.car")
                                .font(.system(size: 20, weight: .regular))
                                .symbolRenderingMode(.monochrome)
                                .frame(width: 24, height: 24)
                            Text("ChargePoint").font(.body)
                        }
                        .frame(minHeight: 48)
                    }
                    .accessibilityIdentifier("settings.cp")
                } header: {
                    Text("Accounts")
                }

                Section {
                    Button {
                        onOpenGallery()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 20, weight: .regular))
                                .symbolRenderingMode(.monochrome)
                                .frame(width: 24, height: 24)
                            Text("Widget previews").font(.body)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.widgetPreviews")
                } footer: {
                    Text("Explore widget layouts with example data. No account connection is required.")
                }
            }
            .navigationTitle("Settings")
            .accessibilityIdentifier("settings.root")
        }
    }
}
