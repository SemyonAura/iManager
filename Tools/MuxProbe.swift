import Foundation

@main
struct MuxProbe {
    static func main() {
        let rawArguments = Array(CommandLine.arguments.dropFirst())
        let arguments = Set(rawArguments)
        print("iManager · проверка usbmuxd и MobileDevice")
        print("Сокет: \(USBMuxClient.socketPath)")
        print("MobileDevice.framework: \(MobileDeviceBridge.shared.isAvailable ? "доступен" : "недоступен")")
        print("Флаги: --pair (сопряжение), --apps (список), --apps-all (полный список), --install <путь.ipa>")

        do {
            let devices = try USBMuxClient.listDevices()

            if devices.isEmpty {
                print("Устройства не найдены.")
                print("Подключите iPhone/iPad по USB и запустите проверку снова.")
                return
            }

            for device in devices {
                print("")
                print("Устройство #\(device.deviceID)")
                print("  Подключение: \(device.connectionType)")
                print("  Серийный номер: \(device.serialNumber)")
                print("  ProductID: \(device.productID)")

                do {
                    let info = try LockdownClient.fetchInfo(deviceID: device.deviceID)
                    print("  Имя: \(info.deviceName ?? "—")")
                    print("  Модель: \(info.productType ?? "—")")
                    print("  iOS: \(info.productVersion ?? "—") (\(info.buildVersion ?? "—"))")
                    print("  UDID: \(info.uniqueDeviceID ?? "—")")
                } catch {
                    print("  lockdownd: \(error.localizedDescription)")
                    if let info = try? MobileDeviceBridge.shared.deviceInfo(identifier: device.serialNumber) {
                        print("  Имя (MobileDevice): \(info.deviceName ?? "—")")
                        print("  Модель (MobileDevice): \(info.productType ?? "—")")
                        print("  iOS (MobileDevice): \(info.productVersion ?? "—") (\(info.buildVersion ?? "—"))")
                        print("  UDID (MobileDevice): \(info.uniqueDeviceID ?? "—")")
                        print("  Батарея (MobileDevice): \(info.batteryLevel.map { "\($0)%" } ?? "—")")
                        if let total = info.totalDiskCapacity ?? info.totalDataCapacity,
                           let free = info.effectiveDataAvailable {
                            let used = max(0, total - free)
                            let usedText = ByteCountFormatter.string(fromByteCount: used, countStyle: .file)
                            let totalText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                            let freeText = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
                            print("  Хранилище (MobileDevice): \(usedText) из \(totalText), доступно \(freeText)")
                            if let raw = info.totalDataAvailable, raw != free {
                                let rawText = ByteCountFormatter.string(fromByteCount: raw, countStyle: .file)
                                print("  (сырое свободное место: \(rawText))")
                            }
                        }
                    } else {
                        print("  Подсказка: подтвердите доверие компьютеру на экране устройства.")
                    }
                }

                let status = MobileDeviceBridge.shared.pairingStatus(identifier: device.serialNumber)
                print("  Pairing: \(describe(status))")

                var effectiveStatus = status

                if arguments.contains("--pair"), status != .paired {
                    print("  Запуск pairing — разблокируйте устройство и подтвердите доверие…")
                    do {
                        try MobileDeviceBridge.shared.pair(identifier: device.serialNumber)
                        effectiveStatus = .paired
                        print("  Pairing: успешно")
                    } catch {
                        print("  Pairing: \(error.localizedDescription)")
                    }
                }

                if effectiveStatus == .paired {
                    do {
                        let apps = try MobileDeviceBridge.shared.installedApps(identifier: device.serialNumber)
                        let userApps = apps.filter(\.isUserApp)
                        print("  Приложений: \(apps.count), пользовательских: \(userApps.count)")

                        if arguments.contains("--apps") || arguments.contains("--apps-all") {
                            let limit = arguments.contains("--apps-all") ? userApps.count : 30
                            for app in userApps.sorted(by: { $0.name < $1.name }).prefix(limit) {
                                print("    • \(app.name) [\(app.bundleID)] v\(app.version)")
                            }
                        }
                    } catch {
                        print("  Список приложений: \(error.localizedDescription)")
                    }

                    if let installIndex = rawArguments.firstIndex(of: "--install"),
                       installIndex + 1 < rawArguments.count {
                        let path = rawArguments[installIndex + 1]
                        print("  Установка: \(path)")
                        do {
                            let info = try IPAInspector.inspect(
                                path: path,
                                deviceUDID: device.serialNumber
                            )
                            print("  Пакет: \(info.name) [\(info.bundleID)] v\(info.version)")
                            print("  Подпись: \(info.signature.title), PackageType: \(info.packageType)")
                            if let issue = info.blockingIssue {
                                print("  Пропущено: \(issue)")
                            } else {
                                try MobileDeviceBridge.shared.installApp(
                                    identifier: device.serialNumber,
                                    ipaPath: path,
                                    packageType: info.packageType,
                                    progress: { progress in
                                        print("    [\(progress.percent)%] \(progress.localizedStatus)")
                                    }
                                )
                                print("  Установка завершена")
                            }
                        } catch {
                            print("  Ошибка установки: \(error.localizedDescription)")
                        }
                    }
                } else if effectiveStatus != .paired {
                    print("  Подсказка: запустите pairing в приложении iManager или с флагом --pair.")
                }
            }
        } catch {
            print("Ошибка: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func describe(_ status: PairingStatus) -> String {
        switch status {
        case .paired:
            return "сопряжено"
        case .notPaired:
            return "не сопряжено"
        case .pairing:
            return "сопряжение…"
        case .checking:
            return "проверка…"
        case .unknown:
            return "неизвестно"
        case .failed(let message):
            return "ошибка: \(message)"
        }
    }
}
