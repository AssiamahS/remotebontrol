import Foundation
import SwiftUI

/// A Samsung Tizen TV on the local network. Token is the pairing secret the TV
/// hands back after you press Allow once; keep it and you never see the prompt again.
struct TV: Identifiable, Codable, Equatable {
    var id: String            // TV's own uuid from /api/v2/, or the MAC when unknown
    var name: String
    var ip: String
    var mac: String
    var model: String
    var token: String

    var displayName: String {
        name.replacingOccurrences(of: "[TV] ", with: "")
    }
}

/// Persisted list of TVs + which one is selected.
@MainActor
final class TVStore: ObservableObject {
    @Published var tvs: [TV] { didSet { save() } }
    @Published var selectedID: String? { didSet { UserDefaults.standard.set(selectedID, forKey: "selectedTV") } }

    static let shared = TVStore()

    private init() {
        if let data = UserDefaults.standard.data(forKey: "tvs"),
           let list = try? JSONDecoder().decode([TV].self, from: data) {
            tvs = list
        } else {
            tvs = []
        }
        selectedID = UserDefaults.standard.string(forKey: "selectedTV")
        if Persistence.isDemo {
            tvs = [TV(id: "demo", name: "[TV] Samsung Q80T (65)", ip: "10.0.0.22", mac: "5C:C1:D7:DB:AE:6C", model: "QN65Q80TAFXZA", token: "demo")]
            selectedID = "demo"
        }
    }

    var selected: TV? {
        tvs.first { $0.id == selectedID } ?? tvs.first
    }

    func upsert(_ tv: TV) {
        if let i = tvs.firstIndex(where: { $0.id == tv.id }) {
            var merged = tv
            if merged.token.isEmpty { merged.token = tvs[i].token }
            tvs[i] = merged
        } else {
            tvs.append(tv)
        }
        if selectedID == nil { selectedID = tv.id }
    }

    func setToken(_ token: String, for id: String) {
        guard let i = tvs.firstIndex(where: { $0.id == id }) else { return }
        tvs[i].token = token
    }

    func remove(_ tv: TV) {
        tvs.removeAll { $0.id == tv.id }
        if selectedID == tv.id { selectedID = tvs.first?.id }
    }

    private func save() {
        guard !Persistence.isDemo else { return }
        if let data = try? JSONEncoder().encode(tvs) {
            UserDefaults.standard.set(data, forKey: "tvs")
        }
    }
}

enum Persistence {
    static let isDemo = ProcessInfo.processInfo.environment["REMOTE_DEMO"] == "1"
        || CommandLine.arguments.contains("-demo")
}

enum Theme {
    static let bg = Color(red: 0.05, green: 0.06, blue: 0.08)
    static let key = Color(red: 0.13, green: 0.14, blue: 0.17)
    static let keyPressed = Color(red: 0.20, green: 0.22, blue: 0.26)
    static let nav = Color(red: 0.27, green: 0.30, blue: 0.36)
    static let border = Color.white.opacity(0.06)
    static let muted = Color(red: 0.55, green: 0.57, blue: 0.62)
    static let power = Color(red: 0.90, green: 0.25, blue: 0.22)
    static let accent = Color(red: 0.0, green: 0.78, blue: 0.75)
}
