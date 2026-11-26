import SwiftUI

struct SidebarView: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    @EnvironmentObject private var manager: DeviceManager
    @ObservedObject private var downloads = DownloadManager.shared

    var body: some View {
        List(selection: $manager.selectedDeviceID) {
            Section(L("Устройства")) {
                if manager.devices.isEmpty {
                    EmptyDeviceRow()
                } else {
                    ForEach(manager.devices) { device in
                        NavigationLink(
                            destination: DeviceDetailView(device: device).id(device.id),
                            tag: device.id,
                            selection: $manager.selectedDeviceID
                        ) {
                            DeviceRow(device: device)
                        }
                    }
                }
            }

            Section(L("Инструменты")) {
                NavigationLink(
                    destination: StoreView(),
                    tag: "appstore",
                    selection: $manager.selectedDeviceID
                ) {
                    Label("App Store", systemImage: "bag")
                }

                NavigationLink(
                    destination: DownloadsView(),
                    tag: "downloads",
                    selection: $manager.selectedDeviceID
                ) {
                    HStack(spacing: 8) {
                        Label(L("Загрузки"), systemImage: "arrow.down.circle")

                        Spacer(minLength: 0)

                        if !downloads.activeDownloads.isEmpty {
                            Text("\(downloads.activeDownloads.count)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                                .compatForeground(Color.accentColor)
                        }
                    }
                }
            }

            Section(L("Состояние")) {
                HStack(spacing: 8) {
                    if manager.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                        Text(L("Поиск устройств…"))
                    } else {
                        Circle()
                            .fill(manager.devices.isEmpty ? Color.secondary.opacity(0.45) : Color.green)
                            .frame(width: 7, height: 7)
                        Text(manager.devices.isEmpty ? L("Ожидание подключения") : L("Обнаружено: %d", manager.devices.count))
                    }
                    Spacer()
                }
                .font(.caption)
                .foregroundColor(.secondary)

                if manager.devices.isEmpty, let message = manager.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let updated = manager.lastUpdated {
                    Text(L("Обновлено: %@", LDate(updated, dateStyle: .none, timeStyle: .medium)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("iManager")
    }
}

private struct DeviceRow: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    let device: Device

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.isTablet ? "ipad" : "iphone")
                .font(.title3)
                .compatForeground(Color.accentColor)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(device.iosVersion == "—" ? device.modelName : "iOS \(device.iosVersion)")
                        .lineLimit(1)
                    Text("•")
                    Label(device.connection.title, systemImage: device.connection.symbol)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct EmptyDeviceRow: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(L("Нет подключённых устройств"), systemImage: "iphone.slash")
                .font(.callout)
            Text(L("Подключите iPhone или iPad по USB либо включите синхронизацию по Wi-Fi."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
}
