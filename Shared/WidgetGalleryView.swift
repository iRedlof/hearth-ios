import SwiftUI
import HearthKit

/// In-app verification gallery: renders the selected Beacon widget at the medium-widget point size for
/// each target device, to check responsiveness in the Simulator. Pick the widget with the segmented
/// control, or launch with `--args -widget alarm` (or `car`) to preselect it for a screenshot.
struct WidgetGalleryView: View {
    @State private var kind: String = UserDefaults.standard.string(forKey: "widget") ?? "car"

    // systemMedium point sizes (approx) across the devices Rohit named + the smallest, for responsiveness.
    private let sizes: [(label: String, w: CGFloat, h: CGFloat)] = [
        ("iPhone 14 Pro Max · medium", 364, 170),
        ("iPhone 16 / 17 Pro Max · medium", 374, 174),
        ("iPhone 17 Pro (smaller) · medium", 360, 169),
        ("Smallest iPhone · medium", 329, 155),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Widget", selection: $kind) {
                Text("Car").tag("car")
                Text("Alarm").tag("alarm")
                Text("Thermostat").tag("thermostat")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 20) {
                    Text("Hearth · \(kind == "alarm" ? "Alarm" : kind == "thermostat" ? "Thermostat" : "Car") Beacon")
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
        default: CarBeaconView(.sample)
        }
    }
}

#Preview { WidgetGalleryView() }
