import AppKit
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppController {
    var isEnabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "enabled")
            if !isEnabled { cancelPreview(); soundedKeys.removeAll(); activeKeys.removeAll() }
        }
    }
    var volume = preference("volume", fallback: 0.6) { didSet { save("volume", volume) } }
    var volumeMode = VolumeMode(rawValue: UserDefaults.standard.string(forKey: "volumeMode") ?? "") ?? .gradient {
        didSet { UserDefaults.standard.set(volumeMode.rawValue, forKey: "volumeMode"); configureAudio() }
    }
    var spatialWidth = preference("width", fallback: 0.65) { didSet { save("width", spatialWidth) } }
    var depth = preference("depth", fallback: 0.5) { didSet { save("depth", depth) } }
    var releaseLevel = preference("release", fallback: 0.5) { didSet { save("release", releaseLevel) } }
    var naturalVariation = UserDefaults.standard.object(forKey: "variation") as? Bool ?? true {
        didSet { UserDefaults.standard.set(naturalVariation, forKey: "variation"); configureAudio() }
    }
    private(set) var selectedProfile = SwitchProfile.find(UserDefaults.standard.string(forKey: "switch") ?? "blackink")
    private(set) var hasPermission = KeyboardMonitor.isAuthorized
    private(set) var isListening = false
    private(set) var secureInput = false
    private(set) var isLoading = true
    private(set) var audioError: String?
    private(set) var activeKeys = Set<UInt16>()
    private(set) var isPreviewing = false
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var loginError: String?
    private(set) var constantVolumeStatus: ConstantVolumeStatus = .unavailable

    @ObservationIgnored private let audio = SoundEngine()
    @ObservationIgnored private let monitor = KeyboardMonitor()
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var soundedKeys = Set<UInt16>()
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    var status: String {
        if let audioError { return audioError }
        if isLoading { return "Loading recordings…" }
        if !isEnabled { return "Paused. Your quiet moment." }
        if secureInput { return "Paused during secure input" }
        if !hasPermission { return "Allow keyboard access to begin" }
        if !isListening { return "Keyboard access needs a restart" }
        return "Listening, wherever you type"
    }

    init() {
        audio.onError = { [weak self] message in
            Task { @MainActor [weak self] in self?.audioError = message }
        }
        audio.onVolumeStatus = { [weak self] status in
            Task { @MainActor [weak self] in self?.constantVolumeStatus = status }
        }
        monitor.onKey = { [weak self] stroke in self?.receive(stroke) }
        monitor.onToggle = { [weak self] in self?.isEnabled.toggle() }
        configureAudio()
        loadSelectedProfile()
        refreshPermissions()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPermissions() }
        }
        if let permissionTimer { RunLoop.main.add(permissionTimer, forMode: .common) }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification,
                                                    object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.monitor.stop()
                self?.isListening = false
                self?.soundedKeys.removeAll()
                self?.activeKeys.removeAll()
                self?.audio.silence()
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                                    object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPermissions() }
        })
    }

    func select(_ profile: SwitchProfile) {
        guard profile != selectedProfile else { return }
        cancelPreview()
        selectedProfile = profile
        UserDefaults.standard.set(profile.id, forKey: "switch")
        soundedKeys.removeAll()
        activeKeys.removeAll()
        loadSelectedProfile()
    }

    func preview(_ profile: SwitchProfile? = nil) {
        if let profile { select(profile) }
        cancelPreview()
        previewTask = Task { [weak self] in
            guard let self else { return }
            // Loading happens off the main thread; a preview waits for its selected pack.
            while self.isLoading && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(30))
            }
            guard !Task.isCancelled, self.audioError == nil else { return }
            self.isPreviewing = true
            for code: UInt16 in [0, 3, 38, 40, 49, 12, 17, 32, 35, 36] {
                guard !Task.isCancelled else { return }
                self.playPreviewKey(code, isDown: true)
                try? await Task.sleep(for: .milliseconds(65))
                guard !Task.isCancelled else { return }
                self.playPreviewKey(code, isDown: false)
                try? await Task.sleep(for: .milliseconds(code == 49 ? 160 : 90))
            }
            self.isPreviewing = false
        }
    }

    func tapPreviewKey(_ code: UInt16) {
        guard !isLoading, audioError == nil else { return }
        let profileID = selectedProfile.id
        playPreviewKey(code, isDown: true)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self, self.selectedProfile.id == profileID else { return }
            self.playPreviewKey(code, isDown: false)
        }
    }

    func requestPermission() {
        NSApp.activate(ignoringOtherApps: true)
        CGRequestListenEventAccess()
        openPermissionSettings()
        refreshPermissions()
    }

    func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshPermissions() {
        hasPermission = KeyboardMonitor.isAuthorized
        let secure = KeyboardMonitor.isSecureInput
        if secure != secureInput {
            secureInput = secure
            monitor.resetHeldKeys()
            soundedKeys.removeAll()
            activeKeys.removeAll()
            if secure { audio.silence() }
        }
        if hasPermission {
            isListening = monitor.start()
        } else {
            monitor.stop()
            isListening = false
            soundedKeys.removeAll()
            activeKeys.removeAll()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch { loginError = error.localizedDescription }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            loginError = "Allow Clicky in System Settings → General → Login Items."
        }
    }

    func retryAudio() { loadSelectedProfile() }

    private func receive(_ stroke: KeyStroke) {
        guard isEnabled, !isLoading, audioError == nil, !KeyboardMonitor.isSecureInput else { return }
        if stroke.isDown { soundedKeys.insert(stroke.code); activeKeys.insert(stroke.code) }
        else {
            activeKeys.remove(stroke.code)
            guard soundedKeys.remove(stroke.code) != nil else { return }
        }
        audio.play(stroke, profileID: selectedProfile.id)
    }

    private func playPreviewKey(_ code: UInt16, isDown: Bool) {
        if isDown { activeKeys.insert(code) } else { activeKeys.remove(code) }
        audio.play(KeyStroke(code: code, isDown: isDown), profileID: selectedProfile.id)
    }

    private func cancelPreview() {
        previewTask?.cancel()
        previewTask = nil
        isPreviewing = false
        activeKeys.removeAll()
        audio.silence()
    }

    private func loadSelectedProfile() {
        isLoading = true
        audioError = nil
        let id = selectedProfile.id
        audio.load(selectedProfile) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, self.selectedProfile.id == id else { return }
                self.isLoading = false
                self.audioError = error
            }
        }
    }

    private func save(_ key: String, _ value: Double) {
        UserDefaults.standard.set(value, forKey: key)
        configureAudio()
    }

    private func configureAudio() {
        audio.configure(PlaybackSettings(volume: Float(volume), volumeMode: volumeMode, width: Float(spatialWidth),
                                         depth: Float(depth), releaseLevel: Float(releaseLevel),
                                         variation: naturalVariation))
    }
}

private func preference(_ key: String, fallback: Double) -> Double {
    guard let number = UserDefaults.standard.object(forKey: key) as? Double, number.isFinite else { return fallback }
    return max(0, min(1, number))
}
