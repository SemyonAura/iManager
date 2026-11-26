import Foundation
import Darwin

// MARK: - Модели ipatool

struct IPAToolApp: Codable, Identifiable, Equatable {
    let id: Int
    let bundleID: String
    let name: String
    let version: String
    let price: Double?
    let purchaseDate: String?
    let platforms: [String]?
    /// `ipatool-cpp` отдаёт тип покупки в поле `kind` ("iOS App", "Book", …).
    let kind: String?

    enum CodingKeys: String, CodingKey {
        case id
        case bundleID
        case name
        case version
        case price
        case purchaseDate
        case platforms
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let value = try? container.decode(Int.self, forKey: .id) {
            id = value
        } else if let value = try? container.decode(String.self, forKey: .id), let parsed = Int(value) {
            id = parsed
        } else {
            id = 0
        }

        bundleID = (try? container.decode(String.self, forKey: .bundleID)) ?? ""
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        version = (try? container.decode(String.self, forKey: .version)) ?? ""
        price = try? container.decode(Double.self, forKey: .price)
        purchaseDate = try? container.decode(String.self, forKey: .purchaseDate)
        platforms = try? container.decode([String].self, forKey: .platforms)
        kind = try? container.decode(String.self, forKey: .kind)
    }
}

struct IPAToolAccount: Equatable {
    let name: String
    let email: String
}

struct IPAToolPurchasesResult {
    let apps: [IPAToolApp]
    let count: Int
}

struct IPAToolVersionMetadata: Equatable {
    let externalVersionID: String
    let displayVersion: String
    let releaseDate: String?
    let minimumOSVersion: String?
}

/// Разобранный вывод `ipatool --format json`. Утилита пишет по одному
/// JSON-объекту на строку, поэтому поля собираются из всех строк.
struct IPAToolParsedOutput {
    var account: IPAToolAccount?
    var apps: [IPAToolApp] = []
    var count: Int?
    var versions: [String] = []
    var versionMetadata: IPAToolVersionMetadata?
    var requires2FA = false
    var success = false
    var errorMessage: String?
    var outputPath: String?
}

// MARK: - Ошибки

enum IPAToolError: LocalizedError {
    case binaryNotFound
    case notAuthenticated
    case requires2FA
    case commandFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return L("Утилита ipatool не найдена внутри приложения. Пересоберите iManager.")
        case .notAuthenticated:
            return L("Вы не вошли в Apple ID. Войдите в раздел «Мои покупки».")
        case .requires2FA:
            return L("Apple запросил код двухфакторной аутентификации (2FA).")
        case .commandFailed(let message):
            return message
        case .invalidResponse(let detail):
            return L("Не удалось разобрать ответ ipatool: %@", detail)
        }
    }
}

// MARK: - Сервис

/// Обёртка над `ipatool-cpp` (https://github.com/Sorvigolova/ipatool).
/// C++-версия умеет то, чего нет в Go-оригинале: полную историю покупок
/// по годам, список версий приложения и скачивание выбранной версии.
final class IPAToolService {
    static let shared = IPAToolService()

    /// Постоянный пароль для шифрования файла аккаунта `~/.ipatool/account`.
    static let keychainPassphrase = "com.aura.imanager.ipatool.keychain"

