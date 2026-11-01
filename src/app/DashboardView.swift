import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if model.needsScreenPermission { PermissionCard() }
                if let name = model.receivingFrom { ReceivingCard(name: name) }
                MacsCard()
                if model.link == .streaming { LiveCard() }
                DisplayCard()
                ThisMacCard()
                ActivityCard()
                footer
            }
            .padding(20)
        }
        .frame(width: 540)
        .frame(minHeight: 420, idealHeight: 720)
        .background(ThemeBackground().ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 12) {
            HeaderMark()
            VStack(alignment: .leading, spacing: 1) {
                Text("Annex").font(Theme.font(.appTitle)).foregroundStyle(Theme.ink)
                Text("Use your other Mac as a second display").font(Theme.font(.body)).foregroundStyle(Theme.inkMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack {
            if let s = model.setupSummary { Text(s) }
            Spacer()
            Link("Open source on GitHub", destination: URL(string: "https://github.com/kvksatish/annex")!)
            Text("v\(model.version)").font(Theme.number(12))
        }
        .font(Theme.font(.caption))
        .foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, 4)
    }
}

private struct PermissionCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Card {
            Label("One more step", systemImage: "hand.raised.fill").font(Theme.font(.cardTitle)).foregroundStyle(Theme.signal)
            Text("To send your screen, macOS needs you to turn on **Annex** under Screen & System Audio Recording. Then relaunch Annex.")
                .font(Theme.font(.body)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Settings") { model.openScreenRecordingSettings() }.themePrimaryButton()
                Button("Relaunch Annex") { model.relaunch() }.themeSecondaryButton()
            }
        }
    }
}

private struct ReceivingCard: View {
    @EnvironmentObject var model: AppModel
    var name: String

    var body: some View {
        Card {
            HStack {
                Image(systemName: "rectangle.inset.filled").font(.title2).foregroundStyle(Theme.success)
                VStack(alignment: .leading) {
                    Text("This screen is showing \(name)").font(Theme.font(.cardTitle)).foregroundStyle(Theme.ink)
                    Text("Press Esc on this Mac to get your screen back.").font(Theme.font(.body)).foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                LinkBadge(cable: model.receivingCable)
            }
        }
    }
}

private struct MacsCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Card(title: "Your other Macs") {
            if model.peers.isEmpty {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for your other Mac…").font(Theme.font(.cardTitle)).foregroundStyle(Theme.ink)
                    Text("Open Annex on it too. For the sharpest, smoothest picture connect the two Macs with a Thunderbolt or USB-C cable — or just keep them on the same Wi-Fi.")
                        .font(Theme.font(.label)).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
            } else {
                ForEach(model.peers) { peer in
                    PeerRow(peer: peer)
                    if let warning = model.batteryDrainWarning(for: peer) { PowerWarning(text: warning, peer: peer) }
                }
            }
        }
    }
}

private struct PeerRow: View {
    @EnvironmentObject var model: AppModel
    var peer: Peer

    private var isTarget: Bool { model.targetID == peer.id }

    private var status: String? {
        guard isTarget else {
            if case .declined(let why) = model.link, model.targetID == nil { return why }
            return nil
        }
        switch model.link {
        case .idle: return nil
        case .connecting: return "Connecting…"
        case .awaitingApproval: return "Click Allow on \(peer.name)"
        case .streaming: return "In use as your display"
        case .retrying(let why): return "\(why) — reconnecting…"
        case .declined(let why): return why
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: peer.icon).font(.system(size: 26)).frame(width: 40).foregroundStyle(Theme.inkMuted)
            VStack(alignment: .leading, spacing: 4) {
                Text(peer.name).font(Theme.font(.cardTitle)).foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    LinkBadge(cable: peer.isCable)
                    if let status { Text(status).font(Theme.font(.caption)).foregroundStyle(Theme.inkMuted) }
                }
            }
            Spacer()
            if isTarget, model.link != .streaming, model.link != .idle { ProgressView().controlSize(.small) }
            if isTarget {
                Button("Stop") { model.toggle(peer) }.themeSecondaryButton()
            } else {
                Button("Use as Display") { model.toggle(peer) }.themePrimaryButton()
            }
        }
    }
}

