import SwiftUI

/// Ограничивает число одновременных запросов метаданных версий: каждый
/// вызов `get-version-metadata` в ipatool-cpp довольно тяжёлый.
private actor MetadataLimiter {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            active = max(0, active - 1)
        }
    }
}

struct VersionPickerView: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    let app: AppStoreApp

    @ObservedObject private var downloads = DownloadManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var versions: [AppStoreVersion] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var didLoad = false

    private static let metadataLimiter = MetadataLimiter(limit: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 560, height: 580)
        .task {
            guard !didLoad else { return }
            didLoad = true
            await loadVersions()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            appIcon

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(app.bundleID.isEmpty ? "ID \(app.id)" : app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let url = URL(string: app.iconUrl), !app.iconUrl.isEmpty {
            AsyncImage(url: url) { image in
                image.resizable()
            } placeholder: {
                placeholderIcon
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        } else {
            placeholderIcon
                .frame(width: 48, height: 48)
        }
    }

    private var placeholderIcon: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Color.secondary.opacity(0.1))
            .overlay(
                Image(systemName: "app.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            )
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 10) {
                ProgressView()
                Text(L("Получаем список версий…"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            VStack(alignment: .leading, spacing: 12) {
                NoticeCard(
                    icon: "exclamationmark.triangle",
                    title: L("Не удалось получить версии"),
                    text: error
                )
                Button(L("Повторить")) {
                    Task { await loadVersions() }
                }
                .controlSize(.small)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if versions.isEmpty {
            Text(L("Для этого приложения нет доступных версий."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach($versions) { $version in
                        VersionRow(
                            app: app,
                            version: $version,
                            limiter: Self.metadataLimiter
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(L("Старые версии могут больше не устанавливаться на iOS."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button(L("Закрыть")) {
                dismiss()
            }

            Button {
                downloads.enqueue(app: app)
                dismiss()
            } label: {
                Label(L("Скачать последнюю"), systemImage: "arrow.down.app")
            }
            .buttonStyle(.borderedProminent)
            .disabled(downloads.activeDownload(for: app, versionID: nil) != nil)
        }
        .padding(16)
    }

    @MainActor
    private func loadVersions() async {
        isLoading = true
        error = nil
        versions = []

        do {
            let ids = try await AppStoreService.shared.versions(for: app)
            versions = ids.map { AppStoreVersion(id: $0) }
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
}

private struct VersionRow: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    let app: AppStoreApp
    @Binding var version: AppStoreVersion
    let limiter: MetadataLimiter

    @ObservedObject private var downloads = DownloadManager.shared

    private var active: AppDownload? {
        downloads.activeDownload(for: app, versionID: version.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(version.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                if version.isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(L("Загружаем сведения…"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if version.failed {
                    Text(L("Не удалось получить сведения"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        if let date = version.releaseDate {
                            Text(LDate(date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let minimumOS = version.minimumOS, !minimumOS.isEmpty {
                            Text("iOS \(minimumOS)+")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if active != nil {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("В очереди"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    downloads.enqueue(
                        app: app,
                        versionID: version.id,
                        versionLabel: version.displayVersion.isEmpty ? nil : version.displayVersion
                    )
                } label: {
                    Label(L("Скачать"), systemImage: "arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
        .task {
            await loadMetadataIfNeeded()
        }
    }

    @MainActor
    private func loadMetadataIfNeeded() async {
        guard version.displayVersion.isEmpty, !version.isLoading, !version.failed else { return }

        version.isLoading = true
        await limiter.acquire()

        do {
            let metadata = try await AppStoreService.shared.versionMetadata(
                for: app,
                versionID: version.id
            )
            version.displayVersion = metadata.displayVersion
            version.releaseDate = AppStoreService.parseDate(metadata.releaseDate)
            version.minimumOS = metadata.minimumOSVersion
            version.failed = false
        } catch {
            version.failed = true
        }

        version.isLoading = false
        await limiter.release()
    }
}
