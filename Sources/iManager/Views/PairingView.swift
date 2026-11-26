import SwiftUI

struct PairingSection: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    let device: Device

    @EnvironmentObject private var manager: DeviceManager

    var body: some View {
        Group {
            switch manager.pairingState(for: device.id) {
            case .paired:
                NoticeCard(
                    icon: "checkmark.shield.fill",
                    title: L("Устройство сопряжено"),
                    text: L("Доверенная связь установлена. Доступны сервисы устройства, включая installation_proxy.")
                )

            case .checking, .unknown:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("Проверка сопряжения…"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)

            case .pairing:
                HStack(alignment: .top, spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Ожидание подтверждения"))
                            .font(.callout.weight(.semibold))
                        Text(L("Разблокируйте устройство и нажмите «Доверять» на его экране."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                )

            case .notPaired:
                VStack(alignment: .leading, spacing: 10) {
                    NoticeCard(
                        icon: "lock.open",
                        title: L("Требуется сопряжение"),
                        text: L("Чтобы открыть доступ к сервисам устройства и списку приложений, подтвердите доверие этому компьютеру.")
                    )
                    Button(L("Сопрячь устройство")) {
                        Task { await manager.pair(device: device) }
                    }
                    .compatButtonStyle(.prominent)
                }

            case .failed(let message):
                VStack(alignment: .leading, spacing: 10) {
                    NoticeCard(
                        icon: "exclamationmark.triangle",
                        title: L("Сопряжение не удалось"),
                        text: message
                    )
                    Button(L("Повторить сопряжение")) {
                        Task { await manager.pair(device: device) }
                    }
                    .compatButtonStyle(.prominent)
                }
            }
        }
    }
}
