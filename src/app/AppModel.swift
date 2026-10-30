import AppKit
import ServiceManagement

enum SizeChoice: Int, CaseIterable, Identifiable {
    case larger, standard, more
    var id: Int { rawValue }
    var title: String { ["Larger Text", "Default", "More Space"][rawValue] }
    var scale: Double { [0.86, 1.0, 1.17][rawValue] }
}

enum LinkState: Equatable {
    case idle, connecting, awaitingApproval, streaming
    case retrying(String)
    case declined(String)
}

struct StreamStats {
    var fps = 0.0, mbps = 0.0, latencyMs = 0.0
    var cable = false
    var width = 0, height = 0
}

/// Everything the dashboard and menu show, plus the connect/reconnect logic.
final class AppModel: ObservableObject {
    static let shared = AppModel()
    static let issuesURL = "https://github.com/kvksatish/annex/issues/new"

    let log = LogStore()
    @Published var peers: [Peer] = []
    @Published var targetID: String?
    @Published var link: LinkState = .idle
    @Published var stats = StreamStats()
    @Published var speedHistory: [Double] = []
    @Published var receivingFrom: String?
    @Published var receivingCable = false
    @Published var receiveFPS = 0.0
    @Published var needsScreenPermission = false
    @Published var myPowerWatts = Int(ANXExternalPowerWatts())

    @Published var sizeChoice: SizeChoice { didSet { defaults.set(sizeChoice.rawValue, forKey: "size"); restartIfStreaming() } }
    @Published var placeLeft: Bool { didSet { defaults.set(placeLeft, forKey: "placeLeft"); restartIfStreaming() } }
    @Published var autoConnect: Bool { didSet { defaults.set(autoConnect, forKey: "autoConnect") } }
    /// Send video over Wi-Fi even when a cable is plugged in (e.g. so the cable can be unplugged to stop
    /// one Mac's battery charging the other).
    @Published var wifiOnly: Bool {
        didSet {
            defaults.set(wifiOnly, forKey: "wifiOnly")
            log.add(wifiOnly ? "Connection set to Wi-Fi only" : "Connection set to Automatic (cable preferred)")
            restartIfStreaming()
        }
    }
    @Published var allowIncoming: Bool {
        didSet { defaults.set(allowIncoming, forKey: "allowIncoming"); receiver.enabled = allowIncoming; discovery.setAdvertising(allowIncoming) }
    }

    let myID: String
    let myName = Host.current().localizedName ?? "Mac"
    let myModel = AppModel.hardwareModel()
    private let defaults = UserDefaults.standard
    private let receiver = ANXReceiver()
    private let discovery: Discovery
    private var sender: ANXSender?
    private var userStopped = false

    private init() {
        if defaults.string(forKey: "deviceID") == nil { defaults.set(UUID().uuidString, forKey: "deviceID") }
        myID = defaults.string(forKey: "deviceID")!
        discovery = Discovery(myID: myID)
        sizeChoice = SizeChoice(rawValue: defaults.integer(forKey: "size")) ?? .standard
        if defaults.object(forKey: "size") == nil { sizeChoice = .standard }
        placeLeft = defaults.bool(forKey: "placeLeft")
        autoConnect = defaults.object(forKey: "autoConnect") as? Bool ?? true
        wifiOnly = defaults.bool(forKey: "wifiOnly")
        allowIncoming = defaults.object(forKey: "allowIncoming") as? Bool ?? true
        if defaults.object(forKey: "firstLaunch") == nil { defaults.set(Date(), forKey: "firstLaunch") }
    }

    // MARK: Startup

