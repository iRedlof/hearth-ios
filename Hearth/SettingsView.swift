import SwiftUI
import HearthKit

/// Each provider has independent setup and account ownership. Settings itself is always available.
@MainActor
struct SettingsView: View {
    @State private var config: HaConfig?
    let runtime: any SettingsRuntime
    let onChange: (HaConfig?) -> Void
    let onOpenGallery: () -> Void
    let onRefresh: () -> Void
    let onSignOut: () -> Void

    init(config: HaConfig?, runtime: any SettingsRuntime = LiveSettingsRuntime.shared,
         onChange: @escaping (HaConfig?) -> Void, onOpenGallery: @escaping () -> Void = {},
         onRefresh: @escaping () -> Void = {}, onSignOut: @escaping () -> Void = {}) {
        _config = State(initialValue: config)
        self.runtime = runtime
        self.onChange = onChange
        self.onOpenGallery = onOpenGallery
        self.onRefresh = onRefresh
        self.onSignOut = onSignOut
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
                                .font(HearthFont.iconMedium.font.weight(.regular))
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
                                .font(HearthFont.iconMedium.font.weight(.regular))
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
                                .font(HearthFont.iconMedium.font.weight(.regular))
                                .symbolRenderingMode(.monochrome)
                                .frame(width: 24, height: 24)
                            Text("Widget previews").font(.body)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(HearthFont.callout.font.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.widgetPreviews")
                } footer: {
                    Text("Explore widget layouts with example data. No account connection is required.")
                }

                Section {
                    Button {
                        onRefresh()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.clockwise")
                                .font(HearthFont.iconMedium.font.weight(.regular))
                                .symbolRenderingMode(.monochrome)
                                .frame(width: 24, height: 24)
                            Text("Refresh").font(.body)
                        }
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.refresh")

                    Button(role: .destructive) {
                        onSignOut()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(HearthFont.iconMedium.font.weight(.regular))
                                .symbolRenderingMode(.monochrome)
                                .frame(width: 24, height: 24)
                            Text("Sign out").font(.body)
                        }
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.signOut")
                } header: {
                    Text("Actions")
                }
            }
            .navigationTitle("Settings")
            .accessibilityIdentifier("settings.root")
        }
    }
}
