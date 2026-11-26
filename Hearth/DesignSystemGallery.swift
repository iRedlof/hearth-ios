#if DEBUG
import SwiftUI
import HearthKit

/// Design system gallery — verification artifact showing all Phase 1 components.
/// DEBUG-only; not wired into shipping navigation.
struct DesignSystemGallery: View {
    @State private var switchIsOn = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                titleSection
                pillsSection
                tilesSection
                switchSection
                buttonsSection
                groupsSection
            }
            .padding(20)
        }
        .background(HearthColor.page(scheme))
    }

    private var titleSection: some View {
        Text("Hearth")
            .font(HearthFont.largeTitle.font)
            .foregroundStyle(HearthColor.ink(scheme))
    }

    private var pillsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status Pills")
                .font(HearthFont.cardHeading.font)
                .foregroundStyle(HearthColor.ink(scheme))

            HStack(spacing: 12) {
                StatusPill("Connected", tone: .ok)
                StatusPill("Needs sign-in", tone: .warn)
                StatusPill("Offline", tone: .neutral)
            }
        }
    }

    private var tilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Icon Tiles")
                .font(HearthFont.cardHeading.font)
                .foregroundStyle(HearthColor.ink(scheme))

            HStack(spacing: 12) {
                IconTile(systemName: "house.fill", hue: .blue)
                IconTile(systemName: "calendar", hue: .orange)
                IconTile(systemName: "music.note", hue: .purple)
                IconTile(systemName: "lightbulb.fill", hue: .amber)
            }

            HStack(spacing: 12) {
                IconTile(systemName: "leaf.fill", hue: .green)
                IconTile(systemName: "lock.fill", hue: .red)
                IconTile(systemName: "theatermasks.fill", hue: .neutral)
            }
        }
    }

    private var switchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Switch")
                .font(HearthFont.cardHeading.font)
                .foregroundStyle(HearthColor.ink(scheme))

            HStack(spacing: 12) {
                HearthSwitch(isOn: .constant(false))
                HearthSwitch(isOn: $switchIsOn)
            }
        }
    }

    private var buttonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Buttons")
                .font(HearthFont.cardHeading.font)
                .foregroundStyle(HearthColor.ink(scheme))

            Button("Add to Home Screen") {}
                .hearthInk()

            Button("Test now") {}
                .hearthInline()
        }
    }

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Groups with Auto-Dividers")
                .font(HearthFont.cardHeading.font)
                .foregroundStyle(HearthColor.ink(scheme))

            HearthGroup("Connections") {
                HearthRow(
                    icon: "house.fill",
                    hue: .blue,
                    title: "Home Assistant"
                ) {
                    StatusPill("Connected", tone: .ok)
                }

                HearthRow(
                    icon: "bolt.car.fill",
                    hue: .orange,
                    title: "ChargePoint",
                    subtitle: "Sign in to continue",
                    subtitleWarn: true
                ) {
                    StatusPill("Needs sign-in", tone: .warn)
                }
            }
        }
    }
}

#Preview("Light Mode") {
    DesignSystemGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    DesignSystemGallery()
        .preferredColorScheme(.dark)
}
#endif
