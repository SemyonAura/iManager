import SwiftUI
import UniformTypeIdentifiers

struct AppsView: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    let device: Device

    @EnvironmentObject private var manager: DeviceManager
    @State private var showSystemApps = false
    @State private var searchText = ""
    @State private var isImporting = false
    @State private var isInspecting = false
    @State private var importError: String?
    @State private var pendingIPAs: [IPAInfo] = []

    private var allApps: [InstalledApp] {
        manager.installedApps(for: device.id)
    }

    @State private var appToUninstall: InstalledApp?

    private var filteredApps: [InstalledApp] {
        var result = allApps

        if !showSystemApps {
            result = result.filter(\.isUserApp)
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || $0.bundleID.localizedCaseInsensitiveContains(query)
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.isUserApp != rhs.isUserApp {
                return lhs.isUserApp
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var subtitle: String {
        guard !allApps.isEmpty else { return L("Список ещё не загружен") }
        let userCount = allApps.filter(\.isUserApp).count
        return L("Пользовательских: %d, всего: %d", userCount, allApps.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                SectionTitle(title: L("Приложения"), subtitle: subtitle)

                Spacer(minLength: 10)

                if isInspecting {
                    ProgressView()
                        .controlSize(.small)
                        .help(Text(L("Чтение метаданных .ipa")))
                }

                Button {
                    isImporting = true
                } label: {
                    Label(L("Установить .ipa…"), systemImage: "arrow.down.app")
                }
                .controlSize(.small)
                .disabled(
                    manager.pairingState(for: device.id) != .paired
                        || manager.isInstalling(on: device.id)
                        || isInspecting
                )
                .help(Text(L("Установить приложения из одного или нескольких файлов .ipa")))

                Toggle(L("Системные"), isOn: $showSystemApps)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Button {
                    Task { await manager.loadApps(for: device, force: true) }
                } label: {
                    if manager.isLoadingApps(for: device.id) {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(L("Обновить"), systemImage: "arrow.clockwise")
                    }
                }
                .controlSize(.small)
                .disabled(manager.isLoadingApps(for: device.id))
            }

            if manager.pairingState(for: device.id) != .paired {
                PairingSection(device: device)
            } else if manager.isLoadingApps(for: device.id) && allApps.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("Чтение списка приложений через installation_proxy…"))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 24)
            } else if let error = manager.appsError(for: device.id) {
                NoticeCard(
                    icon: "exclamationmark.triangle",
                    title: L("Не удалось получить список"),
                    text: error
                )
            } else if allApps.isEmpty {
                Text(L("На устройстве не найдено приложений."))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
            } else {
                TextField(L("Поиск по названию или bundle ID"), text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Text(L("Показано: %d из %d", filteredApps.count, allApps.count))
                    .font(.caption)
                    .foregroundColor(.secondary)

                LazyVStack(spacing: 0) {
                    ForEach(filteredApps) { app in
                        AppRow(app: app)
                            .contextMenu {
                                Button {
                                    appToUninstall = app
                                } label: {
                                    Label(L("Удалить приложение"), systemImage: "trash")
                                }
                            }
                        if app.id != filteredApps.last?.id {
                            Divider()
                                .padding(.leading, 58)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06))
                )
            }
        }
        .compatibleTask {
            if manager.pairingState(for: device.id) == .paired {
                await manager.loadApps(for: device)
            }
        }
        .background(EmptyView().alert(isPresented: Binding(
            get: { appToUninstall != nil },
            set: { if !$0 { appToUninstall = nil } }
        )) {
            Alert(
                title: Text(L("Удалить приложение?")),
                message: Text(appToUninstall.map { L("Приложение %@ будет полностью удалено с устройства вместе со всеми данными.", $0.bundleID) } ?? ""),
                primaryButton: .destructive(Text(appToUninstall.map { L("Удалить %@", $0.name) } ?? L("Удалить"))) {
                    if let app = appToUninstall {
                        Task {
                            await manager.uninstallApp(device: device, app: app)
                            appToUninstall = nil
                        }
                    }
                },
                secondaryButton: .cancel(Text(L("Отмена"))) { appToUninstall = nil }
            )
        })
        .compatibleOnChange(of: manager.pairingState(for: device.id)) { state in
            if state == .paired {
                Task { await manager.loadApps(for: device) }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
            allowsMultipleSelection: true,
            onCompletion: handleImport
        )
        .sheet(isPresented: Binding(
            get: { !pendingIPAs.isEmpty },
            set: { if !$0 { pendingIPAs = [] } }
        )) {
            InstallBatchView(device: device, ipas: pendingIPAs)
                .environmentObject(manager)
        }
        .alert(isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Alert(
                title: Text(L("Не удалось прочитать .ipa")),
                message: Text(importError ?? ""),
                dismissButton: .cancel(Text("OK")) { importError = nil }
            )
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task { await inspect(urls) }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    @MainActor
    private func inspect(_ urls: [URL]) async {
        isInspecting = true
        defer { isInspecting = false }

        var results: [IPAInfo] = []
        for url in urls {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let info = try await Task.detached(priority: .userInitiated) {
                    try IPAInspector.inspect(path: url.path, deviceUDID: device.udid)
                }.value
                results.append(info)
            } catch {
                print("Failed to inspect \(url.lastPathComponent): \(error)")
            }
        }

        if !results.isEmpty {
            manager.resetInstallStates()
            pendingIPAs = results
        } else if !urls.isEmpty {
            importError = L("Не удалось прочитать выбранные файлы или они не являются корректными .ipa.")
        }
    }
}

private struct AppRow: View {
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(iconColor)
                .frame(width: 34, height: 34)
                .overlay(
                    Text(initials)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Text(app.bundleID)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text(app.version.isEmpty ? "—" : "v\(app.version)")
                .font(.caption)
                .foregroundColor(.secondary)

            if !app.isUserApp {
                Text(app.applicationType)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var iconColor: Color {
        var palette: [Color] = [.blue, .purple, .pink, .orange, .green]
        if #available(macOS 12.0, *) {
            palette.append(.indigo)
            palette.append(.teal)
            palette.append(.cyan)
        }
        let hash = app.bundleID.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) & 0x7fff_ffff
        }
        return palette[hash % palette.count]
    }

    private var initials: String {
        let letters = app.name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}
