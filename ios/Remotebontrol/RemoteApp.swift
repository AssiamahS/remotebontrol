import SwiftUI

@main
struct RemoteApp: App {
    @StateObject private var store = TVStore.shared
    @StateObject private var remote = SamsungRemote()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(remote)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: TVStore
    @EnvironmentObject var remote: SamsungRemote
    @State private var page: Int = RootView.initialPage()
    @State private var showSettings = false

    static func initialPage() -> Int {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count {
            return ["remote": 0, "keypad": 1, "apps": 2][args[i + 1]] ?? 0
        }
        return 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            if store.selected == nil {
                NoTVView(showSettings: $showSettings)
            } else {
                TabView(selection: $page) {
                    RemoteView().tag(0)
                    KeypadView().tag(1)
                    AppsView().tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear { remote.use(store.selected) }
        .onChange(of: store.selectedID) { _, _ in remote.use(store.selected) }
        .onAppear { if store.tvs.isEmpty && !Persistence.isDemo { showSettings = true } }
    }

    private var header: some View {
        HStack {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.title3).frame(width: 52, height: 52)
                    .background(Theme.key, in: RoundedRectangle(cornerRadius: 14))
            }
            Spacer()
            VStack(spacing: 2) {
                Text("Remote control").font(.title3.weight(.bold))
                Text(subtitle).font(.footnote).foregroundStyle(statusColor).lineLimit(1)
            }
            Spacer()
            Button { remote.power() } label: {
                Image(systemName: "power").font(.title2.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 60, height: 60).background(Theme.power, in: Circle())
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .foregroundStyle(.white)
    }

    private var subtitle: String {
        guard let tv = store.selected else { return "No TV yet" }
        switch remote.state {
        case .waitingForAllow: return "Press Allow on the TV"
        case .denied: return "\(tv.displayName) · denied, tap to retry"
        case .unreachable: return "\(tv.displayName) · off or unreachable"
        case .connecting, .idle: return "\(tv.displayName) · connecting"
        case .connected: return tv.displayName
        }
    }

    private var statusColor: Color {
        switch remote.state {
        case .connected: return Theme.muted
        case .waitingForAllow: return Theme.accent
        case .denied, .unreachable: return Theme.power
        default: return Theme.muted
        }
    }
}

struct NoTVView: View {
    @Binding var showSettings: Bool
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "tv").font(.system(size: 56)).foregroundStyle(Theme.muted)
            Text("Find your Samsung TV").font(.headline)
            Text("Same Wi-Fi as the TV, then scan. The TV asks once to Allow this phone.")
                .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Scan Wi-Fi") { showSettings = true }.buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
