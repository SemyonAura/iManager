import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FilesView: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    let device: Device

    @StateObject private var model: FilesModel
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var fileToRename: RemoteFile?
    @State private var renameText = ""
    @State private var fileToDelete: RemoteFile?
    @State private var isDropTarget = false

    private let quickPaths: [(title: String, path: String, icon: String)] = [
        (L("Корень"), "/", "iphone"),
        ("DCIM", "/DCIM", "photo.on.rectangle"),
        ("Books", "/Books", "books.vertical"),
        ("Downloads", "/Downloads", "arrow.down.circle"),
        ("PublicStaging", "/PublicStaging", "tray.and.arrow.down")
    ]

    init(device: Device) {
        self.device = device
        _model = StateObject(wrappedValue: FilesModel(deviceID: device.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            pathBar
            quickAccess

            if model.isTransferring {
                transferBanner
            } else if let text = model.transferText {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(text)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let error = model.errorMessage {
                errorBanner(error)
            }

            fileList

            Text(L("Корень проводника — общий каталог Media на устройстве. Файлы приложений доступны через их контейнеры."))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .onAppear { model.loadInitial() }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            SectionTitle(title: L("Файлы"), subtitle: model.subtitle)

            Spacer(minLength: 10)

            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .help(Text(L("Чтение папки")))
            }

            Button {
                chooseFilesToUpload()
            } label: {
                Label(L("Загрузить файлы…"), systemImage: "square.and.arrow.up")
            }
            .controlSize(.small)
            .disabled(model.isTransferring)
            .help(Text(L("Скопировать файлы с Mac в текущую папку на устройстве")))

            Button {
                newFolderName = ""
                showNewFolder = true
            } label: {
                Label(L("Новая папка"), systemImage: "folder.badge.plus")
            }
            .controlSize(.small)
            .disabled(model.isTransferring)

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
            .help(Text(L("Обновить содержимое папки")))
        }
        .alert(L("Новая папка"), isPresented: $showNewFolder) {
            TextField(L("Имя папки"), text: $newFolderName)
            Button(L("Создать")) {
                model.createFolder(named: newFolderName)
            }
            Button(L("Отмена"), role: .cancel) {}
        } message: {
            Text(L("Папка будет создана в %@", model.currentPath))
        }
    }

    // MARK: - Путь

    private var pathBar: some View {
        HStack(spacing: 6) {
            Button {
                model.goUp()
            } label: {
                Image(systemName: "arrow.up")
            }
            .compatButtonStyle(.borderless)
            .disabled(model.parentPath == nil)
            .help(Text(L("На уровень выше")))

            Button {
                model.open("/")
            } label: {
                Image(systemName: "iphone")
            }
            .compatButtonStyle(.borderless)
            .help(Text(L("Корень Media")))

            ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, name in
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)

                Button(name) {
                    model.open(path(upTo: index))
                }
                .compatButtonStyle(.plain)
                .font(.callout)
                .foregroundColor(index == pathComponents.count - 1 ? .primary : .secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
        .alert(
            L("Переименовать «%@»", fileToRename?.name ?? ""),
            isPresented: Binding(
                get: { fileToRename != nil },
                set: { if !$0 { fileToRename = nil } }
            )
        ) {
            TextField(L("Новое имя"), text: $renameText)
            Button(L("Переименовать")) {
                if let file = fileToRename {
                    model.rename(file, to: renameText)
                }
                fileToRename = nil
            }
            Button(L("Отмена"), role: .cancel) {
                fileToRename = nil
            }
        }
    }

    private var pathComponents: [String] {
        model.currentPath.split(separator: "/").map(String.init)
    }

    private func path(upTo index: Int) -> String {
        "/" + pathComponents.prefix(index + 1).joined(separator: "/")
    }

    // MARK: - Быстрый доступ

    private var quickAccess: some View {
        HStack(spacing: 8) {
            ForEach(quickPaths, id: \.path) { item in
                Button {
                    model.open(item.path)
                } label: {
                    Label(item.title, systemImage: item.icon)
                        .font(.caption)
                }
                .compatButtonStyle(.bordered)
                .controlSize(.small)
                .tint(model.currentPath == item.path ? Color.accentColor : Color.secondary)
                .disabled(model.isTransferring)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Список файлов

    private var fileList: some View {
        VStack(spacing: 0) {
            if model.files.isEmpty {
                VStack(spacing: 8) {
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                        Text(L("Чтение папки…"))
                            .font(.callout)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "folder")
                            .font(.system(size: 26, weight: .light))
                            .foregroundColor(.secondary)
                        Text(L("Папка пуста"))
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(model.files) { file in
                        RemoteFileRow(
                            file: file,
                            onOpen: { model.open(file.path) },
                            onDownload: { download(file) },
                            onDownloadFolder: { downloadFolder(file) },
                            onRename: {
                                renameText = file.name
                                fileToRename = file
                            },
                            onDelete: { fileToDelete = file }
                        )

                        if file.id != model.files.last?.id {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isDropTarget ? Color.accentColor : Color.primary.opacity(0.06),
                    lineWidth: isDropTarget ? 2 : 1
                )
        )
        .overlay {
            if isDropTarget {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 24, weight: .light))
                    Text(L("Отпустите файлы, чтобы загрузить их в %@", model.currentPath))
                        .font(.caption)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.windowBackgroundColor).opacity(0.9))
                )
                .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: [UTType.fileURL],
            isTargeted: $isDropTarget,
            perform: handleDrop
        )
        .alert(
            L("Удалить «%@»?", fileToDelete?.name ?? ""),
            isPresented: Binding(
                get: { fileToDelete != nil },
                set: { if !$0 { fileToDelete = nil } }
            ),
            presenting: fileToDelete
        ) { file in
            Button(L("Удалить"), role: .destructive) {
                model.delete(file)
                fileToDelete = nil
            }
            Button(L("Отмена"), role: .cancel) {
                fileToDelete = nil
            }
        } message: { file in
            Text(file.isDirectory
                ? L("Папка будет удалена со всем содержимым. Действие необратимо.")
                : L("Файл будет удалён с устройства. Действие необратимо."))
        }
    }

    // MARK: - Баннеры

    private var transferBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(model.transferText ?? L("Передача файла…"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let progress = model.transferProgress {
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            if let progress = model.transferProgress {
                ProgressView(value: min(max(progress, 0), 1))
                    .progressViewStyle(.linear)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            NoticeCard(
                icon: "exclamationmark.triangle",
                title: L("Не удалось выполнить операцию"),
                text: text
            )

            Button {
                model.dismissError()
            } label: {
                Image(systemName: "xmark")
            }
            .compatButtonStyle(.borderless)
            .help(Text(L("Скрыть сообщение")))
        }
    }

    // MARK: - Действия

    private func download(_ file: RemoteFile) {
        let panel = NSSavePanel()
        panel.title = L("Скачать файл с устройства")
        panel.nameFieldStringValue = file.name
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloads
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.download(file, to: url)
    }

    private func chooseFilesToUpload() {
        let panel = NSOpenPanel()
        panel.title = L("Загрузить файлы на устройство")
        panel.message = L("Файлы будут скопированы в %@", model.currentPath)
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloads
        }
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        model.upload(panel.urls)
    }

    private func downloadFolder(_ folder: RemoteFile) {
        let panel = NSOpenPanel()
        panel.title = L("Скачать папку «%@»", folder.name)
        panel.message = L("Выберите папку на Mac, куда сохранить содержимое.")
        panel.prompt = L("Скачать сюда")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloads
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let destination = url.appendingPathComponent(folder.name, isDirectory: true)
        model.downloadFolder(folder, to: destination)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        let lock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let nsURL = item as? NSURL {
                    url = nsURL as URL
                } else if let direct = item as? URL {
                    url = direct
                }
                guard let url else { return }
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            let files = urls.filter { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? url.hasDirectoryPath
                return !isDirectory
            }
            if !files.isEmpty {
                model.upload(files)
            }
        }
        return true
    }
}

// MARK: - Строка файла

private struct RemoteFileRow: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    let file: RemoteFile
    let onOpen: () -> Void
    let onDownload: () -> Void
    let onDownloadFolder: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.icon)
                .font(.system(size: 15))
                .foregroundColor(file.isDirectory ? .accentColor : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            if isHovering {
                if !file.isDirectory {
                    Button(action: onDownload) {
                        Image(systemName: "arrow.down.circle")
                    }
                    .compatButtonStyle(.borderless)
                    .help(Text(L("Скачать на Mac")))
                }

                Menu {
                    if file.isDirectory {
                        Button(L("Открыть"), action: onOpen)
                        Button(L("Скачать папку…"), action: onDownloadFolder)
                    } else {
                        Button(L("Скачать…"), action: onDownload)
                    }
                    Button(L("Переименовать…"), action: onRename)
                    Divider()
                    Button(L("Удалить…"), role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isHovering ? Color.primary.opacity(0.04) : Color.clear)
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) {
            if !file.isDirectory { onDownload() }
        }
        .onTapGesture {
            if file.isDirectory { onOpen() }
        }
        .contextMenu {
            if file.isDirectory {
                Button(L("Открыть"), action: onOpen)
                Button(L("Скачать папку…"), action: onDownloadFolder)
            } else {
                Button(L("Скачать…"), action: onDownload)
            }
            Button(L("Переименовать…"), action: onRename)
            Divider()
            Button(L("Удалить…"), role: .destructive, action: onDelete)
        }
        .help(file.path)
    }

    private var detail: String {
        if file.isDirectory { return L("Папка") }
        if file.isSymlink { return L("Символическая ссылка") }

        var parts: [String] = []
        if file.size > 0 {
            parts.append(ByteFormatter.string(file.size))
        } else {
            parts.append(L("0 байт"))
        }
        if let modified = file.modified {
            parts.append(Self.dateFormatter.string(from: modified))
        }
        return parts.joined(separator: " • ")
    }
}
