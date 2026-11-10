import Combine
import Foundation
import SwitchKeyboardCore

@MainActor
final class SettingsModel: ObservableObject {
    @Published var shortcut: Shortcut {
        didSet {
            guard shortcut != oldValue else { return }
            if let data = try? JSONEncoder().encode(shortcut) {
                defaults.set(data, forKey: Self.shortcutKey)
            }
            onShortcutChanged?(shortcut)
        }
    }

    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            onEnabledChanged?(isEnabled)
        }
    }

    @Published var accessibilityGranted = false
    @Published var inputMonitoringGranted = false
    @Published var isMonitoring = false
    @Published var statusMessage = "Для начала работы предоставьте системные разрешения."
    @Published var isRecordingShortcut = false

    var onShortcutChanged: ((Shortcut) -> Void)?
    var onEnabledChanged: ((Bool) -> Void)?
    var requestPermissions: (() -> Void)?
    var refreshPermissions: (() -> Void)?
    var beginShortcutRecording: (() -> Void)?
    var cancelShortcutRecording: (() -> Void)?

    private static let shortcutKey = "triggerShortcut"
    private static let enabledKey = "conversionEnabled"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.shortcutKey),
           let savedShortcut = try? JSONDecoder().decode(Shortcut.self, from: data) {
            shortcut = savedShortcut
        } else {
            shortcut = .leftOption
        }
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func restoreDefaultShortcut() {
        cancelRecording()
        shortcut = .leftOption
    }

    func startRecording() {
        isRecordingShortcut = true
        beginShortcutRecording?()
    }

    func cancelRecording() {
        isRecordingShortcut = false
        cancelShortcutRecording?()
    }
}
