import SwiftUI
import AppKit

struct OverviewView: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    let device: Device

    @EnvironmentObject private var manager: DeviceManager
    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(
                title: L("Сведения об устройстве"),
                subtitle: device.isInfoLoaded
                    ? L("Данные получены от устройства через lockdownd")
                    : L("Доступны только базовые данные usbmuxd")
            )

            LazyVGrid(columns: columns, spacing: 12) {
                Group {
                    InfoTile(title: L("Модель"), value: device.modelName, icon: "iphone")
                    InfoTile(title: L("Тип продукта"), value: device.productType.isEmpty ? "—" : device.productType, icon: "cpu")
                    InfoTile(title: L("Версия iOS"), value: device.iosVersion, icon: "gearshape")
                    InfoTile(title: L("Сборка"), value: device.buildVersion, icon: "hammer")
                    InfoTile(title: L("Архитектура CPU"), value: device.cpuArchitecture ?? "—", icon: "memorychip")
                    InfoTile(title: L("Номер модели"), value: device.modelNumber ?? "—", icon: "barcode")
                    InfoTile(title: L("Регион"), value: device.regionInfo ?? "—", icon: "globe")
                    InfoTile(title: L("Активация"), value: activationText, icon: "checkmark.seal")
                    InfoTile(title: "UDID", value: device.udid, icon: "number", monospaced: true)
                    InfoTile(title: L("Серийный номер"), value: device.serialNumber, icon: "barcode", monospaced: true)
                }
                Group {
                    InfoTile(title: L("Подключение"), value: device.connection.title, icon: device.connection.symbol)
                    if let platform = device.hardwarePlatform, !platform.isEmpty {
                        InfoTile(title: L("Аппаратная платформа"), value: platform, icon: "cpu")
                    }
                    if let model = device.hardwareModel, !model.isEmpty {
                        InfoTile(title: L("Аппаратная модель"), value: model, icon: "cpu")
                    }
                    if let color = device.deviceColor, !color.isEmpty {
                        InfoTile(title: L("Цвет корпуса"), value: color, icon: "paintpalette")
                    }
                    if let mem = device.physicalMemory, mem > 0 {
                        InfoTile(title: L("Оперативная память"), value: ByteFormatter.string(mem), icon: "memorychip")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: L("Аккумулятор"), subtitle: nil)
                LazyVGrid(columns: columns, spacing: 12) {
                    InfoTile(
                        title: L("Уровень заряда"),
                        value: device.batteryLevel.map { "\($0)%" } ?? L("Нет данных"),
                        icon: "battery.75"
                    )
                    InfoTile(
                        title: L("Зарядка"),
                        value: chargingText,
                        icon: device.batteryCharging == true ? "bolt.fill" : "bolt.slash"
                    )
                    if let cycles = device.batteryCycleCount {
                        InfoTile(title: L("Циклы зарядки"), value: "\(cycles)", icon: "arrow.triangle.2.circlepath")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: L("Сеть"), subtitle: nil)
                LazyVGrid(columns: columns, spacing: 12) {
                    InfoTile(title: "Wi-Fi (MAC)", value: device.wifiAddress ?? "—", icon: "wifi", monospaced: true)
                    InfoTile(title: "Bluetooth (MAC)", value: device.bluetoothAddress ?? "—", icon: "dot.radiowaves.left.and.right", monospaced: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(
                    title: L("Доступ и сопряжение"),
                    subtitle: L("Pairing открывает доступ к сервисам устройства")
                )
                PairingSection(device: device)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await manager.reloadSelectedDevice() }
                } label: {
                    if manager.isRefreshing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L("Обновление…"))
                        }
                    } else {
                        Label(L("Обновить данные"), systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(manager.isRefreshing)

                Button {
                    copySummary()
                } label: {
                    Label(L("Скопировать сводку"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if !device.isInfoLoaded {
                NoticeCard(
                    icon: "lock.shield",
                    title: L("Ограниченный доступ"),
                    text: L("Не удалось получить сведения об устройстве. Разблокируйте iPhone или iPad, подтвердите доверие этому компьютеру и нажмите «Обновить».")
                )
            }
        }
    }

    private var activationText: String {
        let raw = device.activationState ?? ""
        if raw.isEmpty { return "—" }
        switch raw.lowercased() {
        case "activated": return L("Активировано")
        case "factoryactivated": return L("Заводская активация")
        default: return raw
        }
    }

    private var chargingText: String {
        if device.batteryLevel == nil { return L("Нет данных") }
        if let charging = device.batteryCharging {
            return charging ? L("Идёт зарядка") : L("Не заряжается")
        }
        return "—"
    }

    private func copySummary() {
        var lines: [String] = []
        lines.append(L("Устройство: %@ (%@)", device.name, device.modelName))
        lines.append(L("Тип: %@", device.productType))
        lines.append(L("iOS: %@ (%@)", device.iosVersion, device.buildVersion))
        lines.append(L("UDID: %@", device.udid))
        lines.append(L("Серийный: %@", device.serialNumber))
        if let level = device.batteryLevel { lines.append(L("Аккумулятор: %d%%", level)) }
        if let mem = device.physicalMemory { lines.append(L("Оперативная память: %@", ByteFormatter.string(mem))) }
        if let wifi = device.wifiAddress { lines.append(L("Wi-Fi MAC: %@", wifi)) }
        if let bt = device.bluetoothAddress { lines.append(L("Bluetooth MAC: %@", bt)) }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
