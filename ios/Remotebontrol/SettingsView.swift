import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: TVStore
    @EnvironmentObject var remote: SamsungRemote
    @Environment(\.dismiss) private var dismiss
    @State private var found: [TVScanner.Found] = []
    @State private var scanning = false
    @State private var manualIP = ""
    @State private var manualError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Your TVs") {
                    if store.tvs.isEmpty { Text("None yet. Scan below.").foregroundStyle(Theme.muted) }
                    ForEach(store.tvs) { tv in
                        Button {
                            store.selectedID = tv.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tv.displayName).font(.headline)
                                    Text("\(tv.model) · \(tv.ip)" + (tv.token.isEmpty ? " · not paired yet" : " · paired")).font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                if store.selectedID == tv.id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                        }
                        .foregroundStyle(.white)
                        .swipeActions {
                            Button(role: .destructive) { store.remove(tv) } label: { Label("Forget", systemImage: "trash") }
                            if !tv.token.isEmpty {
                                Button { store.setToken("", for: tv.id); remote.use(nil); remote.use(store.selected) } label: { Label("Re-pair", systemImage: "arrow.clockwise") }
                            }
                        }
                    }
                }
                Section {
                    Button { Task { await scan() } } label: {
                        HStack {
                            Label(scanning ? "Scanning…" : "Scan Wi-Fi for Samsung TVs", systemImage: "dot.radiowaves.left.and.right")
                            if scanning { Spacer(); ProgressView() }
                        }
                    }.disabled(scanning)
                    ForEach(found.filter { f in !store.tvs.contains { $0.id == f.tv.id } }) { f in
                        Button { store.upsert(f.tv); store.selectedID = f.tv.id } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.tv.displayName).font(.headline)
                                    Text("\(f.tv.model) · \(f.tv.ip)" + (f.powerState == "on" ? " · on" : "")).font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                            }
                        }.foregroundStyle(.white)
                    }
                } header: { Text("Find a TV") } footer: {
                    Text("The TV and this phone must be on the same Wi-Fi. TVs that are fully off won't show up; turn one on once to add it.")
                }
                Section("Add by IP") {
                    HStack {
                        TextField("10.0.0.22", text: $manualIP).keyboardType(.decimalPad)
                        Button("Add") { Task { await addManual() } }.disabled(manualIP.isEmpty)
                    }
                    if let manualError { Text(manualError).font(.caption).foregroundStyle(Theme.power) }
                }
                Section("How pairing works") {
                    Text("The first time you press a key, the TV shows “remotebontrol wants to connect”. Pick Allow with any remote that still works, or the TV's own button. After that it remembers this phone. If you ever see “denied”, use Re-pair and watch the TV.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                Section {
                    Link(destination: URL(string: "https://assiamahs.github.io/remotebontrol/privacy.html")!) { Label("Privacy Policy", systemImage: "hand.raised") }
                    Link(destination: URL(string: "https://github.com/AssiamahS/remotebontrol/issues")!) { Label("Support", systemImage: "questionmark.bubble") }
                } footer: {
                    Text("Free. No subscription, no ads, no account. Everything stays on your Wi-Fi.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("TVs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { if store.tvs.isEmpty && !Persistence.isDemo { await scan() } }
        }
    }

    private func scan() async {
        scanning = true; found = []
        await TVScanner.sweep { f in
            if !found.contains(where: { $0.id == f.id }) { found.append(f) }
        }
        scanning = false
    }

    private func addManual() async {
        manualError = nil
        if let f = await TVScanner.probe(manualIP.trimmingCharacters(in: .whitespaces), timeout: 3) {
            store.upsert(f.tv); store.selectedID = f.tv.id; manualIP = ""
        } else {
            manualError = "No Samsung TV answered at that address."
        }
    }
}
