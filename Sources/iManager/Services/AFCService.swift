import Foundation
import Darwin

// MARK: - Удалённый файл

struct RemoteFile: Identifiable, Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
    let isSymlink: Bool
    let size: Int64
    let modified: Date?

    var id: String { path }

    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    var icon: String {
        if isDirectory { return "folder.fill" }
        if isSymlink { return "link" }
        switch fileExtension {
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp":
            return "photo"
        case "mov", "mp4", "m4v", "avi", "mkv":
            return "film"
        case "mp3", "m4a", "aac", "wav", "flac", "caf":
            return "music.note"
        case "pdf":
            return "doc.richtext"
        case "zip", "ipa", "pkg", "tar", "gz":
            return "archivebox"
        case "txt", "md", "rtf", "json", "xml", "plist":
            return "doc.text"
        case "sqlite", "db", "realm":
            return "cylinder.split.1x2"
        default:
            return "doc"
        }
    }
}

// MARK: - Ошибки AFC

enum AFCError: LocalizedError {
    case unavailable(String)
    case failed(operation: String, code: UInt32)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let detail):
            return L("AFC недоступен: %@", detail)
        case .failed(let operation, let code):
            return L("%@: %@ (код %d)", operation, AFCError.message(for: code), Int(code))
        case .invalidResponse(let detail):
            return L("Некорректный ответ AFC: %@", detail)
        }
    }

    static func message(for code: UInt32) -> String {
        switch code {
        case 0: return L("успешно")
        case 1: return L("неизвестная ошибка")
        case 2: return L("некорректный заголовок пакета")
        case 3: return L("недостаточно ресурсов")
        case 4: return L("ошибка чтения")
        case 5: return L("ошибка записи")
        case 6: return L("неизвестный тип пакета")
        case 7: return L("некорректный аргумент")
        case 8: return L("файл или папка не найдены")
        case 9: return L("это папка")
        case 10: return L("доступ запрещён")
        case 11: return L("сервис не подключён")
        case 12: return L("тайм-аут операции")
        case 13: return L("слишком много данных")
        case 14: return L("конец данных")
        case 15: return L("операция не поддерживается")
        case 16: return L("объект уже существует")
        case 17: return L("объект занят")
        case 18: return L("недостаточно свободного места")
        case 19: return L("операция заблокирована")
        case 20: return L("ошибка ввода-вывода")
        case 21: return L("операция прервана")
        case 22: return L("операция выполняется")
        case 23: return L("внутренняя ошибка")
        case 30: return L("ошибка мультиплексирования")
        case 31: return L("недостаточно памяти")
        case 32: return L("недостаточно данных")
        case 33: return L("папка не пуста")
        case 34: return L("ошибка SSL")
        default: return L("ошибка AFC")
        }
    }
}

// MARK: - Клиент AFC

/// Обёртка над приватным AFC API из MobileDevice.framework.
/// Один экземпляр соответствует одному открытому сервису `com.apple.afc`.
final class AFCConnection {
    private typealias ConnectionOpenFn = @convention(c) (UInt32, UInt32, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UInt32
    private typealias ConnectionCloseFn = @convention(c) (UnsafeMutableRawPointer?) -> UInt32
    private typealias DirectoryOpenFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UInt32
    private typealias DirectoryReadFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> UInt32
    private typealias DirectoryCloseFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> UInt32
    private typealias DirectoryCreateFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UInt32
    private typealias RemovePathFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UInt32
    private typealias RenamePathFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UInt32
    private typealias FileOpenFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UInt64, UnsafeMutablePointer<UInt64>?) -> UInt32
    private typealias FileReadFn = @convention(c) (UnsafeMutableRawPointer?, UInt64, UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?) -> UInt32
    private typealias FileWriteFn = @convention(c) (UnsafeMutableRawPointer?, UInt64, UnsafeRawPointer?, UInt32) -> UInt32
    private typealias FileCloseFn = @convention(c) (UnsafeMutableRawPointer?, UInt64) -> UInt32
    private typealias FileInfoOpenFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> UInt32
    private typealias KeyValueReadFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> UInt32
    private typealias KeyValueCloseFn = @convention(c) (UnsafeMutableRawPointer?) -> UInt32

