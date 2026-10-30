import Foundation

/// Another Mac running Annex, as found on the network or over a cable.
struct Peer: Identifiable, Equatable {
    let id: String
    var name: String
    var model: String
    var isLaptop: Bool
    var cableAddress: String?
    var networkAddress: String?
    /// Watts of external power the other Mac is receiving; 0 = on battery.
    var powerWatts: Int

    var bestAddress: String? { cableAddress ?? networkAddress }
    var isCable: Bool { cableAddress != nil }
    var icon: String { isLaptop ? "laptopcomputer" : "desktopcomputer" }
}

/// Advertises this Mac over Bonjour and finds other Macs running Annex.
/// Bonjour runs on every interface, so a Thunderbolt/USB-C cable link and Wi-Fi are both covered.
final class Discovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var onChange: (([Peer]) -> Void)?

    private let myID: String
    private var model = ""
    private var advertisedTXT: [String: String] = [:]
    private let browser = NetServiceBrowser()
    private var advert: NetService?
    private var services: [String: NetService] = [:]
    private var peers: [String: Peer] = [:]   // keyed by service name

    init(myID: String) { self.myID = myID }

    func start(name: String, model: String) {
        self.model = model
        advert = NetService(domain: "local.", type: ANXServiceType, name: name, port: Int32(ANXPort))
        updateTXT()
        browser.delegate = self
        browser.searchForServices(ofType: ANXServiceType, inDomain: "local.")
        // Addresses change when a cable is plugged in or Wi-Fi switches; keep them fresh.
        Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            self?.updateTXT()
            self?.refresh()
        }
    }

    /// Bonjour often reports only the Wi-Fi address, so each Mac also announces its cable addresses itself,
    /// plus its power source so either side can warn when one battery is charging the other.
    private func updateTXT() {
        var txt = ["id": myID, "model": model, "laptop": ANXIsLaptop() ? "1" : "0",
                   "power": String(ANXExternalPowerWatts())]
        let cable = ANXCableAddresses().joined(separator: ",")
        if !cable.isEmpty { txt["cable"] = cable }   // never publish empty values
        guard txt != advertisedTXT else { return }
        advertisedTXT = txt
        advert?.setTXTRecord(NetService.data(fromTXTRecord: txt.mapValues { Data($0.utf8) }))
    }

    func setAdvertising(_ on: Bool) {
        if on { advert?.publish() } else { advert?.stop() }
    }

    func refresh() {
        services.values.forEach { $0.resolve(withTimeout: 5) }
    }

    // MARK: NetServiceBrowserDelegate

    func netServiceBrowser(_ b: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services[service.name] = service
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ b: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeValue(forKey: service.name)
        if peers.removeValue(forKey: service.name) != nil { publish() }
    }

    // MARK: NetServiceDelegate

    func netServiceDidResolveAddress(_ service: NetService) {
        let txt = Self.parseTXT(service.txtRecordData() ?? Data())
        guard let id = txt["id"], id != myID else { return }
        let string = { (key: String) in txt[key] ?? "" }
        let ips = (service.addresses ?? []).compactMap(Self.ipv4)
        let announcedCable = string("cable").split(separator: ",").map(String.init)
        let cable = (announcedCable + ips).first { ANXAddressIsCable($0) }
        let network = ips.first { !ANXAddressIsCable($0) && !$0.hasPrefix("169.254.") }
        let peer = Peer(id: id, name: service.name, model: string("model"), isLaptop: string("laptop") == "1",
                        cableAddress: cable, networkAddress: network, powerWatts: Int(string("power")) ?? 0)
        if peers[service.name] != peer {
            peers[service.name] = peer
            publish()
        }
    }

    private func publish() {
        onChange?(peers.values.sorted { $0.name < $1.name })
    }

    /// Parses a DNS-SD TXT record (length-prefixed "key=value" strings). Apple's
    /// NetService.dictionary(fromTXTRecord:) crashes on keys without a value, so we don't use it.
    static func parseTXT(_ data: Data) -> [String: String] {
        var out: [String: String] = [:]
        let bytes = [UInt8](data)
        var i = 0
        while i < bytes.count {
            let len = Int(bytes[i]); i += 1
            guard len > 0, i + len <= bytes.count else { break }
            let entry = String(decoding: bytes[i..<i + len], as: UTF8.self)
            i += len
            let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = parts.first, !key.isEmpty else { continue }
            out[key.lowercased()] = parts.count > 1 ? String(parts[1]) : ""
        }
        return out
    }

    private static func ipv4(_ data: Data) -> String? {
        data.withUnsafeBytes { raw -> String? in
            guard raw.count >= MemoryLayout<sockaddr_in>.size else { return nil }
            var sin = raw.loadUnaligned(as: sockaddr_in.self)
            guard sin.sin_family == sa_family_t(AF_INET) else { return nil }
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &sin.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN))
            return String(cString: buf)
        }
    }
}
