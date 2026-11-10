import AppKit
import ApplicationServices
import Combine
import SwitchKeyboardCore

@main
enum SwitchKeyboardApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = SettingsModel()
    private let loginItems = LoginItemController()
    private var windowController: SettingsWindowController?
    private var monitor: KeyboardMonitor?
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []
    private var statusMenuItem: NSMenuItem?
    private var toggleMenuItem: NSMenuItem?
    private var shortcutMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchedInBackground = StartupPolicy.isBackgroundLaunch(NSAppleEventManager.shared().currentAppleEvent)
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains(where: { $0.processIdentifier != getpid() }) {
            NSApp.terminate(nil)
            return
        }
        windowController = SettingsWindowController(model: model, loginItems: loginItems)
        if Bundle.main.bundleURL.pathExtension == "app" { loginItems.enableByDefaultIfNeeded() }
        let monitor = KeyboardMonitor(
            shortcut: model.shortcut,
            isEnabled: model.isEnabled,
            targetPID: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        )
        self.monitor = monitor
        monitor.onStatus = { [weak self] running, message in
            self?.model.isMonitoring = running
            self?.model.statusMessage = message
        }
        monitor.onShortcutRecorded = { [weak self] shortcut in
            self?.model.isRecordingShortcut = false
            self?.model.shortcut = shortcut
            self?.model.statusMessage = "Горячая клавиша сохранена: \(shortcut.displayName)."
        }
        monitor.onRecordingCancelled = { [weak self] in self?.model.isRecordingShortcut = false }
        model.onShortcutChanged = { [weak self] _ in self?.updateMonitor() }
        model.onEnabledChanged = { [weak self] _ in self?.updateMonitor() }
        model.beginShortcutRecording = { [weak monitor] in monitor?.recordShortcut() }
        model.cancelShortcutRecording = { [weak monitor] in monitor?.cancelRecording() }
        model.refreshPermissions = { [weak self] in self?.refreshPermissions() }
        model.requestPermissions = { [weak self] in self?.requestPermissions() }
        makeMenu()
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshMenu() }
            .store(in: &cancellables)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.monitor?.activate(pid: app?.processIdentifier ?? 0) }
        }
        refreshPermissions()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        if StartupPolicy.shouldOpenSettings(
            permissionsGranted: model.accessibilityGranted && model.inputMonitoringGranted,
            launchedInBackground: launchedInBackground
        ) { showSettings() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        loginItems.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        monitor?.stop()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func updateMonitor() {
        monitor?.update(shortcut: model.shortcut, isEnabled: model.isEnabled)
    }

    private func requestPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestListenEventAccess()
        refreshPermissions()
    }

    private func refreshPermissions() {
        let accessibility = AXIsProcessTrusted()
        let input = CGPreflightListenEventAccess()
        if model.accessibilityGranted != accessibility { model.accessibilityGranted = accessibility }
        if model.inputMonitoringGranted != input { model.inputMonitoringGranted = input }
        if accessibility, input {
            monitor?.start()
        } else {
            if model.isMonitoring { monitor?.stop(); model.isMonitoring = false }
            let message = "Предоставьте доступ в разделах «Универсальный доступ» и «Мониторинг ввода»."
            if model.statusMessage != message { model.statusMessage = message }
        }
    }

    private func makeMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "A⇄Я"
        item.button?.toolTip = "SwitchKeyboard"
        statusItem = item
        let menu = NSMenu()
        let title = NSMenuItem(title: "SwitchKeyboard", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusMenuItem?.isEnabled = false
        if let statusMenuItem { menu.addItem(statusMenuItem) }
        shortcutMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        shortcutMenuItem?.isEnabled = false
        if let shortcutMenuItem { menu.addItem(shortcutMenuItem) }
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: "Преобразование включено", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggleMenuItem = toggle
        menu.addItem(toggle)
        let settings = NSMenuItem(title: "Настройки…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Завершить SwitchKeyboard", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        // Стандартные ⌘Q и ⌘, работают и без открытого меню строки состояния.
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(settings.copy() as! NSMenuItem)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(quit.copy() as! NSMenuItem)
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        NSApp.mainMenu = mainMenu
        refreshMenu()
    }

    private func refreshMenu() {
        statusMenuItem?.title = model.isMonitoring ? "Перехват клавиш активен" : "Нужны системные разрешения"
        shortcutMenuItem?.title = "Горячая клавиша: \(model.shortcut.displayName)"
        toggleMenuItem?.state = model.isEnabled ? .on : .off
        statusItem?.button?.appearsDisabled = !model.isEnabled
    }

    @objc private func toggleEnabled() { model.isEnabled.toggle() }
    @objc private func showSettings() { windowController?.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
