import Foundation
import Darwin

// MARK: - Состояние загрузки

enum DownloadPhase: Equatable {
    case queued
    case preparing
    case downloading
    case failed
    case cancelled

    var isActive: Bool {
        switch self {
        case .queued, .preparing, .downloading: return true
        case .failed, .cancelled: return false
        }
    }
}

struct AppDownload: Identifiable, Equatable {
    let id: UUID
    let appID: Int
    let bundleID: String
    let name: String
    let version: String
    let versionID: String?
    let iconURL: String
    let destinationPath: String
    let createdAt: Date

    var phase: DownloadPhase = .queued
    var progress: Double?
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var speed: Double = 0
    var message: String?
    var startedAt: Date?
    var finishedAt: Date?

    var fileName: String {
        (destinationPath as NSString).lastPathComponent
    }
}

struct DownloadedIPA: Identifiable, Equatable {
    var id: String { path }

    let path: String
    let size: Int64
    let modifiedAt: Date

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    var name: String {
        fileName.hasSuffix(".ipa") ? String(fileName.dropLast(4)) : fileName
    }
}

// MARK: - Менеджер загрузок

/// Последовательная очередь загрузок `.ipa` из App Store через `ipatool`.
/// Готовые файлы складываются в `~/Downloads/iManager` и показываются как
/// локальная библиотека — её можно установить на подключённое устройство.
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var downloads: [AppDownload] = []
    @Published private(set) var library: [DownloadedIPA] = []
    @Published private(set) var isProcessing = false

    let directoryURL: URL

    private var worker: Task<Void, Never>?
    private var runner: ProcessRunner?
    private var activeID: UUID?
    private var pollTask: Task<Void, Never>?
    private var cancelled: Set<UUID> = []

    private init() {
        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        directoryURL = base.appendingPathComponent("iManager", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        library = Self.scanLibrary(at: directoryURL)
    }

    // MARK: - Публичное состояние

    @MainActor
    func refreshLibrary() {
        library = Self.scanLibrary(at: directoryURL)
    }

    @MainActor
    func activeDownload(for app: AppStoreApp) -> AppDownload? {
        downloads.first { item in
            item.phase.isActive && Self.matches(item: item, app: app)
        }
    }

    @MainActor
    func download(for app: AppStoreApp) -> AppDownload? {
        downloads.first { Self.matches(item: $0, app: app) }
    }

    @MainActor
    func activeDownload(for app: AppStoreApp, versionID: String?) -> AppDownload? {
        let target = versionID?.isEmpty == false ? versionID : nil
        return downloads.first {
            $0.phase.isActive && $0.versionID == target && Self.matches(item: $0, app: app)
        }
    }

    var activeDownloads: [AppDownload] {
        downloads.filter { $0.phase.isActive }
    }

    var failedDownloads: [AppDownload] {
        downloads.filter { $0.phase == .failed || $0.phase == .cancelled }
    }

    // MARK: - Постановка в очередь

    @MainActor
    func enqueue(app: AppStoreApp, versionID: String? = nil, versionLabel: String? = nil) {
        let targetVersionID = versionID?.isEmpty == false ? versionID : nil

        if downloads.contains(where: {
            $0.phase.isActive && $0.versionID == targetVersionID && Self.matches(item: $0, app: app)
        }) {
            return
        }

        let reserved = Set(downloads.map(\.destinationPath))
        let destination = Self.destinationURL(
            for: app,
            versionLabel: versionLabel,
            versionID: targetVersionID,
            in: directoryURL,
            reserved: reserved
        )

        let item = AppDownload(
            id: UUID(),
            appID: app.id,
            bundleID: app.bundleID,
            name: app.name,
            version: versionLabel ?? app.version,
            versionID: targetVersionID,
            iconURL: app.iconUrl,
            destinationPath: destination.path,
            createdAt: Date()
        )

        downloads.append(item)
        startWorkerIfNeeded()
    }

    // MARK: - Управление

    @MainActor
    func cancel(_ item: AppDownload) {
        guard let index = downloads.firstIndex(where: { $0.id == item.id }) else { return }

        switch downloads[index].phase {
        case .queued:
            downloads[index].phase = .cancelled
            downloads[index].message = L("Загрузка отменена.")
            downloads[index].finishedAt = Date()

        case .preparing, .downloading:
            cancelled.insert(item.id)
            downloads[index].message = L("Остановка…")
            guard activeID == item.id else { return }

            let pid = runner?.processIdentifier ?? 0
            runner?.terminate()

            // Если ipatool не завершился по SIGTERM, через несколько секунд
            // принудительно останавливаем процесс, чтобы очередь не зависла.
            if pid > 0 {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard let self, self.activeID == item.id else { return }
                    kill(pid, SIGKILL)
                }
            }

        case .failed, .cancelled:
            break
        }
    }

    @MainActor
    func cancelAllAndWait(timeout: TimeInterval = 5) async {
        for item in activeDownloads {
            cancel(item)
        }

        // Даём ipatool завершиться: иначе он может сохранить состояние
        // сессии уже после того, как выход очистил его.
        let deadline = Date().addingTimeInterval(timeout)
        while !activeDownloads.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    @MainActor
    func retry(_ item: AppDownload) {
        guard let index = downloads.firstIndex(where: { $0.id == item.id }) else { return }
        guard !downloads[index].phase.isActive else { return }

        cleanupTemporaryFiles(for: downloads[index].destinationPath)

        downloads[index].phase = .queued
        downloads[index].progress = 0
        downloads[index].downloadedBytes = 0
        downloads[index].totalBytes = 0
        downloads[index].speed = 0
        downloads[index].message = nil
        downloads[index].startedAt = nil
        downloads[index].finishedAt = nil

        startWorkerIfNeeded()
    }

    @MainActor
    func remove(_ item: AppDownload) {
        guard !item.phase.isActive else { return }
        downloads.removeAll { $0.id == item.id }
    }

    @MainActor
    func clearFinished() {
        downloads.removeAll { !$0.phase.isActive }
    }

    @MainActor
    func deleteLibraryItem(_ item: DownloadedIPA) {
        let url = URL(fileURLWithPath: item.path)
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            try? FileManager.default.removeItem(at: url)
        }
        refreshLibrary()
    }

    // MARK: - Очередь

    @MainActor
    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        isProcessing = true
        worker = Task { @MainActor [weak self] in
            await self?.processQueue()
            self?.isProcessing = false
            self?.worker = nil
        }
    }

    @MainActor
    private func processQueue() async {
        while !Task.isCancelled {
            guard let item = downloads.first(where: { $0.phase == .queued }) else { return }
            await run(itemID: item.id)
        }
    }

    @MainActor
    private func run(itemID: UUID) async {
        guard let index = downloads.firstIndex(where: { $0.id == itemID }) else { return }

        guard let executable = IPAToolService.shared.executableURL else {
            finishFailure(itemID, message: L("Утилита ipatool не найдена внутри приложения. Пересоберите iManager."))
            return
        }

        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        downloads[index].phase = .preparing
        downloads[index].startedAt = Date()
        downloads[index].progress = 0
        downloads[index].message = L("Подготовка загрузки…")

        let item = downloads[index]
        let runner = ProcessRunner()
        self.runner = runner
        activeID = itemID
        cancelled.remove(itemID)

        var arguments = IPAToolService.shared.downloadArguments(
            appID: item.appID,
            bundleID: item.bundleID,
            destination: item.destinationPath,
            versionID: item.versionID
        )
        arguments.append(contentsOf: IPAToolService.shared.globalArguments)

        do {
            try runner.start(
                executable: executable,
                arguments: arguments,
                environment: IPAToolService.shared.processEnvironment,
                onText: { [weak self] line in
                    guard let self else { return }
                    Task { @MainActor in
                        self.handle(line: line, itemID: itemID)
                    }
                }
            )
        } catch {
            self.runner = nil
            activeID = nil
            finishFailure(
                itemID,
                message: L("Не удалось запустить ipatool: %@", error.localizedDescription)
            )
            return
        }

        startPolling(itemID: itemID, destination: item.destinationPath)

        let status = await runner.wait()
        stopPolling()
        self.runner = nil
        activeID = nil

        let parsed = IPAToolService.parse(runner.collectedOutput())
        let wasCancelled = cancelled.remove(itemID) != nil

        cleanupTemporaryFiles(for: item.destinationPath)

        guard let currentIndex = downloads.firstIndex(where: { $0.id == itemID }) else { return }

        if wasCancelled {
            downloads[currentIndex].phase = .cancelled
            downloads[currentIndex].progress = nil
            downloads[currentIndex].speed = 0
            downloads[currentIndex].message = L("Загрузка отменена.")
            downloads[currentIndex].finishedAt = Date()
            return
        }

        let outputPath = (parsed.outputPath?.isEmpty == false ? parsed.outputPath : nil)
            ?? item.destinationPath

        if status == 0, FileManager.default.fileExists(atPath: outputPath) {
            // Готовый файл переезжает в библиотеку на диске.
            downloads.remove(at: currentIndex)
            refreshLibrary()
            return
        }

        let message: String
        if let error = parsed.errorMessage, !error.isEmpty {
            message = IPAToolService.localizedMessage(error)
        } else if status != 0 {
            message = L("ipatool завершился с кодом %d.", Int(status))
        } else {
            message = L("Файл не появился в папке загрузок. Проверьте вход в Apple ID и повторите попытку.")
        }

        downloads[currentIndex].phase = .failed
        downloads[currentIndex].progress = nil
        downloads[currentIndex].speed = 0
        downloads[currentIndex].message = message
        downloads[currentIndex].finishedAt = Date()
    }

    @MainActor
    private func finishFailure(_ itemID: UUID, message: String) {
        guard let index = downloads.firstIndex(where: { $0.id == itemID }) else { return }
        downloads[index].phase = .failed
        downloads[index].progress = nil
        downloads[index].speed = 0
        downloads[index].message = message
        downloads[index].finishedAt = Date()
    }

    // MARK: - Разбор вывода ipatool

    @MainActor
    private func handle(line: String, itemID: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == itemID }) else { return }

        let clean = Self.strippingANSI(line)
        let trimmed = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // JSON-логи ipatool.
        if trimmed.hasPrefix("{") {
            if let data = trimmed.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = object["error"] as? String,
               !error.isEmpty {
                downloads[index].message = IPAToolService.localizedMessage(error)
            }
            return
        }

        if downloads[index].phase == .preparing {
            downloads[index].phase = .downloading
            downloads[index].message = nil
        }

        // `ipatool-cpp` в неинтерактивном режиме печатает машиночитаемый
        // прогресс: "PROGRESS:42".
        if trimmed.hasPrefix("PROGRESS:") {
            let value = trimmed.dropFirst("PROGRESS:".count)
            if let percent = Double(value.trimmingCharacters(in: .whitespaces)) {
                downloads[index].progress = min(max(percent / 100, 0), 1)
            }
            return
        }

        if let percent = Self.percent(from: clean) {
            downloads[index].progress = min(max(percent / 100, 0), 1)
        }

        if let stats = Self.byteStats(from: clean) {
            if stats.total > 0 {
                downloads[index].totalBytes = stats.total
            }
            if stats.downloaded > 0 {
                downloads[index].downloadedBytes = stats.downloaded
            }
            if stats.speed > 0 {
                downloads[index].speed = stats.speed
            }
        }
    }

    private static func percent(from text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: "(\\d{1,3})\\s*%") else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, options: [], range: range),
            let valueRange = Range(match.range(at: 1), in: text),
            let value = Double(text[valueRange])
        else {
            return nil
        }
        return value
    }

    private struct ByteStats {
        let downloaded: Int64
        let total: Int64
        let speed: Double
    }

    private static func byteStats(from text: String) -> ByteStats? {
        let sizePattern = "([\\d.]+)\\s*([KMGTP]?i?B)\\s*/\\s*([\\d.]+)\\s*([KMGTP]?i?B)"
        guard let regex = try? NSRegularExpression(pattern: sizePattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, options: [], range: range),
            let downloadedRange = Range(match.range(at: 1), in: text),
            let downloadedUnitRange = Range(match.range(at: 2), in: text),
            let totalRange = Range(match.range(at: 3), in: text),
            let totalUnitRange = Range(match.range(at: 4), in: text),
            let downloadedValue = Double(text[downloadedRange]),
            let totalValue = Double(text[totalRange])
        else {
            return nil
        }

        let downloaded = Int64(
            downloadedValue * multiplier(for: String(text[downloadedUnitRange]))
        )
        let total = Int64(totalValue * multiplier(for: String(text[totalUnitRange])))

        var speed: Double = 0
        let speedPattern = "([\\d.]+)\\s*([KMGTP]?i?B)/s"
        if let speedRegex = try? NSRegularExpression(pattern: speedPattern, options: [.caseInsensitive]),
           let speedMatch = speedRegex.firstMatch(in: text, options: [], range: range),
           let valueRange = Range(speedMatch.range(at: 1), in: text),
           let unitRange = Range(speedMatch.range(at: 2), in: text),
           let value = Double(text[valueRange]) {
            speed = value * multiplier(for: String(text[unitRange]))
        }

        return ByteStats(downloaded: downloaded, total: total, speed: speed)
    }

    private static func multiplier(for unit: String) -> Double {
        let normalized = unit.lowercased()
        let base: Double
        switch normalized.first {
        case "k": base = 1_000
        case "m": base = 1_000_000
        case "g": base = 1_000_000_000
        case "t": base = 1_000_000_000_000
        case "p": base = 1_000_000_000_000_000
        default: return 1
        }

        if normalized.contains("i") {
            switch normalized.first {
            case "k": return 1_024
            case "m": return 1_048_576
            case "g": return 1_073_741_824
            case "t": return 1_099_511_627_776
            case "p": return 1_125_899_906_842_624
            default: return 1
            }
        }

        return base
    }

    private static func strippingANSI(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\u{001B}\\[[0-9;]*[a-zA-Z]") else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    // MARK: - Прогресс по файлу

    @MainActor
    private func startPolling(itemID: UUID, destination: String) {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                guard let index = self.downloads.firstIndex(where: { $0.id == itemID }) else { return }
                guard self.downloads[index].phase.isActive else { return }

                let bytes = Self.partialBytes(destination: destination)
                guard bytes > 0 else { continue }

                if bytes > self.downloads[index].downloadedBytes {
                    self.downloads[index].downloadedBytes = bytes
                }
                if self.downloads[index].totalBytes > 0 {
                    self.downloads[index].progress = min(
                        Double(bytes) / Double(self.downloads[index].totalBytes),
                        1
                    )
                }
            }
        }
    }

    @MainActor
    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private static func partialBytes(destination: String) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0

        for path in [destination + ".tmp", destination] {
            if let attributes = try? fm.attributesOfItem(atPath: path),
               let size = attributes[.size] as? NSNumber {
                total += size.int64Value
            }
        }

        let partsPath = destination + ".ipatool-parts"
        if let files = try? fm.contentsOfDirectory(atPath: partsPath) {
            for file in files {
                let path = (partsPath as NSString).appendingPathComponent(file)
                if let attributes = try? fm.attributesOfItem(atPath: path),
                   let size = attributes[.size] as? NSNumber {
                    total += size.int64Value
                }
            }
        }

        return total
    }

    @MainActor
    private func cleanupTemporaryFiles(for destination: String) {
        let fm = FileManager.default
        try? fm.removeItem(atPath: destination + ".tmp")
        try? fm.removeItem(atPath: destination + ".ipatool-parts")
    }

    // MARK: - Вспомогательное

    private static func matches(item: AppDownload, app: AppStoreApp) -> Bool {
        if item.appID > 0, app.id > 0, item.appID == app.id {
            return true
        }
        if !item.bundleID.isEmpty, !app.bundleID.isEmpty {
            return item.bundleID == app.bundleID
        }
        return false
    }

    private static func destinationURL(
        for app: AppStoreApp,
        versionLabel: String?,
        versionID: String?,
        in directory: URL,
        reserved: Set<String>
    ) -> URL {
        var base = app.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            base = app.bundleID.isEmpty ? "App" : app.bundleID
        }

        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        base = base.components(separatedBy: forbidden).joined(separator: "-")
        base = base.replacingOccurrences(of: "\n", with: " ")

        let label = versionLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !label.isEmpty {
            base += " \(label)"
        } else if let versionID, !versionID.isEmpty {
            base += " (v\(versionID))"
        } else if !app.version.isEmpty {
            base += " \(app.version)"
        }

        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(base + ".ipa")
        var counter = 2

        while fm.fileExists(atPath: candidate.path)
            || fm.fileExists(atPath: candidate.path + ".tmp")
            || reserved.contains(candidate.path) {
            candidate = directory.appendingPathComponent("\(base) (\(counter)).ipa")
            counter += 1
        }

        return candidate
    }

    private static func scanLibrary(at directory: URL) -> [DownloadedIPA] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { $0.pathExtension.lowercased() == "ipa" }
            .compactMap { url -> DownloadedIPA? in
                guard let values = try? url.resourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
                ), values.isRegularFile == true else {
                    return nil
                }

                return DownloadedIPA(
                    path: url.path,
                    size: Int64(values.fileSize ?? 0),
                    modifiedAt: values.contentModificationDate ?? .distantPast
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }
}
