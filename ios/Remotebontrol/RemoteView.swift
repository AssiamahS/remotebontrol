import SwiftUI

/// A remote key. Label is what you see, code is what the TV gets.
struct Key: Identifiable {
    let id = UUID()
    var label: String
    var code: String
    var symbol: String? = nil
    var style: KeyStyle = .normal
    var color: Color? = nil
}

enum KeyStyle { case normal, nav, tall, color }

/// The main page: the layout you already know, one button per Samsung key.
struct RemoteView: View {
    @EnvironmentObject var remote: SamsungRemote

    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Spacer(minLength: 24)
                HStack(spacing: 12) {
                    rocker(top: "plus", bottom: "minus", middle: "MUTE", topCode: "KEY_VOLUP", bottomCode: "KEY_VOLDOWN", middleCode: "KEY_MUTE")
                    VStack(spacing: 12) {
                        key(Key(label: "HOME", code: "KEY_HOME"))
                        key(Key(label: "SOURCE", code: "KEY_SOURCE"))
                        key(Key(label: "HDMI", code: "KEY_HDMI"))
                    }
                    rocker(top: "chevron.up", bottom: "chevron.down", middle: "LIST", topCode: "KEY_CHUP", bottomCode: "KEY_CHDOWN", middleCode: "KEY_CH_LIST")
                }
                LazyVGrid(columns: cols, spacing: 12) {
                    key(Key(label: "GUIDE", code: "KEY_GUIDE"))
                    key(Key(label: "123", code: "KEY_MORE"))
                    key(Key(label: "MENU", code: "KEY_MENU"))
                    key(Key(label: "TOOLS", code: "KEY_TOOLS"))
                    key(Key(label: "", code: "KEY_UP", symbol: "arrowtriangle.up.fill", style: .nav))
                    key(Key(label: "INFO", code: "KEY_INFO"))
                    key(Key(label: "", code: "KEY_LEFT", symbol: "arrowtriangle.left.fill", style: .nav))
                    key(Key(label: "", code: "KEY_ENTER", symbol: "return", style: .nav))
                    key(Key(label: "", code: "KEY_RIGHT", symbol: "arrowtriangle.right.fill", style: .nav))
                    key(Key(label: "RETURN", code: "KEY_RETURN"))
                    key(Key(label: "", code: "KEY_DOWN", symbol: "arrowtriangle.down.fill", style: .nav))
                    key(Key(label: "EXIT", code: "KEY_EXIT"))
                    key(Key(label: "P.SIZE", code: "KEY_PICTURE_SIZE"))
                    key(Key(label: "SUBT.", code: "KEY_CAPTION"))
                    key(Key(label: "PRE-CH", code: "KEY_PRECH"))
                }
                HStack(spacing: 12) {
                    key(Key(label: "", code: "KEY_RED", style: .color, color: Color(red: 0.85, green: 0.25, blue: 0.25)))
                    key(Key(label: "", code: "KEY_GREEN", style: .color, color: Color(red: 0.55, green: 0.75, blue: 0.25)))
                    key(Key(label: "", code: "KEY_YELLOW", style: .color, color: Color(red: 0.85, green: 0.70, blue: 0.25)))
                    key(Key(label: "", code: "KEY_CYAN", style: .color, color: Color(red: 0.30, green: 0.50, blue: 0.85)))
                }
                .padding(.top, 8)
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 28)
        }
    }

    func key(_ k: Key) -> some View {
        KeyButton(key: k) { remote.key(k.code) }
    }

    private func rocker(top: String, bottom: String, middle: String, topCode: String, bottomCode: String, middleCode: String) -> some View {
        VStack(spacing: 0) {
            Button { remote.key(topCode) } label: { Image(systemName: top).font(.title2.weight(.bold)).frame(maxWidth: .infinity, minHeight: 100) }
            Button { remote.key(middleCode) } label: { Text(middle).font(.headline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 80) }
            Button { remote.key(bottomCode) } label: { Image(systemName: bottom).font(.title2.weight(.bold)).frame(maxWidth: .infinity, minHeight: 100) }
        }
        .foregroundStyle(.white)
        .background(Theme.key, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.border))
    }
}

