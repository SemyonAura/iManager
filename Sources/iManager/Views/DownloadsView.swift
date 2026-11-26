import SwiftUI
import AppKit

struct DownloadsView: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    @ObservedObject private var downloads = DownloadManager.shared
    @EnvironmentObject private var manager: DeviceManager

    @State private var pendingInstall: IPAInfo?
    @State private var errorMessage: AlertMessage?

    private var targetDevice: Device? {
        manager.devices.first { $0.id == manager.selectedDeviceID } ?? manager.devices.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if downloads.downloads.isEmpty && downloads.library.isEmpty {
                    emptyState
                } else {
                    if !downloads.activeDownloads.isEmpty {
                        activeSection
                    }

                    if !downloads.failedDownloads.isEmpty {
                        failedSection
                    }

                    librarySection
                }
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle(L("Загрузки"))
        .sheet(item: $pendingInstall) { ipa in
            if let device = targetDevice {
                InstallIPAView(device: device, ipa: ipa)
            }
        }
        .alert(item: $errorMessage) { message in
            Alert(
                title: Text(L("Не удалось открыть пакет")),
                message: Text(message.text),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Заголовок

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L("Загрузки"))
                    .font(.system(size: 30, weight: .bold))

                Text(L("Файлы .ipa сохраняются в %@", downloads.directoryURL.path))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .compatibleTextSelection()
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button {
                    downloads.refreshLibrary()
                } label: {
                    Label(L("Обновить"), systemImage: "arrow.clockwise")
                }
                .help(Text(L("Перечитать папку загрузок")))

                Button {
                    NSWorkspace.shared.open(downloads.directoryURL)
                } label: {
                    Label(L("Открыть папку"), systemImage: "folder")
                }
            }
        }
    }

    // MARK: - Активные загрузки

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(
                title: L("В процессе"),
                subtitle: downloads.isProcessing
                    ? L("Загрузки выполняются последовательно")
                    : nil
            )

            VStack(spacing: 0) {
                ForEach(downloads.activeDownloads) { item in
                    activeRow(item)
                    if item.id != downloads.activeDownloads.last?.id {
                        Divider()
                            .padding(.leading, 72)
                    }
                }
            }
            .background(cardBackground)
        }
    }

    private func activeRow(_ item: AppDownload) -> some View {
        HStack(alignment: .top, spacing: 14) {
            DownloadIcon(name: item.name, iconURL: item.iconURL, phase: item.phase)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    if !item.version.isEmpty {
                        Text("v\(item.version)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 0)

                    Text(percentText(for: item))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                if let progress = item.progress {
                    ProgressView(value: min(max(progress, 0), 1))
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }

                HStack(spacing: 10) {
                    Text(bytesText(for: item))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)

                    if item.speed > 0, item.phase == .downloading {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(L("%@/с", ByteFormatter.string(Int64(item.speed))))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 0)

                    if let message = item.message {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Button(L("Отменить")) {
                downloads.cancel(item)
            }
            .compatButtonStyle(.bordered)
            .controlSize(.small)
            .disabled(item.phase == .queued)
        }
        .padding(14)
    }

    // MARK: - Ошибки

    private var failedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: L("Не удалось скачать"))

            VStack(spacing: 0) {
                ForEach(downloads.failedDownloads) { item in
                    failedRow(item)
                    if item.id != downloads.failedDownloads.last?.id {
                        Divider()
                            .padding(.leading, 72)
                    }
                }
            }
            .background(cardBackground)
        }
    }

    private func failedRow(_ item: AppDownload) -> some View {
        HStack(alignment: .top, spacing: 14) {
            DownloadIcon(name: item.name, iconURL: item.iconURL, phase: item.phase)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    if !item.version.isEmpty {
                        Text("v\(item.version)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Text(item.message ?? (item.phase == .cancelled ? L("Загрузка отменена.") : L("Неизвестная ошибка.")))
                    .font(.caption)
                    .foregroundColor(item.phase == .cancelled ? .secondary : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button(L("Повторить")) {
                    downloads.retry(item)
                }
                .compatButtonStyle(.bordered)
                .controlSize(.small)

                Button {
                    downloads.remove(item)
                } label: {
                    Image(systemName: "xmark")
                }
                .compatButtonStyle(.borderless)
                .help(Text(L("Убрать из списка")))
            }
        }
        .padding(14)
    }

    // MARK: - Библиотека

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(
                    title: L("Скачанные файлы"),
                    subtitle: downloads.library.isEmpty
                        ? L("Готовые .ipa появятся здесь")
                        : LCount(downloads.library.count, ruOne: "файл", ruFew: "файла", ruMany: "файлов", enOne: "file", enMany: "files")
                )

                Spacer(minLength: 0)

                if targetDevice == nil {
                    Label(L("Устройство не подключено"), systemImage: "iphone.slash")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if downloads.library.isEmpty {
                Text(L("После завершения загрузки файл появится в этой папке."))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(downloads.library) { item in
                        libraryRow(item)
                        if item.id != downloads.library.last?.id {
                            Divider()
                                .padding(.leading, 72)
                        }
                    }
                }
                .background(cardBackground)
            }
        }
    }

    private func libraryRow(_ item: DownloadedIPA) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "doc.zipper")
                        .font(.system(size: 19, weight: .medium))
                        .compatForeground(Color.accentColor)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(ByteFormatter.string(item.size)) • \(LDate(item.modifiedAt, dateStyle: .medium, timeStyle: .short))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                prepareInstall(item)
            } label: {
                Label(L("Установить"), systemImage: "arrow.down.app")
            }
            .compatButtonStyle(.bordered)
            .controlSize(.small)
            .disabled(targetDevice == nil)
            .help(targetDevice == nil ? L("Подключите iPhone или iPad по USB") : L("Установить на устройство"))

            Menu {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                } label: {
                    Label(L("Показать в Finder"), systemImage: "folder")
                }

                Button {
                    downloads.deleteLibraryItem(item)
                } label: {
                    Label(L("Удалить файл"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help(Text(L("Действия с файлом")))
        }
        .padding(14)
    }

    // MARK: - Пустое состояние

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 46, weight: .light))
                .compatForeground(Color.accentColor.opacity(0.8))

            Text(L("Пока нет загрузок"))
                .font(.title3.weight(.semibold))

            Text(L("Откройте App Store, найдите приложение или выберите его из своих покупок и нажмите «Скачать». Файл .ipa сохранится в папку iManager."))
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)

            Button {
                manager.selectedDeviceID = "appstore"
            } label: {
                Label(L("Открыть App Store"), systemImage: "bag")
            }
            .compatButtonStyle(.prominent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Вспомогательное

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }

    private func prepareInstall(_ item: DownloadedIPA) {
        guard let device = targetDevice else { return }

        do {
            let ipa = try IPAInspector.inspect(path: item.path, deviceUDID: device.udid)
            pendingInstall = ipa
        } catch {
            errorMessage = AlertMessage(text: error.localizedDescription)
        }
    }

    private func percentText(for item: AppDownload) -> String {
        switch item.phase {
        case .queued:
            return L("В очереди")
        case .preparing:
            return L("Подготовка")
        case .downloading:
            if let progress = item.progress {
                return "\(Int((progress * 100).rounded()))%"
            }
            return L("Загрузка")
        case .failed, .cancelled:
            return ""
        }
    }

    private func bytesText(for item: AppDownload) -> String {
        let downloaded = ByteFormatter.string(item.downloadedBytes)
        if item.totalBytes > 0 {
            return L("%@ из %@", downloaded, ByteFormatter.string(item.totalBytes))
        }
        if item.downloadedBytes > 0 {
            return downloaded
        }
        return item.phase == .queued ? L("Ожидает начала") : L("Получение данных…")
    }
}

private struct AlertMessage: Identifiable {
    let id = UUID()
    let text: String
}

private struct DownloadIcon: View {
    let name: String
    let iconURL: String
    let phase: DownloadPhase

    var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .compatForeground(tint)
            )
    }

    private var symbol: String {
        switch phase {
        case .queued: return "clock"
        case .preparing: return "gearshape"
        case .downloading: return "arrow.down"
        case .failed: return "exclamationmark.triangle"
        case .cancelled: return "xmark"
        }
    }

    private var tint: Color {
        switch phase {
        case .failed: return .orange
        case .cancelled: return .secondary
        default: return .accentColor
        }
    }
}
