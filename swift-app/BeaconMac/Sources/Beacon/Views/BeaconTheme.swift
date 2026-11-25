import SwiftUI

/// Centralized Liquid Glass adaptive palette for BeaconMac supporting real-time Dark and White (Light)
/// themes with luminous optical depth, specular edge refraction, and crisp Blue typographic anchors.
struct BeaconPalette {
    let colorScheme: ColorScheme

    var isLight: Bool { colorScheme == .light }

    // MARK: - Ambient Canvas & Translucent Glass Surfaces

    var canvas: Color {
        isLight
            ? Color(red: 0.945, green: 0.962, blue: 0.990)
            : Color(red: 0.036, green: 0.044, blue: 0.062)
    }

    var topBar: Color {
        isLight
            ? Color.white.opacity(0.24)
            : Color(red: 0.055, green: 0.068, blue: 0.095).opacity(0.28)
    }

    var sidebarFill: Color {
        isLight
            ? Color.white.opacity(0.20)
            : Color(red: 0.050, green: 0.062, blue: 0.088).opacity(0.24)
    }

    var menuMaterial: Material {
        .ultraThinMaterial
    }

    var menuItemHover: Color {
        isLight
            ? Color.white.opacity(0.42)
            : Color.white.opacity(0.085)
    }

    var menuItemSelected: Color {
        isLight
            ? Color.white.opacity(0.68)
            : Color(red: 0.25, green: 0.59, blue: 1.0).opacity(0.22)
    }

    var glassMaterial: Material {
        isLight ? .regularMaterial : .ultraThinMaterial
    }

    var controlMaterial: Material {
        isLight ? .regularMaterial : .thinMaterial
    }

    var card: Color {
        isLight
            ? Color.white.opacity(0.72)
            : Color(red: 0.078, green: 0.095, blue: 0.132).opacity(0.62)
    }

    var row: Color {
        isLight
            ? Color.white.opacity(0.58)
            : Color(red: 0.058, green: 0.072, blue: 0.102).opacity(0.58)
    }

    var input: Color {
        isLight
            ? Color.white.opacity(0.84)
            : Color(red: 0.038, green: 0.048, blue: 0.070).opacity(0.78)
    }

    var console: Color {
        isLight
            ? Color(red: 0.942, green: 0.958, blue: 0.986).opacity(0.82)
            : Color(red: 0.026, green: 0.033, blue: 0.049).opacity(0.84)
    }

    var sheetCanvas: Color {
        isLight
            ? Color(red: 0.952, green: 0.968, blue: 0.994)
            : Color(red: 0.044, green: 0.054, blue: 0.076)
    }

    // MARK: - Optical Rim Borders & Glass Highlights

    var border: Color {
        isLight
            ? Color(red: 0.785, green: 0.835, blue: 0.915).opacity(0.72)
            : Color.white.opacity(0.115)
    }

    var inputBorder: Color {
        isLight
            ? Color(red: 0.745, green: 0.802, blue: 0.892).opacity(0.85)
            : Color.white.opacity(0.15)
    }

    var subtleBorder: Color {
        isLight
            ? Color(red: 0.825, green: 0.868, blue: 0.935).opacity(0.65)
            : Color.white.opacity(0.08)
    }

    var specularTop: Color {
        isLight
            ? Color.white.opacity(0.95)
            : Color.white.opacity(0.28)
    }

    var specularMid: Color {
        isLight
            ? Color(red: 0.75, green: 0.84, blue: 0.98).opacity(0.45)
            : Color(red: 0.45, green: 0.72, blue: 1.0).opacity(0.12)
    }

    var specularBottom: Color {
        isLight
            ? Color(red: 0.72, green: 0.79, blue: 0.90).opacity(0.42)
            : Color.white.opacity(0.05)
    }