    func start() {
        ANXSetLogSink { [weak self] line in self?.log.add(line) }
        log.add("Annex \(version) on \(myName) (\(myModel)), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

        receiver.enabled = allowIncoming
        receiver.shouldAccept = { [weak self] id, name in self?.askToAccept(id: id, name: name) ?? false }
        receiver.onActiveChange = { [weak self] active, name, cable in
            guard let self else { return }
            receivingFrom = active ? name : nil
            receivingCable = cable
            if active { recordFirstValue() }
        }
        receiver.startListening()

        discovery.onChange = { [weak self] peers in self?.peersChanged(peers) }
        discovery.start(name: myName, model: myModel)
        discovery.setAdvertising(allowIncoming)

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    // MARK: Sending

    func toggle(_ peer: Peer) {
        targetID == peer.id ? stopExtending() : extend(peer)
    }

    func extend(_ peer: Peer) {
        click()
        sender?.stop(); sender = nil
        userStopped = false
        targetID = peer.id
        defaults.set(peer.id, forKey: "lastTarget")
        log.add("Extending to \(peer.name)")
        connect()
    }

    func stopExtending() {
        click()
        userStopped = true
        targetID = nil
        sender?.stop(); sender = nil
        link = .idle
        stats = StreamStats()
        log.add("Stopped extending")
    }

    private func connect() {
        guard let id = targetID, sender == nil else { return }
        guard CGPreflightScreenCaptureAccess() else {
            // Ask macOS once per launch; auto-reconnect waits quietly until the user has granted it.
            if !needsScreenPermission {
                needsScreenPermission = true
                CGRequestScreenCaptureAccess()
                log.add("Annex needs Screen Recording permission to send this screen")
            }
            targetID = nil; link = .idle
            return
        }
        guard let peer = peers.first(where: { $0.id == id }), let address = address(for: peer) else {
            link = .retrying(wifiOnly ? "Waiting for the other Mac on Wi-Fi…" : "Looking for the other Mac…")
            scheduleRetry()
            return
        }
        let s = ANXSender(address: address, senderID: UUID(uuidString: myID)!, senderName: myName)
        s.sizeScale = sizeChoice.scale
        s.placeLeft = placeLeft
        s.onStateChange = { [weak self, weak s] state, detail in
            guard let self, let s, s === self.sender else { return }
            self.handle(state, detail: detail, peer: peer)
        }
        sender = s
        s.start()
    }

    private func address(for peer: Peer) -> String? {
        wifiOnly ? peer.networkAddress : peer.bestAddress
    }

    private func handle(_ state: ANXSenderState, detail: String, peer: Peer) {
        switch state {
        case .connecting: link = .connecting
        case .awaitingApproval: link = .awaitingApproval
        case .streaming:
            link = .streaming
            recordFirstValue()
        case .declined:
            sender = nil; targetID = nil
            link = .declined(detail)
            log.add(detail)
        default:   // ended
            sender = nil
            stats = StreamStats()
            if targetID != nil { link = .retrying(detail); scheduleRetry() } else { link = .idle }
        }
    }

    private func scheduleRetry() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, targetID != nil, sender == nil else { return }
            discovery.refresh()
            connect()
        }
    }

    private func restartIfStreaming() {
        guard sender != nil else { return }
        sender?.stop(); sender = nil
        connect()
    }

    private func peersChanged(_ new: [Peer]) {
        peers = new
        // Cable plugged in mid-stream: hop from Wi-Fi to the cable.
        if link == .streaming, !wifiOnly, !stats.cable, let id = targetID, new.first(where: { $0.id == id })?.isCable == true {
            log.add("Cable detected — switching to it")
            restartIfStreaming()
        }
        // Reconnect to the last Mac automatically.
        if targetID == nil, autoConnect, !userStopped, !needsScreenPermission, let last = defaults.string(forKey: "lastTarget"),
           new.contains(where: { $0.id == last }) {
            targetID = last
            connect()
        }
    }

