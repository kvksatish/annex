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
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 1) {
                Text("Annex").font(.title2.weight(.bold))
                Text("Use your other Mac as a second display").foregroundStyle(.secondary)
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
            Text("v\(model.version)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

private struct PermissionCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Card {
            Label("One more step", systemImage: "hand.raised.fill").font(.headline).foregroundStyle(.orange)
            Text("To send your screen, macOS needs you to turn on **Annex** under Screen & System Audio Recording. Then relaunch Annex.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Settings") { model.openScreenRecordingSettings() }.buttonStyle(.borderedProminent)
                Button("Relaunch Annex") { model.relaunch() }
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
                Image(systemName: "rectangle.inset.filled").font(.title2).foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text("This screen is showing \(name)").font(.headline)
                    Text("Press Esc on this Mac to get your screen back.").foregroundStyle(.secondary)
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
                    Text("Looking for your other Mac…").font(.headline)
                    Text("Open Annex on it too. For the sharpest, smoothest picture connect the two Macs with a Thunderbolt or USB-C cable — or just keep them on the same Wi-Fi.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
            } else {
                ForEach(model.peers) { PeerRow(peer: $0) }
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
            Image(systemName: peer.icon).font(.system(size: 26)).frame(width: 40).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(peer.name).font(.headline)
                HStack(spacing: 6) {
                    LinkBadge(cable: peer.isCable)
                    if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Spacer()
            if isTarget, model.link != .streaming, model.link != .idle { ProgressView().controlSize(.small) }
            Button(isTarget ? "Stop" : "Use as Display") { model.toggle(peer) }
                .buttonStyle(.borderedProminent)
                .tint(isTarget ? .red : .accentColor)
                .controlSize(.large)
        }
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
                StatTile(value: latency,
                         unit: "ms", label: "Latency")
                StatTile(value: model.stats.cable ? "Cable" : "Wi-Fi", unit: "", label: "Connection")
            }
            Sparkline(values: model.speedHistory).frame(height: 40)
            Text(verbatim: "\(model.stats.width) × \(model.stats.height) on \(model.targetPeer?.name ?? "the other Mac") · frames only send when something changes")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct DisplayCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Card(title: "Display") {
            Picker("Size", selection: $model.sizeChoice) {
                ForEach(SizeChoice.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Position", selection: $model.placeLeft) {
                Text("Left of this Mac").tag(true)
                Text("Right of this Mac").tag(false)
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct ThisMacCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Card(title: "This Mac") {
            Toggle("Let my other Macs use this screen", isOn: $model.allowIncoming)
            Toggle("Reconnect automatically", isOn: $model.autoConnect)
            Toggle("Open Annex at login", isOn: Binding(get: { model.openAtLogin }, set: { model.openAtLogin = $0 }))
        }
        .toggleStyle(.switch)
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
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(line.isProblem ? Color.red : Color.secondary)
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
                    Button("Show Log File") { NSWorkspace.shared.activateFileViewerSelecting([log.fileURL]) }
                    Spacer()
                    Button("Report a Problem…") { model.reportProblem() }
                }
                .padding(.top, 6)
            } label: {
                HStack {
                    Text("ACTIVITY").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if log.problemCount > 0 {
                        Text("\(log.problemCount) issue\(log.problemCount == 1 ? "" : "s")")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.red.opacity(0.15)))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}
