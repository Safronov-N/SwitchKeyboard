import Combine
import Foundation
import ServiceManagement

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

struct SystemLoginItemService: LoginItemService {
    nonisolated init() {}

    var status: SMAppService.Status { SMAppService.mainApp.status }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var statusMessage = ""

    private let service: any LoginItemService
    private let defaults: UserDefaults
    private var lastFailure: String?
    private var statusAtFailure: SMAppService.Status?
    private static let defaultAppliedKey = "launchAtLoginDefaultApplied"

    init(service: any LoginItemService = SystemLoginItemService(), defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        refresh()
    }

    func refresh() {
        let status = service.status
        if statusAtFailure != status {
            lastFailure = nil
            statusAtFailure = nil
        }
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
        let description = Self.description(for: status)
        statusMessage = lastFailure.map { "\($0) \(description)" } ?? description
    }

    func setEnabled(_ enabled: Bool) {
        // Явный выбор пользователя отменяет будущую попытку включения по умолчанию.
        defaults.set(true, forKey: Self.defaultAppliedKey)
        lastFailure = nil
        statusAtFailure = nil
        let status = service.status
        if enabled && (status == .enabled || status == .requiresApproval) {
            refresh()
            return
        }
        if !enabled && status == .notRegistered {
            refresh()
            return
        }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            let operation = enabled ? "включить" : "выключить"
            lastFailure = "Не удалось \(operation) запуск при входе: \(error.localizedDescription)."
            statusAtFailure = service.status
        }
        refresh()
    }

    func enableByDefaultIfNeeded() {
        guard !defaults.bool(forKey: Self.defaultAppliedKey) else {
            refresh()
            return
        }
        // Фиксируем попытку до регистрации: ошибка или отказ не должны вызывать повтор каждые две секунды.
        defaults.set(true, forKey: Self.defaultAppliedKey)
        let status = service.status
        guard status == .notRegistered || status == .notFound else {
            refresh()
            return
        }
        setEnabled(true)
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }

    private static func description(for status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            return "Запуск при входе включён."
        case .notRegistered:
            return "Запуск при входе выключен."
        case .requiresApproval:
            return "Подтвердите запуск при входе в системных настройках."
        case .notFound:
            return "Автозапуск ещё не зарегистрирован. Включите запуск при входе."
        @unknown default:
            return "Неизвестное состояние запуска при входе."
        }
    }
}