    private func tick() {
        if let s = sender, link == .streaming {
            stats = StreamStats(fps: s.fps, mbps: s.mbps, latencyMs: s.latencyMs, cable: s.viaCable,
                                width: Int(s.displayWidth), height: Int(s.displayHeight))
            speedHistory.append(s.mbps)
            if speedHistory.count > 60 { speedHistory.removeFirst() }
        }
        receiveFPS = receiver.fps
        let watts = Int(ANXExternalPowerWatts())
        if watts != myPowerWatts { myPowerWatts = watts }
        if needsScreenPermission, CGPreflightScreenCaptureAccess() { needsScreenPermission = false }
    }

    // MARK: Power over the cable

    /// A cable between two MacBooks also carries power. With no real charger on either Mac (a cable from
    /// the other Mac shows up as ≤15 W), one battery is being drained to charge the other.
    func batteryDrainWarning(for peer: Peer) -> String? {
        guard peer.isCable, ANXIsLaptop(), peer.isLaptop,
              myPowerWatts <= 15, peer.powerWatts <= 15 else { return nil }
        return myPowerWatts > 0
            ? "\(peer.name) is charging this Mac through the cable, so its battery is draining."
            : "This Mac is charging \(peer.name) through the cable, so this battery is draining."
    }

    func useWiFiInstead() {
        click()
        wifiOnly = true
    }

    // MARK: Receiving

    private func askToAccept(id: String, name: String) -> Bool {
        var allowed = defaults.stringArray(forKey: "allowedSenders") ?? []
        if allowed.contains(id) { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Let “\(name)” use this screen?"
        alert.informativeText = "This Mac will become an extra display for \(name). Press Esc on this Mac any time to get your screen back."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        let ok = alert.runModal() == .alertFirstButtonReturn
        click()
        if ok { allowed.append(id); defaults.set(allowed, forKey: "allowedSenders") }
        log.add(ok ? "Allowed \(name) to use this screen" : "Declined \(name)")
        return ok
    }

    func handBackScreen() { receiver.pause(for: 30) }

    // MARK: Settings & helpers

    var openAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { log.add("Couldn't change Open at Login: \(error.localizedDescription)") }
            objectWillChange.send()
        }
    }

    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

    var targetPeer: Peer? { peers.first { $0.id == targetID } }

    var menuIcon: String {
        if receivingFrom != nil { return "rectangle.inset.filled" }
        return link == .streaming ? "display.2" : "display"
    }

    /// Steps-to-value: counts clicks until the first working display, and how long it took.
    func click() {
        if defaults.object(forKey: "firstValueSeconds") == nil { defaults.set(defaults.integer(forKey: "clicks") + 1, forKey: "clicks") }
    }

    private func recordFirstValue() {
        guard defaults.object(forKey: "firstValueSeconds") == nil,
              let first = defaults.object(forKey: "firstLaunch") as? Date else { return }
        let secs = Int(Date().timeIntervalSince(first))
        defaults.set(secs, forKey: "firstValueSeconds")
        log.add("Setup complete: first display in \(secs) s after \(defaults.integer(forKey: "clicks")) click(s) in Annex")
        objectWillChange.send()
    }

    var setupSummary: String? {
        guard let secs = defaults.object(forKey: "firstValueSeconds") as? Int else { return nil }
        let time = secs < 120 ? "\(secs) s" : "\(secs / 60) min"
        let clicks = defaults.integer(forKey: "clicks")
        return "Set up in \(time) · \(clicks) click\(clicks == 1 ? "" : "s")"
    }

    func openScreenRecordingSettings() {
        click()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; open \"\(Bundle.main.bundlePath)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    func reportProblem() {
        let body = """
        **What happened?**


        **What did you expect?**


        ---
        Annex \(version) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(myModel) · \
        link: \(link == .streaming ? (stats.cable ? "cable" : "Wi-Fi") : "\(link)")

        <details><summary>Activity log</summary>

        ```
        \(log.text(last: 40))
        ```
        </details>
        """
        var c = URLComponents(string: Self.issuesURL)!
        c.queryItems = [URLQueryItem(name: "title", value: "Problem: "),
                        URLQueryItem(name: "body", value: String(body.prefix(6000)))]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }
}
