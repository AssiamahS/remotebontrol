import Foundation
import UIKit

/// One WebSocket to the TV's remote-control channel. Reconnects on demand,
/// stores the pairing token the first time the TV says yes.
@MainActor
final class SamsungRemote: NSObject, ObservableObject {
    enum State: Equatable { case idle, connecting, waitingForAllow, connected, denied, unreachable, waking, wakeFailed }

    @Published private(set) var state: State = .idle
    @Published private(set) var tv: TV?

    private var session: URLSession!
    private var socket: URLSessionWebSocketTask?
    private var pending: [String] = []
    private var wakeTask: Task<Void, Never>?
    private let clientName = "remotebontrol"

    /// How long the power button keeps knocking before giving up.
    static let wakeBudget: TimeInterval = 25

    override init() {
        super.init()
        let cfg = URLSessionConfiguration.default
        // A TV that's off never answers the TLS handshake; don't sit in "connecting" for a minute.
        cfg.timeoutIntervalForRequest = 8
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    func use(_ tv: TV?) {
        guard tv?.id != self.tv?.id || state == .idle else { return }
        disconnect()
        self.tv = tv
        if tv != nil { connect() }
    }

    /// Drop whatever we had and try again (foreground return, tap on the status line).
    func reconnect() {
        // Leave a healthy or in-flight connection alone; only retry from a dead end.
        guard [.idle, .unreachable, .denied, .wakeFailed].contains(state) else { return }
        disconnect()
        connect()
    }

    func connect() {
        guard let tv, socket == nil else { return }
        if Persistence.isDemo { state = .connected; return }
        state = tv.token.isEmpty ? .waitingForAllow : .connecting
        Task {
            // Cheap plain-HTTP knock first: a TV that is off (or moved IP) fails here in ~1s
            // instead of hanging the WebSocket handshake.
            guard let live = await locate(tv) else {
                if state == .connecting || state == .waitingForAllow { state = .unreachable }
                return
            }
            guard socket == nil, self.tv?.id == tv.id, state != .waking else { return }
            open(live)
        }
    }

    private func open(_ tv: TV) {
        let name = Data(clientName.utf8).base64EncodedString()
        var urlString = "wss://\(tv.ip):8002/api/v2/channels/samsung.remote.control?name=\(name)"
        if !tv.token.isEmpty { urlString += "&token=\(tv.token)" }
        guard let url = URL(string: urlString) else { return }
        state = tv.token.isEmpty ? .waitingForAllow : .connecting
        let task = session.webSocketTask(with: url)
        socket = task
        task.resume()
        receive()
    }

    func disconnect() {
        wakeTask?.cancel(); wakeTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        pending = []
        state = .idle
    }

    /// Send a KEY_* code. Queues while the handshake is in flight.
    func key(_ code: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if Persistence.isDemo { return }
        if socket == nil { connect() }
        guard state == .connected, let socket else {
            if code != "KEY_POWER" { pending.append(code) }
            return
        }
        send(code, over: socket)
    }

    private func send(_ code: String, over socket: URLSessionWebSocketTask) {
        let msg: [String: Any] = ["method": "ms.remote.control",
                                  "params": ["Cmd": "Click", "DataOfCmd": code, "Option": "false", "TypeOfRemote": "SendRemoteKey"]]
        guard let data = try? JSONSerialization.data(withJSONObject: msg), let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { [weak self] err in
            if err != nil { Task { @MainActor in self?.dropSocket(to: .unreachable) } }
        }
    }

    /// Launch a Tizen app by id over plain HTTP; works even before pairing.
    func launchApp(_ appID: String) {
        guard let tv, let url = URL(string: "http://\(tv.ip):8001/api/v2/applications/\(appID)") else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 4
        URLSession.shared.dataTask(with: req).resume()
    }

    /// Power button.
    /// - TV answers on :8001 and says it's on  -> KEY_POWER (that's the off toggle).
    /// - TV answers but is in network standby   -> KEY_POWER wakes it (plus a magic packet for luck).
    /// - TV doesn't answer at all               -> hammer Wake-on-LAN and re-probe until it shows up,
    ///   then connect. Never queue KEY_POWER behind a wake: it would switch the TV straight back off.
    func power() {
        guard let tv else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if Persistence.isDemo { return }
        if state == .waking { return }
        if state == .connected, let socket {
            send("KEY_POWER", over: socket)
            return
        }
        wakeTask?.cancel()
        wakeTask = Task { await wake(tv) }
    }

    private func wake(_ stored: TV) async {
        if let found = await TVScanner.probe(stored.ip, timeout: 1.2) {
            if found.powerState == "on" {
                if socket == nil { open(stored) }
                pending.append("KEY_POWER")
                return
            }
            WakeOnLAN.send(macs: stored.allMACs, ip: stored.ip)
            if socket == nil { open(stored) }
            pending.append("KEY_POWER")
            return
        }

        dropSocket(to: .waking)
        let started = Date()
        let deadline = started.addingTimeInterval(Self.wakeBudget)
        var sweepDone = false
        var target = stored
        while Date() < deadline, !Task.isCancelled {
            WakeOnLAN.send(macs: target.allMACs, ip: target.ip)
            if let found = await TVScanner.probe(target.ip, timeout: 1.0) {
                // Awake. The WoL already turned it on; just attach.
                if found.powerState != "on" { WakeOnLAN.send(macs: target.allMACs, ip: target.ip) }
                if target.ip != stored.ip { TVStore.shared.updateIP(target.ip, for: stored.id) }
                tv = TVStore.shared.tvs.first { $0.id == stored.id } ?? target
                state = .idle
                open(tv ?? target)
                return
            }
            // DHCP may have handed the TV a new address; look for its MAC once, mid-wait.
            if !sweepDone, Date().timeIntervalSince(started) > 6 {
                sweepDone = true
                if let moved = await locate(stored, sweep: true), moved.ip != target.ip {
                    target = moved
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
        if !Task.isCancelled { state = .wakeFailed }
    }

    /// Find the TV: its last IP first, then (optionally) a sweep for the same id/MAC.
    private func locate(_ tv: TV, sweep: Bool = false) async -> TV? {
        if let f = await TVScanner.probe(tv.ip, timeout: 1.5) { return merged(f.tv, with: tv) }
        guard sweep else { return nil }
        var hit: TV?
        await TVScanner.sweep { f in
            if hit == nil, f.tv.id == tv.id || (!tv.mac.isEmpty && f.tv.mac == tv.mac) { hit = f.tv }
        }
        if let hit {
            TVStore.shared.updateIP(hit.ip, for: tv.id)
            return merged(hit, with: tv)
        }
        return nil
    }

    private func merged(_ fresh: TV, with stored: TV) -> TV {
        var t = fresh
        t.token = stored.token
        if t.mac.isEmpty { t.mac = stored.mac }
        return t
    }

    private func receive() {
        socket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure:
                    self.dropSocket(to: self.state == .waitingForAllow ? .denied : .unreachable)
                case .success(let message):
                    if case .string(let text) = message { self.handle(text) }
                    self.receive()
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String else { return }
        switch event {
        case "ms.channel.connect":
            state = .connected
            if let d = json["data"] as? [String: Any], let token = d["token"] as? String, !token.isEmpty, let tv {
                if token != tv.token {
                    self.tv?.token = token
                    TVStore.shared.setToken(token, for: tv.id)
                }
            }
            let queued = pending; pending = []
            if let socket { queued.forEach { send($0, over: socket) } }
        case "ms.channel.unauthorized":
            dropSocket(to: .denied)
        case "ms.channel.timeOut":
            dropSocket(to: .denied)
        default:
            break
        }
    }

    private func dropSocket(to newState: State) {
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        pending = []   // keys queued behind a dead handshake are stale
        state = newState
    }
}

/// Samsung TVs sign their WebSocket with a self-signed cert; trust it for the TV's own IP only.
extension SamsungRemote: URLSessionDelegate {
    nonisolated func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                                completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// Magic packet to wake a TV that's fully off. Sent unicast to the TV's last IP and to the
/// subnet broadcast, on both WoL ports; the unicast path is what works without the multicast entitlement.
/// Only lands if the TV's "Power On with Mobile" (network standby) is on — otherwise its Wi-Fi radio is asleep.
enum WakeOnLAN {
    /// Samsung sets drop the first few magic packets after a long sleep (people who ship
    /// WoL for these TVs send batches of ten), so every wake call is a burst, not one packet.
    static let burst = 10

    static func send(macs: [String], ip: String) {
        for _ in 0..<burst { for mac in macs { send(mac: mac, ip: ip) } }
    }

    static func send(mac: String, ip: String) {
        let hex = mac.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        guard hex.count == 12 else { return }
        var macBytes: [UInt8] = []
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return }
            macBytes.append(b); idx = next
        }
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet += macBytes }

        var targets = [ip]
        let parts = ip.split(separator: ".")
        if parts.count == 4 { targets.append(parts[0...2].joined(separator: ".") + ".255") }
        targets.append("255.255.255.255")

        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return }
        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        for target in targets {
            for port: UInt16 in [9, 7] {
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = port.bigEndian
                addr.sin_addr.s_addr = inet_addr(target)
                withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        _ = packet.withUnsafeBytes { sendto(sock, $0.baseAddress, packet.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                    }
                }
            }
        }
        close(sock)
    }
}
