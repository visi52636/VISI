import SwiftUI

/// Single place for the app's look. To apply a studio identity:
///  - set `accent` (or the AccentColor asset) to the brand colour,
///  - add the logo to Assets.xcassets as an image named "BrandLogo" (white/light version for the dark UI),
///  - set `studioName`.
enum Brand {
    static let studioName = "XPLANSTUDIO"
    static let appName = "VIS X"

    /// Highlight colour: selected states, pins, underlines. Comes from the AccentColor asset.
    static let accent = Color.accentColor

    static let background = Color.black
    static let surface = Color(white: 0.07)
    static let surfaceRaised = Color(white: 0.12)
    static let hairline = Color.white.opacity(0.14)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)

    static var logo: UIImage? { UIImage(named: "BrandLogo") }

    static let cornerRadius: CGFloat = 6
}

extension Font {
    /// Large thin display type used for project names.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .light) }
}

/// Small uppercase, letter-spaced label ("PROJECTS", "COMO · RESIDENCE").
struct Eyebrow: View {
    let text: String
    var color: Color = Brand.textSecondary
    var size: CGFloat = 11

    init(_ text: String, color: Color = Brand.textSecondary, size: CGFloat = 11) {
        self.text = text
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .medium))
            .tracking(size * 0.22)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// The studio mark: the logo artwork if provided ("BrandLogo" asset), otherwise a typeset
/// XPLANSTUDIO wordmark — hairline capitals, an A without crossbar, and the final O in the brand red.
struct BrandMark: View {
    var height: CGFloat = 22

    var body: some View {
        if let logo = Brand.logo {
            Image(uiImage: logo)
                .resizable()
                .scaledToFit()
                .frame(height: height)
                .accessibilityLabel(Brand.studioName)
        } else {
            (Text("XPL\u{039B}NSTUDI").foregroundColor(Brand.textPrimary)
             + Text("O").foregroundColor(Brand.accent))
                .font(.system(size: height, weight: .ultraLight))
                .tracking(height * 0.06)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(Brand.studioName)
        }
    }
}

/// Solid white capsule button with dark uppercase text.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(.black)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .background(Color.white.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}

/// Outlined capsule button.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(Brand.textPrimary.opacity(configuration.isPressed ? 0.6 : 1))
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .overlay(Capsule().strokeBorder(Brand.hairline.opacity(2.5), lineWidth: 1))
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// Bottom-to-top darkening so text stays readable on top of images.
struct ImageScrim: View {
    var strength: Double = 0.85

    var body: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(strength * 0.45), .black.opacity(strength)],
            startPoint: .center,
            endPoint: .bottom
        )
    }
}