struct KeyButton: View {
    let key: Key
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if key.style == .color, let c = key.color {
                    Capsule().fill(c).frame(height: 10).padding(.horizontal, 14)
                } else if let s = key.symbol {
                    Image(systemName: s).font(.title3.weight(.bold))
                } else {
                    Text(key.label).font(.headline.weight(.semibold)).minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: key.style == .color ? 46 : 90)
            .foregroundStyle(.white)
            .background(key.style == .nav ? Theme.nav : Theme.key, in: RoundedRectangle(cornerRadius: key.style == .color ? 14 : 20))
            .overlay(RoundedRectangle(cornerRadius: key.style == .color ? 14 : 20).stroke(Theme.border))
        }
        .buttonStyle(PressStyle())
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Page 2: numbers + transport.
struct KeypadView: View {
    @EnvironmentObject var remote: SamsungRemote
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Spacer(minLength: 24)
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(1...9, id: \.self) { n in KeyButton(key: Key(label: "\(n)", code: "KEY_\(n)")) { remote.key("KEY_\(n)") } }
                    KeyButton(key: Key(label: "TTX/MIX", code: "KEY_TTX_MIX")) { remote.key("KEY_TTX_MIX") }
                    KeyButton(key: Key(label: "0", code: "KEY_0")) { remote.key("KEY_0") }
                    KeyButton(key: Key(label: "", code: "KEY_ENTER", symbol: "return", style: .nav)) { remote.key("KEY_ENTER") }
                }
                LazyVGrid(columns: cols, spacing: 12) {
                    KeyButton(key: Key(label: "", code: "KEY_REWIND", symbol: "backward.fill")) { remote.key("KEY_REWIND") }
                    KeyButton(key: Key(label: "", code: "KEY_PLAY", symbol: "play.fill", style: .nav)) { remote.key("KEY_PLAY") }
                    KeyButton(key: Key(label: "", code: "KEY_FF", symbol: "forward.fill")) { remote.key("KEY_FF") }
                    KeyButton(key: Key(label: "", code: "KEY_STOP", symbol: "stop.fill")) { remote.key("KEY_STOP") }
                    KeyButton(key: Key(label: "", code: "KEY_PAUSE", symbol: "pause.fill")) { remote.key("KEY_PAUSE") }
                    KeyButton(key: Key(label: "", code: "KEY_REC", symbol: "record.circle")) { remote.key("KEY_REC") }
                    KeyButton(key: Key(label: "SLEEP", code: "KEY_SLEEP")) { remote.key("KEY_SLEEP") }
                    KeyButton(key: Key(label: "AMBIENT", code: "KEY_AMBIENT")) { remote.key("KEY_AMBIENT") }
                    KeyButton(key: Key(label: "SETTINGS", code: "KEY_MENU")) { remote.key("KEY_MENU") }
                }
                .padding(.top, 12)
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 28)
        }
    }
}

/// Page 3: one-tap app launch (plain HTTP, no pairing needed).
struct AppsView: View {
    @EnvironmentObject var remote: SamsungRemote
    private let apps: [(String, String, Color)] = [
        ("Netflix", "11101200001", Color(red: 0.90, green: 0.06, blue: 0.08)),
        ("YouTube", "111299001912", Color(red: 1.0, green: 0.0, blue: 0.0)),
        ("Prime Video", "3201910019365", Color(red: 0.0, green: 0.66, blue: 0.88)),
        ("Disney+", "3201901017640", Color(red: 0.05, green: 0.20, blue: 0.55)),
        ("Hulu", "3201601007625", Color(red: 0.11, green: 0.85, blue: 0.53)),
        ("Spotify", "3201606009684", Color(red: 0.11, green: 0.73, blue: 0.33)),
        ("Apple TV", "3201807016597", Color(red: 0.35, green: 0.35, blue: 0.38)),
        ("Plex", "3201512006963", Color(red: 0.90, green: 0.65, blue: 0.10)),
        ("Twitch", "3202203026841", Color(red: 0.57, green: 0.27, blue: 1.0)),
    ]
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Spacer(minLength: 24)
                Text("APPS").font(.caption.weight(.bold)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(apps, id: \.1) { name, id, color in
                        Button { remote.launchApp(id) } label: {
                            HStack {
                                Circle().fill(color).frame(width: 12, height: 12)
                                Text(name).font(.headline.weight(.semibold))
                                Spacer()
                                Image(systemName: "arrow.up.forward").font(.caption).foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 72)
                            .foregroundStyle(.white)
                            .background(Theme.key, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                Text("Launches straight on the TV. Works even before the TV has allowed the remote.")
                    .font(.footnote).foregroundStyle(Theme.muted).padding(.top, 6)
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 28)
        }
    }
}