    private let connectionClose: ConnectionCloseFn?
    private let directoryOpen: DirectoryOpenFn?
    private let directoryRead: DirectoryReadFn?
    private let directoryClose: DirectoryCloseFn?
    private let directoryCreate: DirectoryCreateFn?
    private let removePath: RemovePathFn?
    private let renamePath: RenamePathFn?
    private let fileOpen: FileOpenFn?
    private let fileRead: FileReadFn?
    private let fileWrite: FileWriteFn?
    private let fileClose: FileCloseFn?
    private let fileInfoOpen: FileInfoOpenFn?
    private let keyValueRead: KeyValueReadFn?
    private let keyValueClose: KeyValueCloseFn?

    private let conn: UnsafeMutableRawPointer
    private let lock = NSLock()
    private var isClosed = false

    let serviceHandle: UInt32

    init(serviceHandle: UInt32) throws {
        let path = "/System/Library/PrivateFrameworks/MobileDevice.framework/Versions/A/MobileDevice"
        guard let handle = dlopen(path, RTLD_NOW) else {
            throw AFCError.unavailable(L("не удалось загрузить MobileDevice.framework"))
        }

        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }

        guard let connectionOpen = load("AFCConnectionOpen", as: ConnectionOpenFn.self) else {
            throw AFCError.unavailable("AFCConnectionOpen")
        }
        connectionClose = load("AFCConnectionClose", as: ConnectionCloseFn.self)
        directoryOpen = load("AFCDirectoryOpen", as: DirectoryOpenFn.self)
        directoryRead = load("AFCDirectoryRead", as: DirectoryReadFn.self)
        directoryClose = load("AFCDirectoryClose", as: DirectoryCloseFn.self)
        directoryCreate = load("AFCDirectoryCreate", as: DirectoryCreateFn.self)
        removePath = load("AFCRemovePath", as: RemovePathFn.self)
        renamePath = load("AFCRenamePath", as: RenamePathFn.self)
        fileOpen = load("AFCFileRefOpen", as: FileOpenFn.self)
        fileRead = load("AFCFileRefRead", as: FileReadFn.self)
        fileWrite = load("AFCFileRefWrite", as: FileWriteFn.self)
        fileClose = load("AFCFileRefClose", as: FileCloseFn.self)
        fileInfoOpen = load("AFCFileInfoOpen", as: FileInfoOpenFn.self)
        keyValueRead = load("AFCKeyValueRead", as: KeyValueReadFn.self)
        keyValueClose = load("AFCKeyValueClose", as: KeyValueCloseFn.self)

        var connection: UnsafeMutableRawPointer?
        let result = connectionOpen(serviceHandle, 0, &connection)
        guard result == 0, let connection else {
            throw AFCError.failed(operation: "AFCConnectionOpen", code: result)
        }

