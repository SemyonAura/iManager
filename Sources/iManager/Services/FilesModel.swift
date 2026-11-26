import Foundation

/// Модель проводника AFC: держит одно соединение с сервисом `com.apple.afc`,
/// сериализует все операции и публикует состояние в UI.
final class FilesModel: ObservableObject {
    let deviceID: String

    @Published private(set) var currentPath: String = "/"
    @Published private(set) var files: [RemoteFile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isTransferring = false
    @Published private(set) var transferText: String?
    @Published private(set) var transferProgress: Double?
    @Published private(set) var errorMessage: String?

    private let queue = DispatchQueue(label: "com.aura.imanager.afc")
    private var connection: AFCConnection?
    private var loadGeneration = 0

    init(deviceID: String) {
        self.deviceID = deviceID
    }

    deinit {
        connection?.close()
    }

    // MARK: - Навигация

    var subtitle: String {
        if isLoading { return L("Чтение папки…") }
        let folders = files.filter(\.isDirectory).count
        let filesCount = files.count - folders
        if files.isEmpty { return L("Папка пуста") }
        return L("Папок: %d, файлов: %d", folders, filesCount)
    }

    var parentPath: String? {
        guard currentPath != "/" else { return nil }
        let parent = (currentPath as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    func loadInitial() {
        guard files.isEmpty else { return }
        open("/")
    }

    func open(_ path: String) {
        let normalized = Self.normalize(path)
        loadGeneration += 1
        let generation = loadGeneration

        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }

        perform({ connection in
            try connection.listDirectory(path: normalized)
        }, completion: { result in
            guard generation == self.loadGeneration else { return }
            self.isLoading = false
            switch result {
            case .success(let files):
                self.currentPath = normalized
                self.files = files
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        })
    }

    func refresh() {
        open(currentPath)
    }

    func goUp() {
        if let parentPath {
            open(parentPath)
        }
    }

    // MARK: - Скачивание

    func download(_ file: RemoteFile, to url: URL) {
        guard !file.isDirectory else { return }
        startTransfer(text: L("Скачивание «%@»", file.name))

        let expected = file.size
        let progress: (Int64) -> Void = { [weak self] written in
            guard let self else { return }
            DispatchQueue.main.async {
                if expected > 0 {
                    self.transferProgress = min(1, Double(written) / Double(expected))
                }
                self.transferText = L("Скачивание «%@»: %@", file.name, ByteFormatter.string(written))
            }
        }

        perform({ connection in
            try connection.download(path: file.path, to: url.path, progress: progress)
        }, completion: { result in
            switch result {
            case .success(let bytes):
                self.finishTransfer(L("Скачано: %@ (%@)", file.name, ByteFormatter.string(bytes)))
            case .failure(let error):
                self.failTransfer(error)
            }
        })
    }

    // MARK: - Скачивание папки

    func downloadFolder(_ folder: RemoteFile, to url: URL) {
        guard folder.isDirectory else { return }
        startTransfer(text: L("Скачивание папки «%@»", folder.name))

        perform({ connection in
            var fileCount = 0
            var byteCount: Int64 = 0
            var currentName = folder.name

            func copyDirectory(remote: String, local: URL) throws {
                try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
                let items = try connection.listDirectory(path: remote)
                for item in items {
                    if item.isSymlink { continue }
                    let target = local.appendingPathComponent(item.name)
                    if item.isDirectory {
                        try copyDirectory(remote: item.path, local: target)
                    } else {
                        currentName = item.name
                        DispatchQueue.main.async {
                            self.transferText = L("Скачивание «%@»", currentName)
                        }
                        byteCount += try connection.download(path: item.path, to: target.path) { written in
                            DispatchQueue.main.async {
                                self.transferProgress = nil
                                self.transferText = L("Скачивание «%@»: %@", currentName, ByteFormatter.string(written))
                            }
                        }
                        fileCount += 1
                    }
                }
            }

            try copyDirectory(remote: folder.path, local: url)
            return (fileCount, byteCount)
        }, completion: { result in
            switch result {
            case .success(let summary):
                self.finishTransfer(L("Скачано файлов: %d (%@)", summary.0, ByteFormatter.string(summary.1)))
            case .failure(let error):
                self.failTransfer(error)
            }
        })
    }

    // MARK: - Загрузка

    func upload(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let destinationDirectory = currentPath
        startTransfer(text: urls.count == 1
            ? L("Загрузка «%@»", urls[0].lastPathComponent)
            : L("Загрузка файлов: %d", urls.count))

        perform({ connection in
            for url in urls {
                let remotePath = AFCConnection.join(destinationDirectory, url.lastPathComponent)
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let expected = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
                let name = url.lastPathComponent

                _ = try connection.upload(localPath: url.path, to: remotePath, progress: { written in
                    DispatchQueue.main.async {
                        if expected > 0 {
                            self.transferProgress = min(1, Double(written) / Double(expected))
                        }
                        self.transferText = L("Загрузка «%@»: %@", name, ByteFormatter.string(written))
                    }
                })
            }
        }, completion: { result in
            switch result {
            case .success:
                self.finishTransfer(urls.count == 1
                    ? L("Загружено: %@", urls[0].lastPathComponent)
                    : L("Загружено файлов: %d", urls.count))
                self.reloadAfterMutation()
            case .failure(let error):
                self.failTransfer(error)
            }
        })
    }

    // MARK: - Операции с файловой системой

    func createFolder(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else {
            DispatchQueue.main.async { self.errorMessage = L("Недопустимое имя папки.") }
            return
        }

        let directory = currentPath
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }

        perform({ connection in
            try connection.createDirectory(path: AFCConnection.join(directory, name))
        }, completion: { result in
            self.isLoading = false
            switch result {
            case .success:
                self.finishTransfer(L("Создана папка: %@", name))
                self.reloadAfterMutation()
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        })
    }

    func delete(_ file: RemoteFile) {
        let target = file
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }

        perform({ connection in
            try connection.remove(path: target.path, recursive: true)
        }, completion: { result in
            self.isLoading = false
            switch result {
            case .success:
                self.finishTransfer(L("Удалено: %@", target.name))
                self.reloadAfterMutation()
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        })
    }

    func rename(_ file: RemoteFile, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else {
            DispatchQueue.main.async { self.errorMessage = L("Недопустимое имя файла.") }
            return
        }
        guard name != file.name else { return }

        let target = file
        let destination = AFCConnection.join((file.path as NSString).deletingLastPathComponent, name)

        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }

        perform({ connection in
            try connection.rename(from: target.path, to: destination)
        }, completion: { result in
            self.isLoading = false
            switch result {
            case .success:
                self.finishTransfer(L("Переименовано: %@ → %@", target.name, name))
                self.reloadAfterMutation()
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        })
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Внутреннее

    private func reloadAfterMutation() {
        open(currentPath)
    }

    private func startTransfer(text: String) {
        DispatchQueue.main.async {
            self.isTransferring = true
            self.transferProgress = nil
            self.transferText = text
            self.errorMessage = nil
        }
    }

    private func finishTransfer(_ text: String) {
        DispatchQueue.main.async {
            self.isTransferring = false
            self.transferProgress = nil
            self.transferText = text
        }
    }

    private func failTransfer(_ error: Error) {
        DispatchQueue.main.async {
            self.isTransferring = false
            self.transferProgress = nil
            self.transferText = nil
            self.errorMessage = error.localizedDescription
        }
    }

    /// Выполняет операцию на выделенной последовательной очереди. Соединение
    /// открывается лениво и пересоздаётся после любой ошибки.
    private func perform<T>(
        _ body: @escaping (AFCConnection) throws -> T,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        queue.async {
            do {
                if self.connection == nil {
                    let handle = try MobileDeviceBridge.shared.startAFCService(identifier: self.deviceID)
                    self.connection = try AFCConnection(serviceHandle: handle)
                }
                guard let connection = self.connection else {
                    throw AFCError.unavailable(L("соединение не открыто"))
                }
                let value: T
                do {
                    value = try body(connection)
                } catch {
                    self.closeConnectionLocked()
                    throw error
                }
                DispatchQueue.main.async { completion(.success(value)) }
            } catch {
                self.closeConnectionLocked()
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func closeConnectionLocked() {
        connection?.close()
        connection = nil
    }

    private static func normalize(_ path: String) -> String {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { value = "/" }
        if !value.hasPrefix("/") { value = "/" + value }
        while value.count > 1 && value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
