import SwiftUI

/// Drag-to-arrange, like System Settings → Displays: this Mac's screen in the middle and the extended
/// display around it. Drop it anywhere; it snaps to the nearest edge and moves live.
struct ArrangementView: View {
    @EnvironmentObject var model: AppModel
    @State private var translation: CGSize?

    var body: some View {
        GeometryReader { geo in
            let main = model.mainDisplaySize, ext = model.extendedDisplaySize
            // Fixed scale with room for the display on any side, so nothing jumps while dragging.
            let scale = min(geo.size.width / (main.width + 2 * ext.width),
                            geo.size.height / (main.height + 2 * ext.height)) * 0.96
            let origin = CGPoint(x: (geo.size.width - main.width * scale) / 2,
                                 y: (geo.size.height - main.height * scale) / 2)
            let placed = model.effectivePlacement
            let dragged = translation.map {
                CGPoint(x: placed.x + $0.width / scale, y: placed.y + $0.height / scale)
            }
            let shown = dragged ?? placed
            let snapped = dragged.map { AppModel.snap($0, main: main, extended: ext) }

            ZStack(alignment: .topLeading) {
                screen(title: "This Mac", size: main, scale: scale, isMain: true)
                    .offset(x: origin.x, y: origin.y)

                if let snapped {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Theme.ink, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: ext.width * scale, height: ext.height * scale)
                        .offset(x: origin.x + snapped.x * scale, y: origin.y + snapped.y * scale)
                }

                screen(title: extendedName, size: ext, scale: scale, isMain: false)
                    .opacity(translation == nil ? 1 : 0.85)
                    .offset(x: origin.x + shown.x * scale, y: origin.y + shown.y * scale)
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { translation = $0.translation }
                            .onEnded { value in
                                let drop = CGPoint(x: placed.x + value.translation.width / scale,
                                                   y: placed.y + value.translation.height / scale)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    model.setPlacement(AppModel.snap(drop, main: main, extended: ext))
                                    translation = nil
                                }
                                model.click()
                            }
                    )
                    .onHover { inside in inside ? NSCursor.openHand.push() : NSCursor.pop() }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private var extendedName: String {
        model.targetPeer?.name ?? model.peers.first?.name ?? "Other Mac"
    }

    private func screen(title: String, size: CGSize, scale: CGFloat, isMain: Bool) -> some View {
        let w = size.width * scale, h = size.height * scale
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isMain ? Theme.mainScreenFill : Theme.extendedScreenFill)
            if isMain {
                Rectangle().fill(Color.white.opacity(0.85)).frame(height: max(2, h * 0.05))   // menu bar
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
            }
            Text(title)
                .font(Theme.font(.caption))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
                .frame(maxHeight: .infinity)
        }
        .frame(width: w, height: h)
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.25)))
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}
