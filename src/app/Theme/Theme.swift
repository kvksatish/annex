import SwiftUI

// The standard Annex look, built from system styles.
//
// Every colour, font and surface in the app goes through this file, so a build can swap in another look
// by pointing scripts/build.sh at a different theme folder (ANNEX_THEME_DIR). A replacement theme must
// define the same names: Theme, ThemeBackground, ThemeGroundShapes, ThemeSegmented, ThemeBadge, HeaderMark
// and the View extensions below.

enum Theme {
    static let name = "Standard"

    static func font(_ role: FontRole) -> Font {
        switch role {
        case .appTitle: return .title2.weight(.bold)
        case .cardTitle: return .headline
        case .eyebrow: return .caption.weight(.semibold)
        case .body: return .body
        case .label: return .callout
        case .caption: return .caption
        case .metric: return .system(.title2, design: .rounded).weight(.semibold).monospacedDigit()
        case .unit: return .caption
        case .mono: return .system(.caption, design: .monospaced)
        }
    }

    /// Numbers that should read as figures (counts, times, sizes).
    static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded).monospacedDigit() }

    static let ink = Color.primary
    static let inkMuted = Color.secondary
    static let line = Color.primary.opacity(0.07)
    static let signal = Color.orange
    static let success = Color.green
    static let danger = Color.red
    static let chartStory = Color.accentColor
    static let wifi = Color.blue

    static var mainScreenFill: AnyShapeStyle {
        AnyShapeStyle(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.30)], startPoint: .top, endPoint: .bottom))
    }
    static var extendedScreenFill: AnyShapeStyle {
        AnyShapeStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

struct ThemeBackground: View {
    var body: some View { Color(nsColor: .windowBackgroundColor) }
}

/// Decoration that scrolls behind the content (none in the standard look).
struct ThemeGroundShapes: View {
    var body: some View { Color.clear }
}

struct HeaderMark: View {
    var body: some View {
        Image(systemName: "rectangle.on.rectangle")
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

/// A one-of-several choice (segmented control).
struct ThemeSegmented<Value: Hashable>: View {
    var options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// A small status label with a coloured mark.
struct ThemeBadge: View {
    var text: String
    var icon: String
    var tone: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(tone.opacity(0.15)))
            .foregroundStyle(tone)
    }
}

extension View {
    func themeCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
    }

    /// An inline notice that needs attention but isn't an error.
    func themeNotice() -> some View {
        padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
    }

    func themePrimaryButton() -> some View { buttonStyle(.borderedProminent).controlSize(.large) }
    func themeSecondaryButton() -> some View { buttonStyle(.bordered).controlSize(.large) }
    func themeSmallButton() -> some View { buttonStyle(.bordered).controlSize(.small) }
    func themeToggle() -> some View { toggleStyle(.switch) }
}
