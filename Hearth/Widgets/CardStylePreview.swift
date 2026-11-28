import SwiftUI
import WidgetKit
import HearthKit

/// What a widget kind's preview draws: the person's own current data.
enum CardStylePreviewData {
    case car(CarSnapshot)
    case alarm(AlarmSnapshot)
    case chargePoint(CpSnapshot)
    case battery(BatterySnapshot)
    case activity(ActivitySnapshot)
    case lights(LightsSnapshot)
    case quick(QuickSnapshot)
    case favourites(FavSnapshot)
    case doors(DoorsSnapshot)
}

/// Reads each added widget's current data once, with the same live helpers the widgets and
/// `WidgetPage` use. The Thermostat reads through `ThermostatLiveModel`, which the page owns.
@MainActor
final class CardStylePreviewModel: ObservableObject {
    @Published private(set) var data: [HomeWidgetKind: CardStylePreviewData] = [:]

    func load(_ kind: HomeWidgetKind, config: HaConfig?) async {
        guard data[kind] == nil, let loaded = await Self.read(kind, config: config) else { return }
        data = data.merging([kind: loaded]) { _, new in new }
    }

    private static func read(_ kind: HomeWidgetKind, config: HaConfig?) async -> CardStylePreviewData? {
        let now = Date()
        switch kind {
        case .car: return .car(await CarLiveSnapshot.fetch(now: now))
        case .alarm:
            guard config?.isComplete == true else { return nil }
            return .alarm(AlarmLiveSnapshot.currentFeedback(await AlarmLiveSnapshot.fetch(now: now)))
        case .thermostat: return nil
        case .chargePoint: return .chargePoint(await CpLiveSnapshot.fetch(now: now))
        case .battery: return .battery(await CollectionLiveSnapshots.batteries(now: now))
        case .activity: return .activity(await CollectionLiveSnapshots.activity(now: now))
        case .doors: return .doors(await CollectionLiveSnapshots.doors(now: now))
        case .lights: return .lights(await fetchLightsSnapshot(config, now: now))
        case .quick: return .quick(await fetchQuickSnapshot(config, now: now))
        case .favourites: return .favourites(await fetchFavouritesSnapshot(config, now: now))
        }
    }
}

/// One widget drawn for real in `style`: its own data when there is some, else the sample.
/// A picture only: it takes no taps, and VoiceOver reads it as one image.
struct CardStylePreviewCard: View {
    let kind: HomeWidgetKind
    let data: CardStylePreviewData?
    let thermostat: ThermostatEntryPayload?
    let style: CardStyle

    private enum Size {
        static let width: CGFloat = 329
        static let mediumHeight: CGFloat = 155
        static let largeHeight: CGFloat = 345
        static let corner: CGFloat = 22
    }

    /// The size the widget is drawn at: its one Home Screen size.
    private var size: CGSize {
        switch kind.previewKind.family {
        case .medium: CGSize(width: Size.width, height: Size.mediumHeight)
        case .large: CGSize(width: Size.width, height: Size.largeHeight)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            // Scaled down if wider than the page, never up.
            let scale = geometry.size.width / size.width
            widget
                .cardStyle(style)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: Size.corner, style: .continuous))
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .aspectRatio(size.width / size.height, contentMode: .fit)
        .frame(maxWidth: size.width)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of \(kind.displayName)")
        .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder private var widget: some View {
        switch kind {
        case .car: CarBeaconView(car ?? .sample, interactionMode: .inert)
        case .alarm: AlarmBeaconView(alarm ?? AlarmParityInputs.snapshot("disarmed"))
        case .thermostat: thermostatWidget
        case .chargePoint: CpBeaconView(chargePoint ?? .sample)
        case .battery: BatteryView(battery ?? .sample, layoutFamily: .systemMedium)
        case .activity: ActivityView(activity ?? .sample)
        case .lights: LightTileView(lights ?? .sample)
        case .quick: QuickView(quick ?? .sample)
        case .favourites: FavouritesView(favourites ?? .sample)
        case .doors: DoorsView(doors ?? .sample)
        }
    }

    @ViewBuilder private var thermostatWidget: some View {
        if let thermostat { ThermostatBeaconView(thermostat) }
        else { ThermostatBeaconView(.sample) }
    }

    // MARK: - The loaded data, by kind

    private var car: CarSnapshot? { if case .car(let value) = data { value } else { nil } }
    private var alarm: AlarmSnapshot? { if case .alarm(let value) = data { value } else { nil } }
    private var chargePoint: CpSnapshot? { if case .chargePoint(let value) = data { value } else { nil } }
    private var battery: BatterySnapshot? { if case .battery(let value) = data { value } else { nil } }
    private var activity: ActivitySnapshot? { if case .activity(let value) = data { value } else { nil } }
    private var lights: LightsSnapshot? { if case .lights(let value) = data { value } else { nil } }
    private var quick: QuickSnapshot? { if case .quick(let value) = data { value } else { nil } }
    private var favourites: FavSnapshot? { if case .favourites(let value) = data { value } else { nil } }
    private var doors: DoorsSnapshot? { if case .doors(let value) = data { value } else { nil } }
}

/// The numbers of `WallpaperBackdrop.kt`.
private enum WallpaperLook {
    static let dusk: [UInt32] = [0xFF6F8796, 0xFF3A4A5A, 0xFF232B35]
    static let warm: [UInt32] = [0x99F2DDB8, 0x00F2DDB8]
    static let cool: [UInt32] = [0x667FC4C9, 0x007FC4C9]
    static let warmCentre = UnitPoint(x: 0.12, y: 0.10)
    static let coolCentre = UnitPoint(x: 0.92, y: 0.95)
    /// Glow radii, as a share of the shorter side.
    static let warmRadius: CGFloat = 0.9
    static let coolRadius: CGFloat = 0.8
    static let padding: CGFloat = 14
    static let corner: CGFloat = 24
}

/// What is behind a widget preview, as a wallpaper would be: a calm dusk (slate to deep blue-grey)
/// with a warm glow top-leading and a cool one bottom-trailing. Ported from `WallpaperBackdrop.kt`.
struct WallpaperBackdrop<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(WallpaperLook.padding)
            .background { backdrop }
            .clipShape(RoundedRectangle(cornerRadius: WallpaperLook.corner, style: .continuous))
    }

    private var backdrop: some View {
        GeometryReader { geometry in
            let shorter = min(geometry.size.width, geometry.size.height)
            ZStack {
                LinearGradient(colors: WallpaperLook.dusk.map(Color.init(argb:)), startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: WallpaperLook.warm.map(Color.init(argb:)), center: WallpaperLook.warmCentre,
                               startRadius: 0, endRadius: shorter * WallpaperLook.warmRadius)
                RadialGradient(colors: WallpaperLook.cool.map(Color.init(argb:)), center: WallpaperLook.coolCentre,
                               startRadius: 0, endRadius: shorter * WallpaperLook.coolRadius)
            }
        }
    }
}