    var specularBorderGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: specularTop, location: 0.0),
                .init(color: specularMid, location: 0.38),
                .init(color: specularBottom, location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var glassTopSheen: LinearGradient {
        LinearGradient(
            colors: [
                isLight ? Color.white.opacity(0.55) : Color.white.opacity(0.085),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .center
        )
    }

    var hoverFill: Color {
        isLight
            ? Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.075)
            : Color.white.opacity(0.065)
    }

    var chipFill: Color {
        isLight
            ? Color(red: 0.915, green: 0.942, blue: 0.985).opacity(0.85)
            : Color.white.opacity(0.065)
    }

    var activeChipFill: Color {
        isLight
            ? Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.13)
            : Color(red: 0.25, green: 0.59, blue: 1.0).opacity(0.22)
    }

    // MARK: - Typography & Semantic Accents

    var sectionHeader: Color {
        isLight
            ? Color(red: 0.095, green: 0.315, blue: 0.825)
            : Color(red: 0.46, green: 0.75, blue: 1.0)
    }

    var sectionAccentBar: Color {
        isLight
            ? Color(red: 0.145, green: 0.388, blue: 0.922)
            : Color(red: 0.32, green: 0.67, blue: 1.0)
    }

    var primaryText: Color {
        isLight ? Color(red: 0.070, green: 0.098, blue: 0.155) : Color.white
    }

    var bodyText: Color {
        isLight ? Color(red: 0.125, green: 0.165, blue: 0.240) : Color.white.opacity(0.90)
    }

    var secondaryText: Color {
        isLight ? Color(red: 0.345, green: 0.408, blue: 0.510) : Color.white.opacity(0.62)
    }

    var accentLink: Color {
        isLight ? Color(red: 0.075, green: 0.380, blue: 0.820) : Color(red: 0.38, green: 0.83, blue: 0.99)
    }

    var successText: Color {
        isLight ? Color(red: 0.045, green: 0.520, blue: 0.310) : Color(red: 0.24, green: 0.88, blue: 0.62)
    }

    var warningText: Color {
        isLight ? Color(red: 0.760, green: 0.420, blue: 0.020) : Color(red: 1.0, green: 0.72, blue: 0.28)
    }

    var errorText: Color {
        isLight ? Color(red: 0.790, green: 0.140, blue: 0.190) : Color(red: 1.0, green: 0.44, blue: 0.48)
    }

    var cardShadow: Color {
        isLight ? Color(red: 0.09, green: 0.16, blue: 0.32).opacity(0.075) : Color.black.opacity(0.38)
    }

    var accentGradient: LinearGradient {
        if isLight {
            return LinearGradient(
                colors: [
                    Color(red: 0.19, green: 0.46, blue: 0.98),
                    Color(red: 0.11, green: 0.36, blue: 0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.79, blue: 1.0),
                    Color(red: 0.20, green: 0.60, blue: 0.97)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Ambient Liquid Glass Backdrop Canvas

/// Soft luminous backdrop rendered behind translucent macOS materials so Liquid Glass surfaces
/// naturally refract subtle sapphire, cyan, and indigo depth in both Dark and Light themes.
struct BeaconAmbientCanvas: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLight = colorScheme == .light
        ZStack {
            BeaconPalette(colorScheme: colorScheme).canvas

            GeometryReader { geo in
                ZStack {
                    RadialGradient(
                        colors: [
                            isLight
                                ? Color(red: 0.24, green: 0.56, blue: 1.0).opacity(0.22)
                                : Color(red: 0.18, green: 0.56, blue: 0.98).opacity(0.20),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 20,
                        endRadius: max(geo.size.width, geo.size.height) * 0.72
                    )

                    RadialGradient(
                        colors: [
                            isLight
                                ? Color(red: 0.46, green: 0.42, blue: 0.96).opacity(0.15)
                                : Color(red: 0.36, green: 0.34, blue: 0.92).opacity(0.17),
                            Color.clear
                        ],
                        center: .topTrailing,
                        startRadius: 20,
                        endRadius: max(geo.size.width, geo.size.height) * 0.68
                    )

                    RadialGradient(
                        colors: [
                            isLight
                                ? Color(red: 0.14, green: 0.76, blue: 0.70).opacity(0.12)
                                : Color(red: 0.10, green: 0.68, blue: 0.64).opacity(0.10),
                            Color.clear
                        ],
                        center: .bottom,
                        startRadius: 10,
                        endRadius: max(geo.size.width, geo.size.height) * 0.65
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Liquid Glass Surface Modifiers

struct BeaconGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 20
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = BeaconPalette(colorScheme: colorScheme)
        content
            .padding(padding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(palette.glassMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(palette.card)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(palette.glassTopSheen)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(palette.specularBorderGradient, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: palette.cardShadow, radius: palette.isLight ? 14 : 20, x: 0, y: palette.isLight ? 5 : 10)
    }
}

struct BeaconGlassRowModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var padding: CGFloat = 14
    var accentBorder: Color? = nil
    var isHovered: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = BeaconPalette(colorScheme: colorScheme)
        content
            .padding(padding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(palette.row)
                    if isHovered {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(palette.hoverFill)
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        accentBorder ?? (isHovered ? palette.sectionAccentBar.opacity(0.40) : palette.border),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(.easeOut(duration: 0.16), value: isHovered)
    }
}

struct BeaconGlassWellModifier: ViewModifier {
    var cornerRadius: CGFloat = 10
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = BeaconPalette(colorScheme: colorScheme)
        content
            .background(palette.console)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(palette.subtleBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct BeaconGlassInputModifier: ViewModifier {
    var cornerRadius: CGFloat = 8
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 7
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = BeaconPalette(colorScheme: colorScheme)
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(palette.input)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(palette.inputBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func beaconGlassCard(cornerRadius: CGFloat = 16, padding: CGFloat = 20) -> some View {
        modifier(BeaconGlassCardModifier(cornerRadius: cornerRadius, padding: padding))
    }

    func beaconGlassRow(
        cornerRadius: CGFloat = 12,
        padding: CGFloat = 14,
        accentBorder: Color? = nil,
        isHovered: Bool = false
    ) -> some View {
        modifier(BeaconGlassRowModifier(
            cornerRadius: cornerRadius,
            padding: padding,
            accentBorder: accentBorder,
            isHovered: isHovered
        ))
    }

    func beaconGlassWell(cornerRadius: CGFloat = 10) -> some View {
        modifier(BeaconGlassWellModifier(cornerRadius: cornerRadius))
    }

    func beaconGlassInput(cornerRadius: CGFloat = 8, horizontalPadding: CGFloat = 10, verticalPadding: CGFloat = 7) -> some View {
        modifier(BeaconGlassInputModifier(
            cornerRadius: cornerRadius,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        ))
    }
}

// MARK: - Refined Section Header (Zero Left Accent Bar Clutter)

struct BeaconSectionHeaderText: View {
    let title: String
    var fontSize: CGFloat = 15.5
    var systemImage: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = BeaconPalette(colorScheme: colorScheme)
        HStack(spacing: 8) {
            if let systemImage {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.activeChipFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(palette.sectionAccentBar.opacity(0.28), lineWidth: 1)
                        )
                    Image(systemName: systemImage)
                        .font(.system(size: max(11, fontSize - 3.5), weight: .semibold))
                        .foregroundStyle(palette.sectionHeader)
                }
                .frame(width: 24, height: 24)
            }

            Text(title)
                .font(.system(size: fontSize, weight: .bold, design: .default))
                .tracking(-0.2)
                .foregroundStyle(palette.sectionHeader)
        }
    }
}

// MARK: - Tactile Liquid Glass Button Styles

struct BeaconPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BeaconPrimaryButtonBody(configuration: configuration)
    }
}

private struct BeaconPrimaryButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let palette = BeaconPalette(colorScheme: colorScheme)
        let isLight = palette.isLight

        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(isLight ? Color.white : Color(red: 0.032, green: 0.045, blue: 0.072))
            .padding(.horizontal, 13)
            .padding(.vertical, 6.5)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(palette.accentGradient)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isHovered ? 0.30 : 0.20), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(isLight ? 0.55 : 0.65), Color.white.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(
                color: palette.sectionAccentBar.opacity(isEnabled ? (isHovered ? 0.36 : 0.22) : 0),
                radius: isHovered ? 10 : 6,
                x: 0,
                y: isHovered ? 3 : 2
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1.0) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

struct BeaconSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BeaconSecondaryButtonBody(configuration: configuration)
    }
}

private struct BeaconSecondaryButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let palette = BeaconPalette(colorScheme: colorScheme)
        let isLight = palette.isLight

        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(isLight ? Color(red: 0.10, green: 0.15, blue: 0.23) : Color.white.opacity(0.92))
            .padding(.horizontal, 11.5)
            .padding(.vertical, 6)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        .fill(palette.controlMaterial)
                    RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        .fill(
                            isLight
                                ? Color.white.opacity(isHovered ? 0.92 : 0.68)
                                : Color.white.opacity(isHovered ? 0.13 : 0.065)
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                    .strokeBorder(
                        isHovered
                            ? (isLight ? palette.sectionAccentBar.opacity(0.45) : Color.white.opacity(0.28))
                            : palette.border,
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1.0) : 0.42)
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.80), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

struct BeaconDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BeaconDangerButtonBody(configuration: configuration)
    }
}

private struct BeaconDangerButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let palette = BeaconPalette(colorScheme: colorScheme)
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(palette.errorText)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Color.red.opacity(palette.isLight ? (isHovered ? 0.14 : 0.07) : (isHovered ? 0.20 : 0.11))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                    .strokeBorder(Color.red.opacity(isHovered ? 0.45 : 0.25), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1.0) : 0.42)
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.80), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
