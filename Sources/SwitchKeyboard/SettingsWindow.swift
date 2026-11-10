import AppKit
import SwiftUI
import SwitchKeyboardCore

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SwitchKeyboard — Настройки"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.center()
        super.init(window: window)
        window.delegate = self
        window.setFrameAutosaveName("SwitchKeyboardSettings")
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func show() {
        model.refreshPermissions?()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelRecording()
    }
}

private struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                Toggle("Преобразование по горячей клавише", isOn: $model.isEnabled)
                    .toggleStyle(.switch)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(model.isRecordingShortcut ? "Ожидание сочетания…" : model.shortcut.displayName)
                                .font(.system(size: 18, weight: .medium, design: .monospaced))
                                .accessibilityLabel("Текущая горячая клавиша")
                                .accessibilityValue(model.shortcut.displayName)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if model.isRecordingShortcut {
                                Button("Отмена") { model.cancelRecording() }
                            } else {
                                Button("Изменить…") { model.startRecording() }
                                    .disabled(!model.isMonitoring)
                            }
                        }

                        Text(model.isRecordingShortcut
                             ? "Нажмите сочетание клавиш или отдельно нажмите и отпустите модификатор. Esc — отмена."
                             : "По умолчанию — отдельное нажатие и отпускание левого Option. "
                               + "Option вместе с другой клавишей сохраняет обычное действие.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Button("Вернуть левый Option") { model.restoreDefaultShortcut() }
                            .controlSize(.small)
                            .disabled(model.shortcut == .leftOption && !model.isRecordingShortcut)
                    }
                    .padding(8)
                } label: {
                    Label("Горячая клавиша", systemImage: "command")
                }

                permissions
                behavior

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: model.isMonitoring ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(model.isMonitoring ? Color.green : Color.secondary)
                    Text(model.statusMessage)
                        .font(.callout)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
        }
        .frame(width: 620, height: 720)
        .onExitCommand {
            if model.isRecordingShortcut { model.cancelRecording() }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "keyboard")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("SwitchKeyboard")
                    .font(.title2.bold())
                Text("Исправление раскладки EN ↔ RU по вашей команде")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var permissions: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                permissionRow(
                    title: "Универсальный доступ",
                    subtitle: "Замена текста в активном приложении.",
                    granted: model.accessibilityGranted,
                    pane: "Privacy_Accessibility"
                )
                Divider()
                permissionRow(
                    title: "Мониторинг ввода",
                    subtitle: "Глобальная горячая клавиша и недавно набранный текст.",
                    granted: model.inputMonitoringGranted,
                    pane: "Privacy_ListenEvent"
                )
                HStack {
                    Button("Запросить разрешения") { model.requestPermissions?() }
                    Button("Проверить снова") { model.refreshPermissions?() }
                }
                .controlSize(.small)
                Text("Включите SwitchKeyboard в обоих разделах. Если macOS попросит перезапуск, закройте приложение "
                     + "через меню в строке состояния и запустите снова.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        } label: {
            Label("Системные разрешения", systemImage: "lock.shield")
        }
    }

    private var behavior: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Выделенный текст имеет приоритет. Без выделения меняется недавно набранный фрагмент: "
                     + "он начинается заново после Enter, перемещения курсора или клика.")
                Text("Пробелы и регистр сохраняются. В смешанном тексте каждая буква меняет раскладку: "
                     + "Ghbdtn рщц → Привет how. Словаря и проверки орфографии нет.")
                Text("Ввод паролей и Secure Input недоступны. Совместимость зависит от приложения.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(8)
        } label: {
            Label("Как работает замена", systemImage: "arrow.left.arrow.right")
        }
    }

    private func permissionRow(title: String, subtitle: String, granted: Bool, pane: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Открыть…") {
                guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
                    return
                }
                NSWorkspace.shared.open(url)
            }
            .controlSize(.small)
        }
    }
}
