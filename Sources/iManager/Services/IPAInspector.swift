import Foundation

/// Тип подписи, обнаруженный внутри `.ipa`.
enum IPASignatureKind: String, Sendable {
    case development
    case enterprise
    case appStore
    case repackaged
    case unsigned

    var title: String {
        switch self {
        case .development: return L("Сертификат разработчика")
        case .enterprise: return L("Enterprise-подпись")
        case .appStore: return "App Store"
        case .repackaged: return L("Перепакован без FairPlay")
        case .unsigned: return L("Без подписи")
        }
    }

    /// Значение ключа `PackageType` для installation_proxy.
    var packageType: String {
        switch self {
        case .development: return "Developer"
        case .enterprise: return "Enterprise"
        case .appStore: return "Customer"
        case .repackaged, .unsigned: return "Developer"
        }
    }
}

struct IPAInfo: Identifiable, Equatable, Sendable {
    var id: String { path }

    let path: String
    let appBundlePath: String
    let bundleID: String
    let name: String
    let version: String
    let buildVersion: String
    let minimumOSVersion: String
    let signature: IPASignatureKind
    let profileName: String?
    let profileTeam: String?
    let profileExpiration: Date?
    let profileIncludesDevice: Bool?
    let fileSize: Int64

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    var packageType: String {
        signature.packageType
    }

    var isProfileExpired: Bool {
        guard let profileExpiration else { return false }
        return profileExpiration < Date()
    }

    /// Причина, по которой установка заведомо не пройдёт.
    var blockingIssue: String? {
        switch signature {
        case .unsigned:
            return L("В IPA нет подписи кода. iOS не установит такое приложение. Подпишите его сертификатом разработчика или через сервис подписи.")
        case .repackaged:
            return L("IPA выглядит перепакованным: в нём нет FairPlay-подписи App Store. iOS отклонит его при проверке подписи. Переподпишите приложение.")
        case .development, .enterprise:
            if let profileExpiration, profileExpiration < Date() {
                return L("Срок действия профиля подписи истёк %@. Переподпишите IPA.", Self.dateFormatter.string(from: profileExpiration))
            }
            if profileIncludesDevice == false {
                return L("Профиль подписи не содержит UDID этого устройства. Добавьте устройство в профиль и переподпишите IPA.")
            }
            return nil
        case .appStore:
            return nil
        }
    }

    var warning: String? {
        if signature == .appStore {
            return L("App Store-подпись проверяется устройством. Установка пройдёт, если устройство авторизовано для этой покупки. Изменённые после скачивания приложения не установятся.")
        }
        return blockingIssue
    }

    var canInstall: Bool {
        blockingIssue == nil
    }

    private static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }
}

enum IPAInspectorError: LocalizedError {
    case notIPA
    case fileNotFound(String)
    case unzip(String)
    case noPayload
    case noInfoPlist
    case invalidInfoPlist(String)
    case missingBundleIdentifier

    var errorDescription: String? {
        switch self {
        case .notIPA:
            return L("Выбранный файл не является .ipa.")
        case .fileNotFound(let path):
            return L("Файл не найден: %@", path)
        case .unzip(let detail):
            return L("Не удалось прочитать архив: %@", detail)
        case .noPayload:
            return L("В архиве нет каталога Payload с приложением.")
        case .noInfoPlist:
            return L("В архиве не найден Info.plist приложения.")
        case .invalidInfoPlist(let detail):
            return L("Не удалось разобрать Info.plist: %@", detail)
        case .missingBundleIdentifier:
            return L("В Info.plist отсутствует CFBundleIdentifier.")
        }
    }
}

