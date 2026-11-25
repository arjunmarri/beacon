import SwiftUI

struct TrafficLightLampView: View {
    let active: TrafficLightColor
    let label: String
    @Environment(\.colorScheme) private var colorScheme

    private var palette: BeaconPalette { BeaconPalette(colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                lampDot(color: .red, lit: active == .red)
                lampDot(color: .orange, lit: active == .amber)
                lampDot(color: .green, lit: active == .green)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(palette.isLight ? Color(red: 0.93, green: 0.945, blue: 0.97) : Color(red: 0.043, green: 0.051, blue: 0.063))
            .overlay(
                Capsule()
                    .stroke(palette.border, lineWidth: 1)
            )
            .clipShape(Capsule())

            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(labelColor)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(label)")
    }

    private func lampDot(color: Color, lit: Bool) -> some View {
        Circle()
            .fill(lit ? color : (palette.isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.12)))
            .frame(width: 8, height: 8)
            .shadow(color: lit ? color.opacity(palette.isLight ? 0.45 : 0.75) : .clear, radius: 4)
    }

    private var labelColor: Color {
        switch active {
        case .green: return palette.successText
        case .amber: return palette.warningText
        case .red: return palette.errorText
        }
    }
}
