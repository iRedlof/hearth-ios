import SwiftUI
import HearthKit

/// In-app verification gallery: renders the selected Beacon widget at the medium-widget point size for
/// each target device, to check responsiveness in the Simulator. Pick the widget with the segmented
/// control, or launch with `--args -widget alarm` (or `car`) to preselect it for a screenshot.
struct WidgetGalleryView: View {
    @State private var kind: String = UserDefaults.standard.string(forKey: "widget") ?? "car"

    // systemMedium point sizes (approx) across the devices Rohit named + the smallest, for responsiveness.
    private let mediumSizes: [(label: String, w: CGFloat, h: CGFloat)] = [
        ("iPhone 14 Pro Max · medium", 364, 170),
        ("iPhone 16 / 17 Pro Max · medium", 374, 174),
        ("iPhone 17 Pro (smaller) · medium", 360, 169),
        ("Smallest iPhone · medium", 329, 155),
    ]
    // systemLarge for the tall non-Beacon widgets.
    private let largeSizes: [(label: String, w: CGFloat, h: CGFloat)] = [
        ("iPhone 14 Pro Max · large", 364, 382),
        ("Smallest iPhone · large", 329, 345),
    ]
    private let tallKinds: Set<String> = ["battery", "activity", "lights", "favourites", "doors"]
    private var sizes: [(label: String, w: CGFloat, h: CGFloat)] { tallKinds.contains(kind) ? largeSizes : mediumSizes }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Widget", selection: $kind) {
                Text("Car").tag("car")
                Text("Alarm").tag("alarm")
                Text("Thermostat").tag("thermostat")
                Text("ChargePoint").tag("chargepoint")
                Text("Batteries").tag("battery")
                Text("Activity").tag("activity")
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 20) {
                    Text("Hearth · \(galleryTitle)")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(sizes, id: \.label) { size in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(size.label)  ·  \(Int(size.w))×\(Int(size.h))")
                                .font(.caption).foregroundStyle(.secondary)
                            widget
                                .frame(width: size.w, height: size.h)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
        }
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var widget: some View {
        switch kind {
        case "alarm": AlarmBeaconView(.sample)
        case "thermostat": ThermostatBeaconView(.sample)
        case "chargepoint": CpBeaconView(.sample)
        case "battery": BatteryView(.sample)
        case "activity": ActivityView(.sample)
        default: CarBeaconView(.sample)
        }
    }

    private var galleryTitle: String {
        switch kind {
        case "alarm": "Alarm Beacon"
        case "thermostat": "Thermostat Beacon"
        case "chargepoint": "ChargePoint Beacon"
        case "battery": "Batteries"
        case "activity": "Activity"
        default: "Car Beacon"
        }
    }
}

#Preview { WidgetGalleryView() }