private struct PowerWarning: View {
    @EnvironmentObject var model: AppModel
    var text: String
    var peer: Peer

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "battery.25percent").foregroundStyle(Theme.signal).font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(Theme.font(.label)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if model.wifiOnly {
                    Text("Video is going over Wi-Fi now. Unplug the cable to stop the charging, or plug a charger into either Mac.")
                        .font(Theme.font(.caption)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Plug a charger into either Mac, or send the video over Wi-Fi and unplug the cable.")
                        .font(Theme.font(.caption)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                    if peer.networkAddress != nil {
                        Button("Use Wi-Fi Instead") { model.useWiFiInstead() }.themeSmallButton()
                    } else {
                        Text("Wi-Fi isn't available: \(peer.name) isn't on the same Wi-Fi network.")
                            .font(Theme.font(.caption)).foregroundStyle(Theme.signal)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .themeNotice()
    }
}

private struct LiveCard: View {
    @EnvironmentObject var model: AppModel

    private var latency: String {
        let ms = model.stats.latencyMs
        if ms <= 0 { return "–" }
        return ms < 1 ? "<1" : String(format: ms < 10 ? "%.1f" : "%.0f", ms)
    }

    var body: some View {
        Card(title: "Live") {
            HStack {
                StatTile(value: "\(Int(model.stats.fps))", unit: "fps", label: "Smoothness")
                StatTile(value: String(format: "%.1f", model.stats.mbps), unit: "Mbps", label: "Speed")
                StatTile(value: latency, unit: "ms", label: "Latency")
                VStack(alignment: .leading, spacing: 6) {
                    LinkBadge(cable: model.stats.cable)
                    Text("Connection").font(Theme.font(.caption)).foregroundStyle(Theme.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Sparkline(values: model.speedHistory).frame(height: 40)
            HStack(spacing: 4) {
                Text(verbatim: "\(model.stats.width) × \(model.stats.height)").font(Theme.number(12))
                Text("on \(model.targetPeer?.name ?? "the other Mac") · frames only send when something changes")
                    .font(Theme.font(.caption))
            }
            .foregroundStyle(Theme.inkMuted)
        }
    }
}

private struct DisplayCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Card(title: "Display") {
            Row(label: "Size") {
                ThemeSegmented(options: SizeChoice.allCases.map { ($0, $0.title) }, selection: $model.sizeChoice)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Arrangement").font(Theme.font(.label)).foregroundStyle(Theme.ink)
                ArrangementView().frame(height: 210)
                Text("Drag the display to match where your other Mac sits on your desk.")
                    .font(Theme.font(.caption)).foregroundStyle(Theme.inkMuted)
            }
            Row(label: "Connection") {
                ThemeSegmented(options: [(false, "Automatic (cable first)"), (true, "Wi-Fi only")], selection: $model.wifiOnly)
            }
        }
    }

    private struct Row<Control: View>: View {
        var label: String
        @ViewBuilder var control: Control
        var body: some View {
            HStack(spacing: 12) {
                Text(label).font(Theme.font(.label)).foregroundStyle(Theme.ink).frame(width: 80, alignment: .leading)
                control
            }
        }
    }
}

private struct ThisMacCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Card(title: "This Mac") {
            Group {
                Toggle("Let my other Macs use this screen", isOn: $model.allowIncoming)
                Toggle("Reconnect automatically", isOn: $model.autoConnect)
                Toggle("Open Annex at login", isOn: Binding(get: { model.openAtLogin }, set: { model.openAtLogin = $0 }))
            }
            .font(Theme.font(.body))
            .foregroundStyle(Theme.ink)
            .themeToggle()
        }
    }
}

private struct ActivityCard: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var log = AppModel.shared.log
    @State private var expanded = false

    var body: some View {
        Card {
            DisclosureGroup(isExpanded: $expanded) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(log.lines) { line in
                                Text("\(LogStore.time(line.time))  \(line.text)")
                                    .font(Theme.font(.mono))
                                    .foregroundStyle(line.isProblem ? Theme.danger : Theme.inkMuted)
                                    .textSelection(.enabled)
                                    .id(line.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 160)
                    .onChange(of: log.lines.count) { proxy.scrollTo(log.lines.last?.id) }
                }
                HStack {
                    Button("Copy Log") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(log.text(), forType: .string)
                    }
                    .themeSmallButton()
                    Button("Show Log File") { NSWorkspace.shared.activateFileViewerSelecting([log.fileURL]) }.themeSmallButton()
                    Spacer()
                    Button("Report a Problem…") { model.reportProblem() }.themeSmallButton()
                }
                .padding(.top, 6)
            } label: {
                HStack {
                    Eyebrow(text: "Activity")
                    if log.problemCount > 0 {
                        ThemeBadge(text: "\(log.problemCount) issue\(log.problemCount == 1 ? "" : "s")",
                                   icon: "exclamationmark.circle", tone: Theme.danger)
                    }
                }
            }
        }
    }
}
