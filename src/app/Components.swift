import SwiftUI

/// Text roles every theme maps to a font.
enum FontRole { case appTitle, cardTitle, eyebrow, body, label, caption, metric, unit, mono }

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Eyebrow(text: title) }
            content
        }
        .themeCard()
    }
}

struct Eyebrow: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(Theme.font(.eyebrow)).tracking(0.6).foregroundStyle(Theme.inkMuted)
    }
}

struct LinkBadge: View {
    var cable: Bool
    var body: some View {
        ThemeBadge(text: cable ? "Cable" : "Wi-Fi", icon: cable ? "cable.connector" : "wifi",
                   tone: cable ? Theme.success : Theme.wifi)
    }
}

struct StatTile: View {
    var value: String
    var unit: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(Theme.font(.metric)).foregroundStyle(Theme.ink)
                Text(unit).font(Theme.font(.unit)).foregroundStyle(Theme.inkMuted)
            }
            Text(label).font(Theme.font(.caption)).foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Sparkline: View {
    var values: [Double]

    var body: some View {
        GeometryReader { geo in
            let top = max(values.max() ?? 1, 1)
            let step = geo.size.width / CGFloat(max(values.count - 1, 1))
            let points = values.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * step, y: geo.size.height * (1 - CGFloat(v / top)))
            }
            ZStack {
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    points.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
                }
                .fill(LinearGradient(colors: [Theme.chartStory.opacity(0.32), .clear], startPoint: .top, endPoint: .bottom))
                Path { p in p.addLines(points) }
                    .stroke(Theme.chartStory, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
    }
}
