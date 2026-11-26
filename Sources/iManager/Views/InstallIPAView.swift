import SwiftUI

struct InstallIPAView: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    let device: Device
    let ipa: IPAInfo

    @EnvironmentObject private var manager: DeviceManager
    @Environment(\.presentationMode) private var presentationMode
    private func dismiss() { presentationMode.wrappedValue.dismiss() }

    private var state: AppInstallState {
        manager.installState(for: ipa.path)
    }

    private var isInstalling: Bool {
        if case .installing = state { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            details

            if let warning = ipa.warning {
                NoticeCard(
                    icon: ipa.canInstall ? "info.circle" : "exclamationmark.triangle",
                    title: ipa.canInstall ? L("Сведения о подписи") : L("Установка заблокирована"),
                    text: warning
                )
            }

            status

            if ipa.canInstall && !isInstalling {
                Label(
                    L("Перед установкой разблокируйте устройство и не блокируйте экран до завершения."),
                    systemImage: "lock.open"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
            actions
        }
        .padding(22)
        .frame(width: 540)
        .interactiveDismissDisabled(isInstalling)
        .onAppear {
            manager.resetInstallStates()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.35),
                            Color.accentColor.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 58, height: 58)
                .overlay(
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 26, weight: .medium))
                        .compatForeground(Color.accentColor)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(ipa.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                Text(ipa.bundleID)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .compatibleTextSelection()
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(L("Версия %@", versionText))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow(L("Файл"), value: ipa.fileName)
            detailRow(L("Размер"), value: ByteFormatter.string(ipa.fileSize))
            detailRow(L("Подпись"), value: ipa.signature.title)

            if let profile = ipa.profileName {
                detailRow(L("Профиль"), value: profile)
            }
            if let team = ipa.profileTeam {
                detailRow(L("Команда"), value: team)
            }
            if let expiration = ipa.profileExpiration {
                detailRow(L("Действует до"), value: LDate(expiration), valueColor: ipa.isProfileExpired ? .red : .primary)
            }
            if let includes = ipa.profileIncludesDevice {
                HStack(alignment: .top, spacing: 18) {
                    Text(L("Устройство в профиле"))
                        .foregroundColor(.secondary)
                        .frame(width: 150, alignment: .leading)
                    Label(
                        includes ? L("Да") : L("Нет"),
                        systemImage: includes ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundColor(includes ? .green : .red)
                }
            }
            if !ipa.minimumOSVersion.isEmpty {
                detailRow(L("Минимальная iOS"), value: ipa.minimumOSVersion)
            }
        }
        .font(.callout)
    }

    private func detailRow(_ title: String, value: String, valueColor: Color = .primary) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text(title)
                .foregroundColor(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .foregroundColor(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .compatibleTextSelection()
        }
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .idle:
            EmptyView()

        case .installing(let progress):
            VStack(alignment: .leading, spacing: 7) {
                ProgressView(value: Double(progress.percent) / 100.0)
                HStack {
                    Text(progress.localizedStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(progress.percent)%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

        case .success:
            Label(L("Приложение установлено на устройство"), systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundColor(.green)

        case .failed(let message):
            NoticeCard(
                icon: "xmark.octagon",
                title: L("Установка не удалась"),
                text: message
            )
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            if case .success = state {
                Spacer()
                Button(L("Готово")) {
                    dismiss()
                }
                .compatButtonStyle(.prominent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button(ipa.canInstall ? L("Отмена") : L("Закрыть")) {
                    dismiss()
                }
                .disabled(isInstalling)

                Spacer()

                if isInstalling {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("Установка…"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    Button {
                        Task { await manager.installApp(device: device, ipa: ipa) }
                    } label: {
                        Label(L("Установить"), systemImage: "arrow.down.app")
                    }
                    .compatButtonStyle(.prominent)
                    .disabled(!ipa.canInstall)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var versionText: String {
        let version = ipa.version.isEmpty ? "—" : ipa.version
        let build = ipa.buildVersion.isEmpty ? "—" : ipa.buildVersion
        return "\(version) (\(build))"
    }
}
