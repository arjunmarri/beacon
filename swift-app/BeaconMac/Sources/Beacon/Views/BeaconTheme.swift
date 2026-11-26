import SwiftUI

/// Centralized Liquid Glass adaptive palette for BeaconMac supporting real-time Dark and White (Light)
/// themes with luminous optical depth, specular edge refraction, and crisp Blue typographic anchors.
struct BeaconPalette {
    let colorScheme: ColorScheme

    var isLight: Bool { colorScheme == .light }

    // MARK: - Ambient Canvas & Translucent Glass Surfaces

    var canvas: Color {
        isLight
            ? Color(red: 0.824, green: 0.875, blue: 0.941)
            : Color(red: 0.012, green: 0.020, blue: 0.039)
    }

    var topBar: Color {
        isLight
            ? Color.white.opacity(0.24)
            : Color(red: 0.055, green: 0.068, blue: 0.095).opacity(0.28)
    }

    var sidebarFill: Color {
        isLight
            ? Color.white.opacity(0.22)
            : Color(red: 0.050, green: 0.062, blue: 0.088).opacity(0.26)
    }

    var menuMaterial: Material {
        .ultraThinMaterial
    }

    var menuItemHover: Color {
        isLight
            ? Color.white.opacity(0.46)
            : Color.white.opacity(0.095)
    }

    var menuItemSelected: Color {
        isLight
            ? Color.white.opacity(0.72)
            : Color(red: 0.25, green: 0.59, blue: 1.0).opacity(0.22)
    }

    var glassMaterial: Material {
        .ultraThinMaterial
    }

    var controlMaterial: Material {
        .ultraThinMaterial
    }

    var card: Color {
        isLight
            ? Color.white.opacity(0.54)
            : Color(red: 0.086, green: 0.125, blue: 0.204).opacity(0.50)
    }

    var row: Color {
        isLight
            ? Color.white.opacity(0.48)
            : Color.white.opacity(0.065)
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

    var accentInk: Color {
        isLight ? Color.white : Color(red: 0.032, green: 0.045, blue: 0.072)
    }

    var accentGradient: LinearGradient {
        if isLight {
            return LinearGradient(
                colors: [
                    Color(red: 0.23, green: 0.51, blue: 0.98),
                    Color(red: 0.11, green: 0.31, blue: 0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.43, green: 0.83, blue: 1.0),
                    Color(red: 0.16, green: 0.66, blue: 0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    var accentHoverGradient: LinearGradient {
        if isLight {
            return LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.39, blue: 0.92),
                    Color(red: 0.12, green: 0.25, blue: 0.69)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.56, green: 0.88, blue: 1.0),
                    Color(red: 0.22, green: 0.74, blue: 0.97)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Ambient Liquid Glass Backdrop Canvas

/// Darkened same-hue backdrop with slow blackhole gravitational infall space motion and
/// pointer-reactive translucent undersea glass stingrays gliding behind Liquid Glass panels.
struct BeaconAmbientCanvas: View {
    var interactive: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isLight = colorScheme == .light
        ZStack {
            LinearGradient(
                colors: isLight
                    ? [
                        Color(red: 0.867, green: 0.906, blue: 0.965),
                        Color(red: 0.812, green: 0.867, blue: 0.941),
                        Color(red: 0.749, green: 0.812, blue: 0.906)
                    ]
                    : [
                        Color(red: 0.024, green: 0.039, blue: 0.078),
                        Color(red: 0.012, green: 0.024, blue: 0.047),
                        Color(red: 0.008, green: 0.012, blue: 0.031)
                    ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { geo in
                ZStack {
                    RadialGradient(
                        colors: [
                            isLight
                                ? Color(red: 0.22, green: 0.74, blue: 0.97).opacity(0.20)
                                : Color(red: 0.22, green: 0.74, blue: 0.97).opacity(0.16),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 20,
                        endRadius: max(geo.size.width, geo.size.height) * 0.72
                    )

                    RadialGradient(
                        colors: [
                            isLight
                                ? Color(red: 0.39, green: 0.40, blue: 0.95).opacity(0.18)
                                : Color(red: 0.39, green: 0.40, blue: 0.95).opacity(0.15),
                            Color.clear
                        ],
                        center: .topTrailing,
                        startRadius: 20,
                        endRadius: max(geo.size.width, geo.size.height) * 0.68
                    )

                    RadialGradient(
                        colors: [
                            isLight
                                ? Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.14)
                                : Color(red: 0.06, green: 0.73, blue: 0.51).opacity(0.10),
                            Color.clear
                        ],
                        center: .bottom,
                        startRadius: 10,
                        endRadius: max(geo.size.width, geo.size.height) * 0.65
                    )
                }
            }

            if interactive {
                BeaconUnderseaBackdropView()
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
            .foregroundStyle(palette.accentInk)
            .padding(.horizontal, 13)
            .padding(.vertical, 6.5)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(palette.accentGradient)
                    // Smooth left-to-right background fill on hover (no border shift)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(palette.accentHoverGradient)
                        .scaleEffect(x: isHovered ? 1.0 : 0.001, y: 1.0, anchor: .leading)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.24), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            }
            .overlay {
                // Fixed non-shifting border
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(isLight ? 0.55 : 0.62), Color.white.opacity(0.08)],
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
            .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.30), value: isHovered)
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
            .foregroundStyle(isHovered ? palette.accentInk : (isLight ? Color(red: 0.08, green: 0.13, blue: 0.22) : Color.white.opacity(0.92)))
            .padding(.horizontal, 11.5)
            .padding(.vertical, 6)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        .fill(palette.controlMaterial)
                    RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        .fill(isLight ? Color.white.opacity(0.56) : Color.white.opacity(0.075))
                    // Smooth left-to-right accent color fill on hover (no border change)
                    RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        .fill(palette.accentGradient)
                        .scaleEffect(x: isHovered ? 1.0 : 0.001, y: 1.0, anchor: .leading)
                }
            }
            .overlay {
                // Fixed non-shifting border
                RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))
            .shadow(
                color: palette.sectionAccentBar.opacity(isEnabled && isHovered ? 0.24 : 0),
                radius: isHovered ? 8 : 0,
                x: 0,
                y: isHovered ? 3 : 0
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.84 : 1.0) : 0.42)
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.80), value: configuration.isPressed)
            .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.30), value: isHovered)
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
            .foregroundStyle(isHovered ? Color.white : palette.errorText)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        .fill(Color.red.opacity(palette.isLight ? 0.08 : 0.12))
                    // Smooth left-to-right crimson fill on hover (no border change)
                    RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.92, green: 0.24, blue: 0.29), Color(red: 0.78, green: 0.14, blue: 0.20)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .scaleEffect(x: isHovered ? 1.0 : 0.001, y: 1.0, anchor: .leading)
                }
            }
            .overlay {
                // Fixed non-shifting border
                RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.28), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.84 : 1.0) : 0.42)
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.80), value: configuration.isPressed)
            .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.28), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - BeaconMac Brand Mark (Matches Website Icon & macOS AppIcon)

