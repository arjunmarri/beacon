import SwiftUI

/// Centralized adaptive palette for BeaconMac supporting real-time Dark and White (Light) themes
/// with high-contrast Blue section headers for effortless visual scanning.
struct BeaconPalette {
    let colorScheme: ColorScheme

    var isLight: Bool { colorScheme == .light }

    // Surfaces
    var canvas: Color {
        isLight ? Color(red: 0.961, green: 0.971, blue: 0.988) : Color(red: 0.043, green: 0.051, blue: 0.063)
    }

    var topBar: Color {
        isLight ? Color.white : Color(red: 0.043, green: 0.051, blue: 0.063)
    }

    var card: Color {
        isLight ? Color.white : Color(red: 0.075, green: 0.086, blue: 0.106)
    }

    var row: Color {
        isLight ? Color(red: 0.965, green: 0.975, blue: 0.992) : Color(red: 0.048, green: 0.056, blue: 0.070)
    }

    var input: Color {
        isLight ? Color.white : Color(red: 0.043, green: 0.051, blue: 0.063)
    }

    var console: Color {
        isLight ? Color(red: 0.957, green: 0.967, blue: 0.984) : Color(red: 0.035, green: 0.041, blue: 0.052)
    }

    var sheetCanvas: Color {
        isLight ? Color(red: 0.965, green: 0.973, blue: 0.988) : Color(red: 0.055, green: 0.067, blue: 0.086)
    }

    // Borders & Dividers
    var border: Color {
        isLight ? Color(red: 0.835, green: 0.867, blue: 0.918) : Color.white.opacity(0.09)
    }

    var inputBorder: Color {
        isLight ? Color(red: 0.775, green: 0.818, blue: 0.885) : Color.white.opacity(0.13)
    }

    var subtleBorder: Color {
        isLight ? Color(red: 0.875, green: 0.902, blue: 0.942) : Color.white.opacity(0.06)
    }

    var hoverFill: Color {
        isLight ? Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.06) : Color.white.opacity(0.05)
    }

    var chipFill: Color {
        isLight ? Color(red: 0.925, green: 0.945, blue: 0.978) : Color.white.opacity(0.05)
    }

    var activeChipFill: Color {
        isLight ? Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.14) : Color(red: 0.23, green: 0.56, blue: 0.98).opacity(0.22)
    }

    // Typography
    /// Distinct Blue section header color for fast visual anchoring in both Dark and White themes.
    var sectionHeader: Color {
        isLight ? Color(red: 0.114, green: 0.337, blue: 0.847) : Color(red: 0.376, green: 0.678, blue: 1.0)
    }

    var sectionAccentBar: Color {
        isLight ? Color(red: 0.145, green: 0.388, blue: 0.922) : Color(red: 0.29, green: 0.62, blue: 1.0)
    }

    var primaryText: Color {
        isLight ? Color(red: 0.075, green: 0.105, blue: 0.165) : Color.white
    }

    var bodyText: Color {
        isLight ? Color(red: 0.115, green: 0.155, blue: 0.225) : Color.white.opacity(0.90)
    }

    var secondaryText: Color {
        isLight ? Color(red: 0.345, green: 0.408, blue: 0.506) : Color.white.opacity(0.62)
    }

    var accentLink: Color {
        isLight ? Color(red: 0.086, green: 0.396, blue: 0.788) : Color.cyan
    }

    var successText: Color {
        isLight ? Color(red: 0.055, green: 0.51, blue: 0.30) : Color(red: 0.22, green: 0.84, blue: 0.58)
    }

    var warningText: Color {
        isLight ? Color(red: 0.74, green: 0.42, blue: 0.02) : Color.orange
    }

    var errorText: Color {
        isLight ? Color(red: 0.78, green: 0.14, blue: 0.18) : Color.red.opacity(0.92)
    }

    var cardShadow: Color {
        isLight ? Color.black.opacity(0.05) : Color.clear
    }
}

struct BeaconSectionHeaderText: View {
    let title: String
    var fontSize: CGFloat = 15.5
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = BeaconPalette(colorScheme: colorScheme)
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(palette.sectionAccentBar)
                .frame(width: 3.5, height: fontSize + 1)
            Text(title)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(palette.sectionHeader)
        }
    }
}

struct BeaconPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let isLight = colorScheme == .light
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isLight ? Color.white : Color(red: 0.043, green: 0.051, blue: 0.063))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                (isLight ? Color(red: 0.145, green: 0.388, blue: 0.922) : Color(red: 0.28, green: 0.69, blue: 0.99))
                    .opacity(configuration.isPressed ? 0.82 : 1.0)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct BeaconSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let isLight = colorScheme == .light
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isLight ? Color(red: 0.11, green: 0.16, blue: 0.24) : Color.white.opacity(0.92))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                isLight
                    ? Color(red: 0.935, green: 0.952, blue: 0.980).opacity(configuration.isPressed ? 0.72 : 1.0)
                    : Color.white.opacity(configuration.isPressed ? 0.14 : 0.08)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isLight ? Color(red: 0.79, green: 0.835, blue: 0.90) : Color.white.opacity(0.11))
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
