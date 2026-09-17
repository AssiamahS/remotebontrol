import Foundation
import Network

/// Finds Samsung TVs by asking every address on the phone's /24 for /api/v2/ on port 8001.
/// No multicast entitlement needed, and it catches TVs that ignore ping (the Q80T does).
enum TVScanner {
    struct Found: Identifiable {
        var id: String { tv.id }
        var tv: TV
        var powerState: String?
    }

    /// The phone's Wi-Fi IPv4 address (en0), if any.
    static func localIPv4() -> String? {
        var addr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addr) == 0, let first = addr else { return nil }
        defer { freeifaddrs(addr) }
        var result: String?
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name == "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result = String(cString: host)
            }
        }
        return result
    }

    /// Probe one host. Returns nil unless it speaks the Samsung API.
    static func probe(_ ip: String, timeout: TimeInterval = 1.5) async -> Found? {
        guard let url = URL(string: "http://\(ip):8001/api/v2/") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dev = json["device"] as? [String: Any],
              let name = dev["name"] as? String else { return nil }
        let mac = (dev["wifiMac"] as? String ?? "").uppercased()
        let id = (dev["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (mac.isEmpty ? ip : mac)
        let tv = TV(id: id, name: name, ip: ip, mac: mac, model: dev["modelName"] as? String ?? "", token: "")
        return Found(tv: tv, powerState: dev["PowerState"] as? String)
    }

    /// Sweep the local /24. Calls `onFound` as TVs turn up so the list fills live.
    static func sweep(onFound: @escaping @MainActor (Found) -> Void) async {
        guard let ip = localIPv4() else { return }
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return }
        let prefix = parts[0...2].joined(separator: ".")
        await withTaskGroup(of: Found?.self) { group in
            var inflight = 0
            for host in 1...254 {
                group.addTask { await probe("\(prefix).\(host)") }
                inflight += 1
                if inflight >= 32 {
                    if let f = await group.next(), let found = f { await onFound(found) }
                    inflight -= 1
                }
            }
            for await f in group { if let found = f { await onFound(found) } }
        }
    }
}