        self.serviceHandle = serviceHandle
        conn = connection
    }

    deinit {
        close()
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        isClosed = true
        _ = connectionClose?(conn)
        _ = Darwin.close(Int32(serviceHandle))
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        isClosed = true
        _ = connectionClose?(conn)
        _ = Darwin.close(Int32(serviceHandle))
    }

    // MARK: - Список файлов

    func listDirectory(path: String) throws -> [RemoteFile] {
        lock.lock()
        defer { lock.unlock() }
        try ensureOpen()

        guard let directoryOpen, let directoryRead, let directoryClose else {
            throw AFCError.unavailable("AFCDirectoryOpen / AFCDirectoryRead")
        }

        var directory: UnsafeMutableRawPointer?
        let openResult = path.withCString { directoryOpen(conn, $0, &directory) }
        guard openResult == 0, let directory else {
            throw AFCError.failed(operation: "AFCDirectoryOpen(\(path))", code: openResult)
        }

        var names: [String] = []
        defer { _ = directoryClose(conn, directory) }

        while true {
            var namePointer: UnsafeMutablePointer<CChar>?
            let result = directoryRead(conn, directory, &namePointer)
            guard result == 0 else {
                throw AFCError.failed(operation: "AFCDirectoryRead(\(path))", code: result)
            }
            guard let namePointer else { break }
            let name = String(cString: namePointer)
            if name == "." || name == ".." || name.isEmpty { continue }
            names.append(name)
        }

        var files: [RemoteFile] = []
        files.reserveCapacity(names.count)

        for name in names {
            let childPath = Self.join(path, name)
            let info = (try? fileInfoLocked(path: childPath)) ?? [:]
            let ifmt = info["st_ifmt"] ?? ""
            let isDirectory = ifmt == "S_IFDIR"
            let isSymlink = ifmt == "S_IFLNK"
            let size = Int64(info["st_size"] ?? "") ?? 0
            let modified = AFCConnection.date(from: info["st_mtime"])

            files.append(RemoteFile(
                name: name,
                path: childPath,
                isDirectory: isDirectory,
                isSymlink: isSymlink,
                size: size,
                modified: modified
            ))
        }

        return files.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func fileInfo(path: String) throws -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        try ensureOpen()
        return try fileInfoLocked(path: path)
    }

    private func fileInfoLocked(path: String) throws -> [String: String] {
        guard let fileInfoOpen, let keyValueRead, let keyValueClose else {
            throw AFCError.unavailable("AFCFileInfoOpen / AFCKeyValueRead")
        }

        var dictionary: UnsafeMutableRawPointer?
        let openResult = path.withCString { fileInfoOpen(conn, $0, &dictionary) }
        guard openResult == 0, let dictionary else {
            throw AFCError.failed(operation: "AFCFileInfoOpen(\(path))", code: openResult)
        }
        defer { _ = keyValueClose(dictionary) }

        var info: [String: String] = [:]
        while true {
            var keyPointer: UnsafeMutablePointer<CChar>?
            var valuePointer: UnsafeMutablePointer<CChar>?
            let result = keyValueRead(dictionary, &keyPointer, &valuePointer)
            guard result == 0 else {
                throw AFCError.failed(operation: "AFCKeyValueRead(\(path))", code: result)
            }
            guard let keyPointer else { break }
            let key = String(cString: keyPointer)
            let value = valuePointer.map { String(cString: $0) } ?? ""
            info[key] = value
        }
        return info
    }

    // MARK: - Чтение и запись

    func download(path: String, to destination: String, progress: ((Int64) -> Void)? = nil) throws -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        try ensureOpen()

        guard let fileOpen, let fileRead, let fileClose else {
            throw AFCError.unavailable("AFCFileRefOpen / AFCFileRefRead")
        }

        var fileRef: UInt64 = 0
        let openResult = path.withCString { fileOpen(conn, $0, 1, &fileRef) }
        guard openResult == 0, fileRef != 0 else {
            throw AFCError.failed(operation: "AFCFileRefOpen(\(path))", code: openResult)
        }
        defer { _ = fileClose(conn, fileRef) }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination) {
            try? fileManager.removeItem(atPath: destination)
        }
        guard fileManager.createFile(atPath: destination, contents: nil) else {
            throw AFCError.unavailable(L("не удалось создать файл %@", destination))
        }

        let output = try FileHandle(forWritingTo: URL(fileURLWithPath: destination))
        defer { try? output.close() }

        let bufferSize = 1 << 20
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var total: Int64 = 0

        while true {
            var length = UInt32(bufferSize)
            let readResult = buffer.withUnsafeMutableBytes { rawBuffer in
                fileRead(conn, fileRef, rawBuffer.baseAddress, &length)
            }
            guard readResult == 0 else {
                throw AFCError.failed(operation: "AFCFileRefRead(\(path))", code: readResult)
            }
            if length == 0 { break }

            output.write(Data(bytes: buffer, count: Int(length)))
            total += Int64(length)
            progress?(total)
        }

        return total
    }

    func upload(localPath: String, to remotePath: String, progress: ((Int64) -> Void)? = nil) throws -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        try ensureOpen()

        guard let fileOpen, let fileWrite, let fileClose else {
            throw AFCError.unavailable("AFCFileRefOpen / AFCFileRefWrite")
        }

        var fileRef: UInt64 = 0
        let openResult = remotePath.withCString { fileOpen(conn, $0, 3, &fileRef) }
        guard openResult == 0, fileRef != 0 else {
            throw AFCError.failed(operation: "AFCFileRefOpen(\(remotePath))", code: openResult)
        }
        defer { _ = fileClose(conn, fileRef) }

        let input = try FileHandle(forReadingFrom: URL(fileURLWithPath: localPath))
        defer { try? input.close() }

        var total: Int64 = 0
        while let data = try input.read(upToCount: 1 << 20), !data.isEmpty {
            let writeResult = data.withUnsafeBytes { rawBuffer in
                fileWrite(conn, fileRef, rawBuffer.baseAddress, UInt32(data.count))
            }
            guard writeResult == 0 else {
                throw AFCError.failed(operation: "AFCFileRefWrite(\(remotePath))", code: writeResult)
            }
            total += Int64(data.count)
            progress?(total)
        }

        return total
    }

    // MARK: - Операции с файловой системой

    func createDirectory(path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureOpen()
        guard let directoryCreate else {
            throw AFCError.unavailable("AFCDirectoryCreate")
        }
        let result = path.withCString { directoryCreate(conn, $0) }
        guard result == 0 else {
            throw AFCError.failed(operation: "AFCDirectoryCreate(\(path))", code: result)
        }
    }

    func remove(path: String, recursive: Bool = false) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureOpen()
        try removeLocked(path: path, recursive: recursive)
    }

    private func removeLocked(path: String, recursive: Bool) throws {
        guard let removePath else {
            throw AFCError.unavailable("AFCRemovePath")
        }

        if recursive, let info = try? fileInfoLocked(path: path), info["st_ifmt"] == "S_IFDIR" {
            if let directoryOpen, let directoryRead, let directoryClose {
                var directory: UnsafeMutableRawPointer?
                let openResult = path.withCString { directoryOpen(conn, $0, &directory) }
                if openResult == 0, let directory {
                    var names: [String] = []
                    while true {
                        var namePointer: UnsafeMutablePointer<CChar>?
                        let result = directoryRead(conn, directory, &namePointer)
                        guard result == 0 else { break }
                        guard let namePointer else { break }
                        let name = String(cString: namePointer)
                        if name == "." || name == ".." || name.isEmpty { continue }
                        names.append(name)
                    }
                    _ = directoryClose(conn, directory)

                    for name in names {
                        try removeLocked(path: Self.join(path, name), recursive: true)
                    }
                }
            }
        }

        let result = path.withCString { removePath(conn, $0) }
        guard result == 0 else {
            throw AFCError.failed(operation: "AFCRemovePath(\(path))", code: result)
        }
    }

    func rename(from: String, to: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureOpen()
        guard let renamePath else {
            throw AFCError.unavailable("AFCRenamePath")
        }
        let result = from.withCString { fromPointer in
            to.withCString { toPointer in
                renamePath(conn, fromPointer, toPointer)
            }
        }
        guard result == 0 else {
            throw AFCError.failed(operation: "AFCRenamePath(\(from) → \(to))", code: result)
        }
    }

    // MARK: - Вспомогательное

    private func ensureOpen() throws {
        guard !isClosed else {
            throw AFCError.unavailable(L("соединение AFC закрыто"))
        }
    }

    static func join(_ path: String, _ name: String) -> String {
        if path == "/" || path.isEmpty {
            return "/" + name
        }
        return path.hasSuffix("/") ? path + name : path + "/" + name
    }

    static func date(from rawValue: String?) -> Date? {
        guard let rawValue, let value = Double(rawValue), value > 0 else { return nil }
        // AFC отдаёт st_mtime в наносекундах.
        let seconds = value > 1_000_000_000_000 ? value / 1_000_000_000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}