struct BeaconBrandMarkView: View {
    var size: CGFloat = 32
    var cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.29, green: 0.61, blue: 1.00),
                            Color(red: 0.23, green: 0.51, blue: 0.96),
                            Color(red: 0.11, green: 0.31, blue: 0.85),
                            Color(red: 0.08, green: 0.22, blue: 0.68)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.49, green: 0.83, blue: 0.99).opacity(0.34), Color.clear],
                                center: UnitPoint(x: 0.26, y: 0.16),
                                startRadius: 1,
                                endRadius: size * 0.85
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.62), Color.white.opacity(0.16)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color(red: 0.15, green: 0.39, blue: 0.92).opacity(0.34), radius: size * 0.24, y: size * 0.09)

            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
                let unit = min(canvasSize.width, canvasSize.height) / 24.0
                let strokeStyle = StrokeStyle(lineWidth: 2.3 * unit, lineCap: .round, lineJoin: .round)

                // Central beacon emitter dot
                let dotR = 2.35 * unit
                let dotRect = CGRect(x: center.x - dotR, y: center.y - dotR, width: dotR * 2, height: dotR * 2)
                context.fill(Path(ellipseIn: dotRect), with: .color(.white))

                // Symmetric inner & outer broadcast arcs (matching website SVG)
                for radiusUnits in [6.0, 10.0] {
                    let r = radiusUnits * unit
                    var rightArc = Path()
                    rightArc.addArc(
                        center: center,
                        radius: r,
                        startAngle: .degrees(-45),
                        endAngle: .degrees(45),
                        clockwise: false
                    )
                    context.stroke(rightArc, with: .color(.white), style: strokeStyle)

                    var leftArc = Path()
                    leftArc.addArc(
                        center: center,
                        radius: r,
                        startAngle: .degrees(135),
                        endAngle: .degrees(225),
                        clockwise: false
                    )
                    context.stroke(leftArc, with: .color(.white), style: strokeStyle)
                }
            }
            .padding(size * 0.14)
        }
        .frame(width: size, height: size)
    }
}

