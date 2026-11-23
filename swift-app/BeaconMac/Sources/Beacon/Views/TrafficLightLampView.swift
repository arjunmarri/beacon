import SwiftUI

struct TrafficLightLampView: View {
    let active: TrafficLightColor
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                lampDot(color: .red, lit: active == .red)
                lampDot(color: .orange, lit: active == .amber)
                lampDot(color: .green, lit: active == .green)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color(red: 0.043, green: 0.051, blue: 0.063))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
            .fill(lit ? color : Color.white.opacity(0.12))
            .frame(width: 8, height: 8)
            .shadow(color: lit ? color.opacity(0.75) : .clear, radius: 4)
    }

    private var labelColor: Color {
        switch active {
        case .green: return Color(red: 0.20, green: 0.83, blue: 0.60)
        case .amber: return Color(red: 0.98, green: 0.75, blue: 0.14)
        case .red: return Color(red: 0.98, green: 0.44, blue: 0.52)
        }
    }
}
