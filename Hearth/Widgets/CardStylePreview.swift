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

    var car: CarSnapshot? { if case .car(let value) = self { value } else { nil } }
    var alarm: AlarmSnapshot? { if case .alarm(let value) = self { value } else { nil } }
    var chargePoint: CpSnapshot? { if case .chargePoint(let value) = self { value } else { nil } }
    var battery: BatterySnapshot? { if case .battery(let value) = self { value } else { nil } }
    var activity: ActivitySnapshot? { if case .activity(let value) = self { value } else { nil } }
    var lights: LightsSnapshot? { if case .lights(let value) = self { value } else { nil } }
    var quick: QuickSnapshot? { if case .quick(let value) = self { value } else { nil } }
    var favourites: FavSnapshot? { if case .favourites(let value) = self { value } else { nil } }
}

/// Reads a widget's current data with the same live helpers the widgets use, for the previews on
/// the Card style page and each widget's own page. The Thermostat reads through
/// `ThermostatLiveModel`, which the page owns.
@MainActor
final class CardStylePreviewModel: ObservableObject {
    @Published private(set) var data: [HomeWidgetKind: CardStylePreviewData] = [:]

    /// Reads `kind` once; a later call keeps what is already there.
    func load(_ kind: HomeWidgetKind, config: HaConfig?) async {
        guard data[kind] == nil else { return }
        await reload(kind, config: config)
    }

    /// Reads `kind` again, as after its settings changed. What is shown stays until the new data arrives.
    func reload(_ kind: HomeWidgetKind, config: HaConfig?) async {
        guard let loaded = await Self.read(kind, config: config) else { return }
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
        case .lights: return .lights(await CollectionLiveSnapshots.lights(now: now))
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

    /// The size the widget is drawn at: the size this iPhone gives it on the Home Screen, so the
    /// preview is the same box the real widget has to fit.
    private var size: CGSize {
        let real = homeScreenWidgetSize(screenWidth: Double(UIScreen.main.bounds.width))
        return CGSize(width: real.width, height: real.height)
    }

    var body: some View {
        GeometryReader { geometry in
            // Scaled down if wider than the page, never up.
            let scale = geometry.size.width / size.width
            widget
                .cardStyle(style)
                .widgetContainer(size: size)
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
        case .car: CarBeaconView(data?.car ?? .sample, interactionMode: .inert)
        case .alarm: AlarmBeaconView(data?.alarm ?? AlarmParityInputs.snapshot("disarmed"))
        case .thermostat: thermostatWidget
        case .chargePoint: CpBeaconView(data?.chargePoint ?? .sample)
        case .battery: BatteryView(data?.battery ?? .sample, layoutFamily: .systemMedium)
        case .activity: ActivityPanelView(data?.activity ?? .sample)
        case .lights: LightsPanelView(data?.lights ?? .sample)
        case .quick: QuickPanelView(data?.quick ?? .sample)
        case .favourites: FavouritesPanelView(data?.favourites ?? .sample)
        }
    }

    @ViewBuilder private var thermostatWidget: some View {
        if let thermostat { ThermostatBeaconView(thermostat) }
        else { ThermostatBeaconView(.sample) }
    }
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
