import SwiftUI

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

struct LinkBadge: View {
    var cable: Bool

    var body: some View {
        Label(cable ? "Cable" : "Wi-Fi", systemImage: cable ? "cable.connector" : "wifi")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill((cable ? Color.green : Color.blue).opacity(0.15)))
            .foregroundStyle(cable ? Color.green : Color.blue)
    }
}

struct StatTile: View {
    var value: String
    var unit: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
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
                .fill(LinearGradient(colors: [.accentColor.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                Path { p in p.addLines(points) }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
    }
}
