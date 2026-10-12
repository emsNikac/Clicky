import AppKit
import SwiftUI

enum ClickyTheme {
    static let background = Color(hex: 0x1B1C20)
    static let surface = Color(hex: 0x24252B)
    static let elevated = Color(hex: 0x2C2D34)
    static let accent = Color(hex: 0xF2B880)
    static let muted = Color(hex: 0x92939F)
    static let text = Color(hex: 0xF4F0E9)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct MenuPanel: View {
    @Bindable var controller: AppController
    @State private var showingSettings = false
    @State private var category: SwitchCategory?
    @State private var search = ""

    private var filteredProfiles: [SwitchProfile] {
        SwitchProfile.all.filter { profile in
            (category == nil || category == profile.category) &&
            (search.isEmpty || "\(profile.name) \(profile.maker) \(profile.character)"
                .localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !controller.hasPermission || !controller.isListening {
                        permissionCard
                    }
                    if let error = controller.audioError {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Audio needs attention", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 12, weight: .semibold))
                            Text(error).font(.system(size: 11)).foregroundStyle(ClickyTheme.muted)
                            Button("Try again") { controller.retryAudio() }.buttonStyle(.bordered)
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(ClickyTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if showingSettings { settings } else { library }
                }
                .padding(20)
            }
            if showingSettings {
                settingsPreview
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(ClickyTheme.background)
                    .overlay(alignment: .top) { Divider().opacity(0.4) }
            }
            footer
        }
        .frame(width: 390, height: 690)
        .background(ClickyTheme.background)
        .foregroundStyle(ClickyTheme.text)
        .tint(ClickyTheme.accent)
        .preferredColorScheme(.dark)
        .onAppear { controller.refreshPermissions() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().scaledToFit().frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Clicky").font(.system(size: 23, weight: .bold, design: .rounded)).tracking(-0.7)
                Text("A little more character.").font(.system(size: 10)).foregroundStyle(ClickyTheme.muted)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { controller.isEnabled.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(controller.isEnabled ? ClickyTheme.accent : ClickyTheme.muted).frame(width: 5, height: 5)
                    Text(controller.isEnabled ? "ON" : "PAUSED").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(controller.isEnabled ? ClickyTheme.accent : ClickyTheme.muted)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(controller.isEnabled ? ClickyTheme.accent.opacity(0.1) : ClickyTheme.surface,
                            in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controller.isEnabled ? "Pause keyboard sounds" : "Enable keyboard sounds")
            .help("Toggle sounds · ⌃⌥⌘M")
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .overlay(alignment: .bottom) { Divider().opacity(0.4) }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 18) {
            selectedCard
            VStack(alignment: .leading, spacing: 12) {
                volumeControl
                volumeModeControl
            }
            HStack {
                Text("SWITCH LIBRARY").font(.system(size: 10, weight: .bold)).tracking(1.5)
                Spacer()
                Text("\(SwitchProfile.all.count) recorded profiles")
                    .font(.system(size: 10)).foregroundStyle(ClickyTheme.muted)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(ClickyTheme.muted)
                TextField("Find your sound…", text: $search)
                    .textFieldStyle(.plain).font(.system(size: 12))
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(ClickyTheme.muted).accessibilityLabel("Clear search")
                }
            }.padding(10).background(ClickyTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 5) {
                categoryButton("All", category: nil)
                ForEach(SwitchCategory.allCases) { item in categoryButton(item.rawValue, category: item) }
            }
            LazyVStack(spacing: 6) {
                ForEach(filteredProfiles) { profile in profileRow(profile) }
                if filteredProfiles.isEmpty {
                    Text("No switches found. Try another search.")
                        .font(.system(size: 12)).foregroundStyle(ClickyTheme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            }
        }
    }

    private var selectedCard: some View {
        let profile = controller.selectedProfile
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("NOW PLAYING").font(.system(size: 9, weight: .bold)).tracking(1.8)
                        .foregroundStyle(ClickyTheme.accent)
                    Text(profile.name).font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-0.6)
                    Text("\(profile.maker) / \(profile.category.rawValue)")
                        .font(.system(size: 11)).foregroundStyle(ClickyTheme.muted)
                }
                Spacer()
                SwitchIllustration(color: Color(hex: profile.colorHex)).frame(width: 64, height: 66)
            }
            KeyboardPreview(activeKeys: controller.activeKeys, accent: Color(hex: profile.colorHex)) {
                controller.tapPreviewKey($0)
            }
            HStack {
                Text(controller.isLoading ? "Loading…" : "Tap a key. Find your rhythm.")
                    .font(.system(size: 10)).foregroundStyle(ClickyTheme.muted)
                Spacer()
                Button { controller.preview() } label: {
                    Label(controller.isPreviewing ? "Playing" : "Preview", systemImage: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(ClickyTheme.accent)
                .disabled(controller.isLoading || controller.audioError != nil)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 15).fill(
                LinearGradient(colors: [Color(hex: profile.colorHex).opacity(0.11), ClickyTheme.surface],
                               startPoint: .topTrailing, endPoint: .bottomLeading))
        }
        .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.07)) }
    }

    private var volumeControl: some View {
        HStack(spacing: 12) {
            Image(systemName: controller.volume == 0 ? "speaker.slash" : "speaker.wave.2")
                .font(.system(size: 12)).foregroundStyle(ClickyTheme.muted).frame(width: 18)
            Slider(value: $controller.volume, in: 0...1).controlSize(.small).accessibilityLabel("Volume")
            Text("\(Int(controller.volume * 100))%")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(ClickyTheme.muted).frame(width: 32)
        }
    }

    private var volumeModeControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Volume mode", selection: $controller.volumeMode) {
                ForEach(VolumeMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented).controlSize(.small)
            .accessibilityLabel("Volume mode")
            Text(controller.volumeMode == .gradient
                 ? "Follows your Mac's volume."
                 : controller.constantVolumeStatus.message)
                .font(.system(size: 10)).foregroundStyle(ClickyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func categoryButton(_ title: String, category item: SwitchCategory?) -> some View {
        Button { category = item } label: {
            Text(title).font(.system(size: 10, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .foregroundStyle(category == item ? ClickyTheme.background : ClickyTheme.muted)
                .background(category == item ? ClickyTheme.accent : ClickyTheme.surface,
                            in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityAddTraits(category == item ? .isSelected : [])
    }

    private func profileRow(_ profile: SwitchProfile) -> some View {
        let selected = controller.selectedProfile == profile
        return HStack(spacing: 0) {
            Button { controller.select(profile) } label: {
                HStack(spacing: 11) {
                    RoundedRectangle(cornerRadius: 6).fill(Color(hex: profile.colorHex).opacity(0.15))
                        .frame(width: 32, height: 35)
                        .overlay { Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 15)).foregroundStyle(Color(hex: profile.colorHex)) }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(profile.name).font(.system(size: 12, weight: .semibold))
                            if selected {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 10))
                                    .foregroundStyle(ClickyTheme.accent)
                            }
                        }
                        Text(profile.character).font(.system(size: 10)).foregroundStyle(ClickyTheme.muted)
                    }
                    Spacer(minLength: 4)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Select \(profile.maker) \(profile.name)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            Button { controller.preview(profile) } label: {
                Image(systemName: "play.fill").font(.system(size: 10))
                    .foregroundStyle(selected ? ClickyTheme.accent : ClickyTheme.muted)
                    .frame(width: 30, height: 35).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Preview \(profile.name)")
        }
        .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 9)
        .background(selected ? ClickyTheme.accent.opacity(0.055) : ClickyTheme.surface.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(
            selected ? ClickyTheme.accent.opacity(0.3) : .clear) }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Let Clicky hear your keys", systemImage: "hand.raised")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(ClickyTheme.accent)
            Text("Allow Clicky in System Settings → Privacy & Security → Input Monitoring. Then quit and reopen it if macOS asks.")
                .font(.system(size: 11)).foregroundStyle(ClickyTheme.muted).fixedSize(horizontal: false, vertical: true)
            Button(controller.hasPermission ? "Open Input Monitoring" : "Allow keyboard access") {
                if controller.hasPermission { controller.openPermissionSettings() }
                else { controller.requestPermission() }
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
            .foregroundStyle(ClickyTheme.background)
            Text("Only key positions are used. Your typing is never saved.")
                .font(.system(size: 9)).foregroundStyle(ClickyTheme.muted)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(ClickyTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Make it yours.").font(.system(size: 24, weight: .semibold, design: .rounded)).tracking(-0.6)
                Text("Small adjustments. A different atmosphere.")
                    .font(.system(size: 11)).foregroundStyle(ClickyTheme.muted)
            }
            settingSlider("Volume", detail: "How much character fills the room.", value: $controller.volume,
                          low: "Quiet", high: "Loud")
            volumeModeControl
            settingSlider("Spatial width", detail: "Follow each key from left to right.", value: $controller.spatialWidth,
                          low: "Centered", high: "Wide")
            settingSlider("Tone", detail: "Shape the recording, from bright to deep.", value: $controller.depth,
                          low: "Bright", high: "Deep")
            settingSlider("Key release", detail: "The softer sound as your fingers lift.", value: $controller.releaseLevel,
                          low: "Off", high: "Present")
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $controller.naturalVariation) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Natural variation").font(.system(size: 12, weight: .medium))
                        Text("Subtle changes keep repeated keys alive.")
                            .font(.system(size: 10)).foregroundStyle(ClickyTheme.muted)
                    }
                }
                Toggle(isOn: Binding(get: { controller.launchAtLogin }, set: { controller.setLaunchAtLogin($0) })) {
                    Text("Start at login").font(.system(size: 12, weight: .medium))
                }
                if let error = controller.loginError {
                    Text(error).font(.system(size: 10)).foregroundStyle(ClickyTheme.accent)
                }
            }.toggleStyle(.switch).controlSize(.small)
            VStack(alignment: .leading, spacing: 7) {
                Text("REAL RECORDINGS. LOCAL PLAYBACK.")
                    .font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(ClickyTheme.accent)
                Text("Recordings by Thomas Lai / kbsim, used under the MIT license. Row-specific samples, plus separate space, return and delete sounds where available. MX Blue uses row samples for every key.")
                    .font(.system(size: 10)).foregroundStyle(ClickyTheme.muted)
                Link("Sound credits & source ↗", destination: URL(string: "https://github.com/tplai/kbsim")!)
                    .font(.system(size: 10, weight: .medium))
                Text("Clicky stays on your Mac and pauses during secure password entry. Physical key positions follow an ANSI layout, with ISO and JIS key support.")
                    .font(.system(size: 10)).foregroundStyle(ClickyTheme.muted)
            }
        }
    }

    private var settingsPreview: some View {
        SettingsPreviewButton(isLoading: controller.isLoading, isPlaying: controller.isPreviewing,
                              hasAudioError: controller.audioError != nil) { controller.preview() }
    }

    private func settingSlider(_ title: String, detail: String, value: Binding<Double>, low: String, high: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(ClickyTheme.accent)
            }
            Text(detail).font(.system(size: 10)).foregroundStyle(ClickyTheme.muted)
            Slider(value: value, in: 0...1).controlSize(.small).accessibilityLabel(title)
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }.font(.system(size: 9)).foregroundStyle(ClickyTheme.muted)
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(controller.isEnabled && controller.isListening && !controller.secureInput && controller.audioError == nil
                          ? Color(hex: 0xA6C5A3) : ClickyTheme.muted).frame(width: 5, height: 5)
            Text(controller.status).font(.system(size: 9)).foregroundStyle(ClickyTheme.muted).lineLimit(1)
            Spacer(minLength: 4)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showingSettings.toggle() }
            } label: {
                Image(systemName: showingSettings ? "arrow.left" : "slider.horizontal.3")
                    .font(.system(size: 12)).frame(width: 25, height: 25)
            }.buttonStyle(.plain).help(showingSettings ? "Back to switches" : "Sound settings")
                .accessibilityLabel(showingSettings ? "Back to switches" : "Sound settings")
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 12)).frame(width: 25, height: 25)
            }.buttonStyle(.plain).help("Quit Clicky").accessibilityLabel("Quit Clicky")
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .overlay(alignment: .top) { Divider().opacity(0.4) }
    }
}