    /// Каталог, в котором `ipatool-cpp` хранит состояние входа:
    /// `account` (учётные данные), `cookies` (сессия App Store) и
    /// `adi-state` (идентификатор устройства).
    static var stateDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ipatool", isDirectory: true)
    }

    /// MAC-адрес, который подставляется ipatool через `ipatool-shim.dylib`.
    /// ipatool выводит из него GUID устройства, а Apple запоминает GUID как
    /// доверенное устройство. После выхода генерируется новый MAC, поэтому
    /// Apple снова запрашивает код 2FA.
    private static let deviceMACKey = "iManager.AppStoreDeviceMAC"
    private static let forceNewDeviceKey = "iManager.AppStoreForceNewDevice"
    private static let deviceMACEnvironmentKey = "IMANAGER_DEVICE_MAC"

    private let runnersLock = NSLock()
    private var runners: [ProcessRunner] = []

    private init() {}

    var executableURL: URL? {
        var candidates: [URL] = []

        if let url = Bundle.main.url(forResource: "ipatool", withExtension: nil, subdirectory: "bin") {
            candidates.append(url)
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("bin/ipatool"))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin/ipatool"))
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/bin/ipatool")
        )

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    var isAvailable: Bool { executableURL != nil }

    var shimURL: URL? {
        var candidates: [URL] = []

        if let url = Bundle.main.url(
            forResource: "ipatool-shim",
            withExtension: "dylib",
            subdirectory: "bin"
        ) {
            candidates.append(url)
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("bin/ipatool-shim.dylib"))
        }
        candidates.append(
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin/ipatool-shim.dylib")
        )
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/bin/ipatool-shim.dylib")
        )

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private var storedDeviceMAC: String? {
        UserDefaults.standard.string(forKey: Self.deviceMACKey)
    }

    /// Окружение для запуска ipatool. Если задан новый MAC, подключаем шим,
    /// который подменяет адрес, читаемый ipatool из IOKit.
    var processEnvironment: [String: String]? {
        guard let shimURL, let mac = storedDeviceMAC else { return nil }

        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_INSERT_LIBRARIES"] = shimURL.path
        environment[Self.deviceMACEnvironmentKey] = mac
        return environment
    }

    /// Готовит новое устройство для входа: если сохранённого MAC нет,
    /// генерирует его. Вызывается перед `auth login`.
    func prepareDeviceIdentity() {
        guard storedDeviceMAC == nil else { return }

        let forceNew = UserDefaults.standard.bool(forKey: Self.forceNewDeviceKey)
        if !forceNew {
            // В файле аккаунта может лежать kbsync, привязанный к старому
            // MAC. Не меняем идентичность, пока сессия не удалена выходом.
            let accountURL = Self.stateDirectoryURL.appendingPathComponent("account")
            guard !FileManager.default.fileExists(atPath: accountURL.path) else { return }
        }

        UserDefaults.standard.set(Self.makeDeviceMAC(), forKey: Self.deviceMACKey)
        UserDefaults.standard.set(false, forKey: Self.forceNewDeviceKey)
    }

    /// Забывает MAC: следующий вход будет с нового устройства.
    func resetDeviceIdentity() {
        UserDefaults.standard.removeObject(forKey: Self.deviceMACKey)
        UserDefaults.standard.set(true, forKey: Self.forceNewDeviceKey)
    }

    private static func makeDeviceMAC() -> String {
        var bytes = [UInt8](repeating: 0, count: 6)
        bytes.withUnsafeMutableBytes { buffer in
            arc4random_buf(buffer.baseAddress, buffer.count)
        }

        // Локально администрируемый unicast-адрес — так выглядят приватные
        // MAC-адреса Apple, и ipatool не считает его placeholder-значением.
        bytes[0] = (bytes[0] | 0x02) & 0xFE
        if bytes == [0x02, 0x00, 0x00, 0x00, 0x00, 0x00] {
            bytes[5] = 0x01
        }

        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    var globalArguments: [String] {
        ["--format", "json", "--keychain-passphrase", Self.keychainPassphrase]
    }

    // MARK: - Авторизация

    func login(email: String, password: String, authCode: String? = nil) async throws -> IPAToolAccount {
        // Новый вход после выхода должен выглядеть для Apple как новое
        // устройство — тогда она снова запросит код 2FA.
        prepareDeviceIdentity()

        var arguments = [
            "auth", "login",
            "--email", email,
            "--password", password
        ]

        if let authCode, !authCode.isEmpty {
            arguments.append(contentsOf: ["--auth-code", authCode])
        }

        let result = try await run(arguments)
        let parsed = Self.parse(result.output)

        if parsed.requires2FA {
            throw IPAToolError.requires2FA
        }
        if let account = parsed.account {
            return account
        }
        if let error = parsed.errorMessage {
            throw IPAToolError.commandFailed(Self.localizedMessage(error))
        }
        if result.status != 0 {
            throw IPAToolError.commandFailed(L("Не удалось войти в Apple ID (код %d).", Int(result.status)))
        }

        throw IPAToolError.commandFailed(L("Apple не подтвердил вход. Проверьте Apple ID и пароль."))
    }

    func accountInfo() async throws -> IPAToolAccount? {
        let result = try await run(["auth", "info"])
        let parsed = Self.parse(result.output)

        if let account = parsed.account {
            return account
        }
        if let error = parsed.errorMessage {
            if Self.isNotAuthenticated(error) {
                return nil
            }
            throw IPAToolError.commandFailed(Self.localizedMessage(error))
        }
        if Self.isNotAuthenticated(result.output) {
            return nil
        }
        return nil
    }

    /// Полностью удаляет сохранённую сессию Apple ID.
    ///
    /// `ipatool auth revoke` стирает только `account` и `cookies`, оставляя
    /// `adi-state` — локальный идентификатор устройства. Пока он существует,
    /// Apple считает повторный вход доверенным и не запрашивает код 2FA.
    /// Поэтому удаляем весь каталог состояния: следующий вход будет выглядеть
    /// как вход с нового устройства.
    func revoke() async throws {
        // Останавливаем уже запущенные команды, чтобы работающий процесс
        // не успел заново сохранить состояние сессии после очистки.
        cancelRunningCommands()

        _ = try? await run(["auth", "revoke"])

        let fileManager = FileManager.default
        let stateDirectory = Self.stateDirectoryURL
        var deletionError: Error?

        if fileManager.fileExists(atPath: stateDirectory.path) {
            do {
                try fileManager.removeItem(at: stateDirectory)
            } catch {
                deletionError = error
            }
        }

        // Следующий вход получит новый MAC и новый GUID устройства — даже
        // если удалить файлы не удалось и сессия осталась на диске.
        resetDeviceIdentity()

        if let deletionError {
            throw IPAToolError.commandFailed(
                L("Не удалось удалить данные сессии Apple ID: %@", deletionError.localizedDescription)
            )
        }
    }

    /// Останавливает все запущенные команды `ipatool`.
    func cancelRunningCommands() {
        runnersLock.lock()
        let active = runners
        runnersLock.unlock()
        active.forEach { $0.terminate() }
    }

    private func register(_ runner: ProcessRunner) {
        runnersLock.lock()
        runners.append(runner)
        runnersLock.unlock()
    }

    private func unregister(_ runner: ProcessRunner) {
        runnersLock.lock()
        runners.removeAll { $0 === runner }
        runnersLock.unlock()
    }

    // MARK: - Покупки

    /// Загружает покупки за один календарный год (`range` = "2024-all")
    /// или всю историю сразу (`allYears`).
    func listPurchases(range: String? = nil, allYears: Bool = false) async throws -> IPAToolPurchasesResult {
        var arguments = ["list-purchases"]
        if allYears {
            arguments.append("--all")
        } else if let range, !range.isEmpty {
            arguments.append(contentsOf: ["--range", range])
        }

        let result = try await run(arguments)
        let parsed = Self.parse(result.output)

        if parsed.requires2FA {
            throw IPAToolError.requires2FA
        }
        if let error = parsed.errorMessage {
            if Self.isNotAuthenticated(error) || Self.isHTTPAuthFailure(error) {
                throw IPAToolError.notAuthenticated
            }
            throw IPAToolError.commandFailed(Self.localizedMessage(error))
        }
        if result.status != 0 {
            throw IPAToolError.commandFailed(L("ipatool завершился с кодом %d.", Int(result.status)))
        }

        return IPAToolPurchasesResult(
            apps: parsed.apps,
            count: parsed.count ?? parsed.apps.count
        )
    }

    // MARK: - Версии приложения

    func listVersions(appID: Int, bundleID: String) async throws -> [String] {
        var arguments = ["list-versions"]
        // App Store ID надёжнее bundle ID: не требует lookup и работает для
        // приложений, удалённых из каталога.
        if appID > 0 {
            arguments.append(contentsOf: ["--app-id", "\(appID)"])
        } else if !bundleID.isEmpty {
            arguments.append(contentsOf: ["--bundle-id", bundleID])
        } else {
            throw IPAToolError.commandFailed(L("Неизвестен идентификатор приложения."))
        }

        let result = try await run(arguments)
        let parsed = Self.parse(result.output)

        if let error = parsed.errorMessage {
            if Self.isNotAuthenticated(error) {
                throw IPAToolError.notAuthenticated
            }
            throw IPAToolError.commandFailed(Self.localizedMessage(error))
        }
        if result.status != 0 {
            throw IPAToolError.commandFailed(L("Не удалось получить список версий (код %d).", Int(result.status)))
        }

        return parsed.versions
    }

    func versionMetadata(appID: Int, bundleID: String, versionID: String) async throws -> IPAToolVersionMetadata {
        var arguments = ["get-version-metadata"]
        if appID > 0 {
            arguments.append(contentsOf: ["--app-id", "\(appID)"])
        } else if !bundleID.isEmpty {
            arguments.append(contentsOf: ["--bundle-id", bundleID])
        } else {
            throw IPAToolError.commandFailed(L("Неизвестен идентификатор приложения."))
        }
        arguments.append(contentsOf: ["--external-version-id", versionID])

        let result = try await run(arguments)
        let parsed = Self.parse(result.output)

        if let error = parsed.errorMessage {
            if Self.isNotAuthenticated(error) {
                throw IPAToolError.notAuthenticated
            }
            throw IPAToolError.commandFailed(Self.localizedMessage(error))
        }
        if result.status != 0 {
            throw IPAToolError.commandFailed(L("Не удалось получить сведения о версии (код %d).", Int(result.status)))
        }
        guard let metadata = parsed.versionMetadata else {
            throw IPAToolError.invalidResponse(L("нет данных о версии"))
        }
        return metadata
    }

    // MARK: - Загрузка

    func downloadArguments(
        appID: Int,
        bundleID: String,
        destination: String,
        versionID: String? = nil
    ) -> [String] {
        var arguments = ["download"]

        if appID > 0 {
            arguments.append(contentsOf: ["--app-id", "\(appID)"])
        } else if !bundleID.isEmpty {
            arguments.append(contentsOf: ["--bundle-id", bundleID])
        }

        arguments.append(contentsOf: [
            "--output", destination,
            "--purchase"
        ])

        if let versionID, !versionID.isEmpty {
            arguments.append(contentsOf: ["--external-version-id", versionID])
        }

        return arguments
    }

    // MARK: - Запуск

    struct RunResult {
        let output: String
        let status: Int32
    }

    private func run(_ arguments: [String]) async throws -> RunResult {
        guard let executableURL else {
            throw IPAToolError.binaryNotFound
        }

        let runner = ProcessRunner()
        register(runner)

        defer {
            unregister(runner)
        }

        do {
            try runner.start(
                executable: executableURL,
                arguments: arguments + globalArguments,
                environment: processEnvironment
            )
        } catch {
            throw IPAToolError.commandFailed(L("Не удалось запустить ipatool: %@", error.localizedDescription))
        }

        let status = await runner.wait()
        return RunResult(output: runner.collectedOutput(), status: status)
    }

    // MARK: - Разбор вывода

    static func parse(_ output: String) -> IPAToolParsedOutput {
        var parsed = IPAToolParsedOutput()
        let lines = output
            .components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            // `ipatool-cpp` печатает ошибки обычным текстом, а успешные
            // ответы — одной JSON-строкой.
            if !line.hasPrefix("{") {
                consumePlainLine(line, into: &parsed)
                continue
            }

            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            if let message = object["message"] as? String {
                consumePlainLine(message, into: &parsed)
            }

            if let error = object["error"] as? String, !error.isEmpty {
                parsed.errorMessage = error
            }

            if let success = object["success"] as? Bool, success {
                parsed.success = true
                if let email = object["email"] as? String, !email.isEmpty {
                    parsed.account = IPAToolAccount(
                        name: (object["name"] as? String) ?? "",
                        email: email
                    )
                }
            }

            if let count = object["count"] as? Int {
                parsed.count = count
            }
            if let outputPath = object["output"] as? String, !outputPath.isEmpty {
                parsed.outputPath = outputPath
            }

            if let rawApps = object["apps"] as? [[String: Any]] {
                var apps: [IPAToolApp] = []
                for rawApp in rawApps {
                    guard
                        let appData = try? JSONSerialization.data(withJSONObject: rawApp),
                        let app = try? JSONDecoder().decode(IPAToolApp.self, from: appData)
                    else {
                        continue
                    }
                    apps.append(app)
                }
                parsed.apps = apps
            }

            if let rawVersions = object["externalVersionIdentifiers"] as? [Any] {
                parsed.versions = rawVersions.compactMap { value in
                    if let string = value as? String { return string }
                    if let number = value as? NSNumber { return number.stringValue }
                    return nil
                }
            }

            if let displayVersion = object["displayVersion"] as? String {
                let versionID = (object["externalVersionID"] as? String)
                    ?? (object["externalVersionID"] as? NSNumber)?.stringValue
                    ?? ""
                parsed.versionMetadata = IPAToolVersionMetadata(
                    externalVersionID: versionID,
                    displayVersion: displayVersion,
                    releaseDate: object["releaseDate"] as? String,
                    minimumOSVersion: object["minimumOSVersion"] as? String
                )
            }
        }

        return parsed
    }

    private static func consumePlainLine(_ line: String, into parsed: inout IPAToolParsedOutput) {
        let lower = line.lowercased()

        if lower.contains("two-factor auth code required")
            || lower.contains("enter 2fa code")
            || lower.contains("2fa code is required")
            || lower.contains("auth code is required") {
            parsed.requires2FA = true
        }

        if lower.contains("not logged in") {
            parsed.errorMessage = "Not logged in."
            return
        }

        if lower.hasPrefix("list-purchases failed") {
            parsed.errorMessage = line
            return
        }

        let prefixes = [
            "login error:",
            "download error:",
            "search error:",
            "purchase error:",
            "error:"
        ]

        for prefix in prefixes where lower.hasPrefix(prefix) {
            let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                parsed.errorMessage = value
            }
            return
        }
    }

    // MARK: - Сообщения

    static func isNotAuthenticated(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("not logged in")
            || lower.contains("failed to get account")
            || lower.contains("could not be found in the keyring")
            || lower.contains("item could not be found")
            || lower.contains("keychain is not configured")
            || lower.contains("re-login failed: 2fa")
    }

    static func isHTTPAuthFailure(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("http 401") || lower.contains("http 403")
    }

    static func localizedMessage(_ raw: String) -> String {
        var message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Login error:", "Download error:", "Search error:", "Purchase error:", "Error:"] {
            if message.lowercased().hasPrefix(prefix.lowercased()) {
                message = String(message.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        let lower = message.lowercased()

        if isNotAuthenticated(message) {
            return L("Сессия Apple ID не найдена. Войдите в «Мои покупки» заново.")
        }
        if isHTTPAuthFailure(message) {
            return L("Сессия Apple ID истекла. Войдите в «Мои покупки» заново.")
        }
        if lower.contains("two-factor") || lower.contains("2fa") || lower.contains("auth code") {
            return L("Apple запросил код 2FA. Введите его и повторите вход.")
        }
        if lower.contains("account is disabled") {
            return L("Apple временно заблокировал аккаунт. Разблокируйте его через устройство или iCloud и повторите вход.")
        }
        if lower.contains("your password has changed") {
            return L("Пароль Apple ID изменился. Войдите заново.")
        }
        if lower.contains("invalid username or password")
            || lower.contains("incorrect username or password")
            || lower.contains("bad credentials")
            || lower.contains("did you forget your password") {
            return L("Неверный Apple ID или пароль.")
        }
        if lower.contains("incorrect verification code")
            || lower.contains("invalid verification code")
            || lower.contains("incorrect auth code") {
            return L("Неверный код двухфакторной аутентификации.")
        }
        if lower.contains("could not resolve host")
            || lower.contains("couldn't resolve host")
            || lower.contains("connection refused")
            || lower.contains("connection reset")
            || lower.contains("timeout")
            || lower.contains("no such host")
            || lower.contains("network is unreachable")
            || lower.contains("failed to initialize sap signer") {
            return L("Нет связи с серверами Apple. Проверьте подключение к интернету.")
        }
        if lower.contains("license is required") || lower.contains("you must purchase this app first") {
            return L("Для этого приложения не получена лицензия. Повторите загрузку с включённым получением лицензии.")
        }
        if lower.contains("app not found") {
            return L("Приложение не найдено в App Store. Возможно, оно удалено из магазина.")
        }
        if lower.contains("item is temporarily unavailable") {
            return L("Приложение временно недоступно в App Store. Попробуйте другую версию или повторите позже.")
        }
        if lower.contains("empty songlist") {
            return L("Apple вернул пустой список загрузки. Войдите в Apple ID заново.")
        }
        if lower.contains("hash mismatch") {
            return L("Файл скачался повреждённым. Повторите загрузку.")
        }

        return message.isEmpty ? raw : message
    }
}