enum IPAInspector {
    static func inspect(path: String, deviceUDID: String) throws -> IPAInfo {
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension.lowercased() == "ipa" else {
            throw IPAInspectorError.notIPA
        }
        guard FileManager.default.fileExists(atPath: path) else {
            throw IPAInspectorError.fileNotFound(path)
        }

        let entries = try listEntries(path: path)
        guard let infoEntry = entries.first(where: isAppInfoPlist) else {
            if !entries.contains(where: { $0.hasPrefix("Payload/") }) {
                throw IPAInspectorError.noPayload
            }
            throw IPAInspectorError.noInfoPlist
        }

        let appBundlePath = infoEntry
            .components(separatedBy: "/")
            .dropLast()
            .joined(separator: "/")

        let infoData = try readEntry(path: path, entry: infoEntry)
        let plist: [String: Any]
        do {
            let object = try PropertyListSerialization.propertyList(
                from: infoData,
                options: [],
                format: nil
            )
            guard let dictionary = object as? [String: Any] else {
                throw IPAInspectorError.invalidInfoPlist(L("корневой объект не является словарём"))
            }
            plist = dictionary
        } catch let error as IPAInspectorError {
            throw error
        } catch {
            throw IPAInspectorError.invalidInfoPlist(error.localizedDescription)
        }

        guard let bundleID = plist["CFBundleIdentifier"] as? String, !bundleID.isEmpty else {
            throw IPAInspectorError.missingBundleIdentifier
        }

        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? bundleID
        let version = (plist["CFBundleShortVersionString"] as? String) ?? ""
        let buildVersion = (plist["CFBundleVersion"] as? String) ?? ""
        let minimumOSVersion = (plist["MinimumOSVersion"] as? String) ?? ""

        let hasProfile = entries.contains { $0 == "\(appBundlePath)/embedded.mobileprovision" }
        let hasCodeSignature = entries.contains { $0.hasPrefix("\(appBundlePath)/_CodeSignature/") }
        let hasFairPlay = entries.contains { $0.hasPrefix("\(appBundlePath)/SC_Info/") }

        var signature: IPASignatureKind
        var profileName: String?
        var profileTeam: String?
        var profileExpiration: Date?
        var profileIncludesDevice: Bool?

        if hasProfile {
            let profile = try? readProvisioningProfile(
                path: path,
                entry: "\(appBundlePath)/embedded.mobileprovision"
            )
            profileName = profile?.name
            profileTeam = profile?.team
            profileExpiration = profile?.expiration

            if profile?.provisionsAllDevices == true {
                signature = .enterprise
            } else {
                signature = .development
                if let devices = profile?.provisionedDevices {
                    profileIncludesDevice = devices.contains(deviceUDID)
                }
            }
        } else if hasCodeSignature {
            signature = hasFairPlay ? .appStore : .repackaged
        } else {
            signature = .unsigned
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0

        return IPAInfo(
            path: path,
            appBundlePath: appBundlePath,
            bundleID: bundleID,
            name: name,
            version: version,
            buildVersion: buildVersion,
            minimumOSVersion: minimumOSVersion,
            signature: signature,
            profileName: profileName,
            profileTeam: profileTeam,
            profileExpiration: profileExpiration,
            profileIncludesDevice: profileIncludesDevice,
            fileSize: fileSize
        )
    }

    // MARK: - ZIP

    private static func isAppInfoPlist(_ entry: String) -> Bool {
        let parts = entry.split(separator: "/", omittingEmptySubsequences: true)
        return parts.count == 3
            && parts[0] == "Payload"
            && parts[1].hasSuffix(".app")
            && parts[2] == "Info.plist"
    }

    private static func listEntries(path: String) throws -> [String] {
        let data = try runUnzip(["-Z1", path])
        guard let output = String(data: data, encoding: .utf8) else {
            throw IPAInspectorError.unzip(L("не удалось декодировать список файлов"))
        }
        return output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func readEntry(path: String, entry: String) throws -> Data {
        try runUnzip(["-p", path, entry])
    }

    private static func runUnzip(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments

        let output = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput

        do {
            try process.run()
        } catch {
            throw IPAInspectorError.unzip(error.localizedDescription)
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw IPAInspectorError.unzip(
                detail?.isEmpty == false ? detail! : L("unzip завершился с кодом %d", Int(process.terminationStatus))
            )
        }
        return data
    }

    // MARK: - Профиль подписи

    private struct ProvisioningProfile {
        let name: String?
        let team: String?
        let expiration: Date?
        let provisionsAllDevices: Bool
        let provisionedDevices: [String]?
    }

    private static func readProvisioningProfile(path: String, entry: String) throws -> ProvisioningProfile? {
        let data = try readEntry(path: path, entry: entry)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("iManager-profile-\(UUID().uuidString).mobileprovision")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["cms", "-D", "-i", tempURL.path]

        let output = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput

        do {
            try process.run()
        } catch {
            return nil
        }

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        _ = errorOutput.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let object = try? PropertyListSerialization.propertyList(
                  from: outputData,
                  options: [],
                  format: nil
              ),
              let plist = object as? [String: Any] else {
            return nil
        }

        return ProvisioningProfile(
            name: plist["Name"] as? String,
            team: plist["TeamName"] as? String,
            expiration: plist["ExpirationDate"] as? Date,
            provisionsAllDevices: (plist["ProvisionsAllDevices"] as? Bool) ?? false,
            provisionedDevices: plist["ProvisionedDevices"] as? [String]
        )
    }
}
