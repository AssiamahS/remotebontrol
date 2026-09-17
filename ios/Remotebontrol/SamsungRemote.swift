import Foundation
import UIKit

/// One WebSocket to the TV's remote-control channel. Reconnects on demand,
/// stores the pairing token the first time the TV says yes.
@MainActor
final class SamsungRemote: NSObject, ObservableObject {
    enum State: Equatable { case idle, connecting, waitingForAllow, connected, denied, unreachable }

    @Published private(set) var state: State = .idle
    @Published private(set) var tv: TV?

    private var session: URLSession!
    private var socket: URLSessionWebSocketTask?
    private var pending: [String] = []
    private let clientName = "remotebontrol"

    override init() {
        super.init()
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    func use(_ tv: TV?) {
        guard tv?.id != self.tv?.id || state == .idle else { return }
        disconnect()
        self.tv = tv
        if tv != nil { connect() }
    }

    func connect() {
        guard let tv, socket == nil else { return }
        if Persistence.isDemo { state = .connected; return }
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
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        state = .idle
    }

    /// Send a KEY_* code. Queues while the handshake is in flight.
    func key(_ code: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if Persistence.isDemo { return }
        if socket == nil { connect() }
        guard state == .connected, let socket else { pending.append(code); return }
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

    /// Power: if the TV answers on the network it's on (or in network standby) -> KEY_POWER toggles.
    /// If it doesn't answer, fire Wake-on-LAN at its MAC.
    func power() {
        guard let tv else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if Persistence.isDemo { return }
        Task {
            if let found = await TVScanner.probe(tv.ip, timeout: 1.2), found.powerState == "on" {
                key("KEY_POWER")
            } else {
                WakeOnLAN.send(mac: tv.mac, ip: tv.ip)
                key("KEY_POWER")
            }
        }
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
            queued.forEach { key($0) }
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
/// subnet broadcast; the unicast path is what works without the multicast entitlement.
enum WakeOnLAN {
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
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(9).bigEndian
            addr.sin_addr.s_addr = inet_addr(target)
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    _ = packet.withUnsafeBytes { sendto(sock, $0.baseAddress, packet.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                }
            }
        }
        close(sock)
    }
}
