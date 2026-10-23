import SwiftUI
import HearthKit

/// In-app verification gallery: renders the Car Beacon view at the medium-widget point size for each
/// target device, so the layout can be checked for responsiveness in the Simulator (one screenshot
/// shows every size). The real home-screen widget is the `HearthWidgets` extension.
struct WidgetGalleryView: View {
    // systemMedium point sizes (approx) across the devices Rohit named + the smallest, to prove responsiveness.
    private let sizes: [(label: String, w: CGFloat, h: CGFloat)] = [
        ("iPhone 14 Pro Max · medium", 364, 170),
        ("iPhone 16 / 17 Pro Max · medium", 374, 174),
        ("iPhone 17 Pro (smaller) · medium", 360, 169),
        ("Smallest iPhone · medium", 329, 155),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Hearth · Car Beacon")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(sizes, id: \.label) { size in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(size.label)  ·  \(Int(size.w))×\(Int(size.h))")
                            .font(.caption).foregroundStyle(.secondary)
                        CarBeaconView(.sample)
                            .frame(width: size.w, height: size.h)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

#Preview { WidgetGalleryView() }
