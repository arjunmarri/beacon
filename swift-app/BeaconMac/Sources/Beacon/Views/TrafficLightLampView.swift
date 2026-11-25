import SwiftUI

struct TrafficLightLampView: View {
    let active: TrafficLightColor
    let label: String
    @Environment(\.colorScheme) private var colorScheme

    private var palette: BeaconPalette { BeaconPalette(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                lampDot(color: Color(red: 0.96, green: 0.28, blue: 0.34), lit: active == .red)
                lampDot(color: Color(red: 0.98, green: 0.65, blue: 0.16), lit: active == .amber)
                lampDot(color: Color(red: 0.18, green: 0.84, blue: 0.54), lit: active == .green)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                ZStack {
                    Capsule()
                        .fill(palette.controlMaterial)
                    Capsule()
                        .fill(palette.isLight ? Color.white.opacity(0.65) : Color.black.opacity(0.32))
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(palette.specularBorderGradient, lineWidth: 1)
            }
            .clipShape(Capsule())

            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(labelColor)
                .lineLimit(1)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: active)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(label)")
    }

    private func lampDot(color: Color, lit: Bool) -> some View {
        ZStack {
            Circle()
                .fill(lit ? color : (palette.isLight ? Color.black.opacity(0.11) : Color.white.opacity(0.11)))
                .frame(width: 8, height: 8)
            if lit {
                Circle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 2.5, height: 2.5)
                    .offset(x: -1.4, y: -1.4)
            }
        }
        .shadow(color: lit ? color.opacity(palette.isLight ? 0.50 : 0.80) : .clear, radius: lit ? 5 : 0)
        .scaleEffect(lit ? 1.06 : 0.92)
    }

    private var labelColor: Color {
        switch active {
        case .green: return palette.successText
        case .amber: return palette.warningText
        case .red: return palette.errorText
        }
    }
}
