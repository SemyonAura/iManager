import SwiftUI

struct InstallIPAView: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    let device: Device
    let ipa: IPAInfo

    @EnvironmentObject private var manager: DeviceManager
    @Environment(\.dismiss) private var dismiss

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
                .foregroundStyle(.secondary)
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
                        .foregroundStyle(Color.accentColor)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(ipa.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                Text(ipa.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(L("Версия %@", versionText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var details: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                Text(L("Файл"))
                    .foregroundStyle(.secondary)
                Text(ipa.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            GridRow {
                Text(L("Размер"))
                    .foregroundStyle(.secondary)
                Text(ByteFormatter.string(ipa.fileSize))
            }

            GridRow {
                Text(L("Подпись"))
                    .foregroundStyle(.secondary)
                Text(ipa.signature.title)
            }

            if let profile = ipa.profileName {
                GridRow {
                    Text(L("Профиль"))
                        .foregroundStyle(.secondary)
                    Text(profile)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let team = ipa.profileTeam {
                GridRow {
                    Text(L("Команда"))
                        .foregroundStyle(.secondary)
                    Text(team)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let expiration = ipa.profileExpiration {
                GridRow {
                    Text(L("Действует до"))
                        .foregroundStyle(.secondary)
                    Text(LDate(expiration))
                        .foregroundStyle(ipa.isProfileExpired ? .red : .primary)
                }
            }

            if let includes = ipa.profileIncludesDevice {
                GridRow {
                    Text(L("Устройство в профиле"))
                        .foregroundStyle(.secondary)
                    Label(
                        includes ? L("Да") : L("Нет"),
                        systemImage: includes ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(includes ? .green : .red)
                }
            }

            if !ipa.minimumOSVersion.isEmpty {
                GridRow {
                    Text(L("Минимальная iOS"))
                        .foregroundStyle(.secondary)
                    Text(ipa.minimumOSVersion)
                }
            }
        }
        .font(.callout)
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
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(progress.percent)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

        case .success:
            Label(L("Приложение установлено на устройство"), systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)

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
                .buttonStyle(.borderedProminent)
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
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        Task { await manager.installApp(device: device, ipa: ipa) }
                    } label: {
                        Label(L("Установить"), systemImage: "arrow.down.app")
                    }
                    .buttonStyle(.borderedProminent)
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
