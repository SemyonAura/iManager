import SwiftUI
import AppKit

@main
struct iManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var manager = DeviceManager()

    var body: some Scene {
        WindowGroup("iManager") {
            ContentView()
                .environmentObject(manager)
                .frame(minWidth: 980, minHeight: 640)
        }
        .commands {
            AppCommands(manager: manager)
        }
    }
}

/// Меню приложения. Отдельная структура нужна, чтобы названия пунктов
/// обновлялись при смене языка интерфейса.
struct AppCommands: Commands {
    @ObservedObject var manager: DeviceManager
    @ObservedObject private var l10n = LocalizationManager.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) { }

        CommandGroup(replacing: .appSettings) {
            Button(L("Настройки…")) {
                SettingsStore.shared.present()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu(L("Устройство")) {
            Button(L("Обновить список")) {
                Task { await manager.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandMenu(L("Язык")) {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    LocalizationManager.shared.language = language
                } label: {
                    if LocalizationManager.shared.language == language {
                        Label(language.title, systemImage: "checkmark")
                    } else {
                        Text(language.title)
                    }
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