struct SettingsPreviewButton: View {
    let isLoading: Bool
    let isPlaying: Bool
    let hasAudioError: Bool
    let action: () -> Void

    private var isAvailable: Bool { !isLoading && !hasAudioError }

    var body: some View {
        Button(action: action) {
            Label(isLoading ? "Loading recordings…" : isPlaying ? "Playing preview…" : "Preview your settings",
                  systemImage: isPlaying ? "waveform" : "play.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isAvailable ? ClickyTheme.background : ClickyTheme.text)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(isAvailable ? ClickyTheme.accent : ClickyTheme.elevated,
                            in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityLabel("Preview your settings")
    }
}

private struct SwitchIllustration: View {
    let color: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.25))
                .frame(width: 52, height: 42).rotationEffect(.degrees(-12)).offset(y: 10)
            RoundedRectangle(cornerRadius: 9).fill(color.opacity(0.3))
                .frame(width: 50, height: 42).rotationEffect(.degrees(-12)).offset(y: 4)
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(color.opacity(0.5))
                    .frame(width: 50, height: 42).rotationEffect(.degrees(-12)).offset(y: 4) }
            RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.6))
                .frame(width: 36, height: 29).rotationEffect(.degrees(-12)).offset(y: -3)
            Image(systemName: "plus").font(.system(size: 21, weight: .black))
                .foregroundStyle(color).rotationEffect(.degrees(-12)).offset(y: -8)
        }.accessibilityHidden(true)
    }
}

private struct KeyboardPreview: View {
    let activeKeys: Set<UInt16>
    let accent: Color
    let onTap: (UInt16) -> Void

    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.width / 15
            VStack(spacing: 3) {
                ForEach(0..<PhysicalKeyboard.rows.count, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(PhysicalKeyboard.rows[row]) { key in
                            Button { onTap(key.code) } label: {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(activeKeys.contains(key.code) ? accent : .white.opacity(row == 0 ? 0.045 : 0.075))
                                    .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.05)) }
                                    .overlay {
                                        Text(key.label).font(.system(size: row == 0 ? 4 : 6, weight: .medium))
                                            .foregroundStyle(activeKeys.contains(key.code) ? ClickyTheme.background : ClickyTheme.muted)
                                    }
                                    .frame(width: max(1, unit * key.width - 3), height: row == 0 ? 10 : 16)
                                    .frame(width: unit * key.width)
                            }.buttonStyle(.plain)
                                .accessibilityLabel(key.code == 49 ? "Preview space" : "Preview \(key.label)")
                        }
                    }
                }
            }
        }.frame(height: 105)
    }
}
