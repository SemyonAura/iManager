import Foundation
import Darwin

struct InstalledApp: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let bundleID: String
    let version: String
    let buildVersion: String
    let applicationType: String

    var isUserApp: Bool {
        applicationType.caseInsensitiveCompare("User") == .orderedSame
    }
}

enum PairingStatus: Equatable, Sendable {
    case unknown
    case checking
    case paired
    case notPaired
    case pairing
    case failed(String)
}

enum InstallPhase: String, Sendable {
    case transferring
    case installing
}

struct InstallProgress: Equatable, Sendable {
    let phase: InstallPhase
    let percent: Int
    let status: String

    var localizedStatus: String {
        switch status {
        case "CopyingFile": return L("Копирование на устройство")
        case "CreatingStagingDirectory": return L("Подготовка")
        case "ExtractingPackage": return L("Распаковка пакета")
        case "InspectingPackage": return L("Проверка пакета")
        case "PreflightingApplication": return L("Предварительная проверка")
        case "VerifyingApplication": return L("Проверка подписи")
        case "CreatingContainer": return L("Создание контейнера")
        case "InstallingApplication": return L("Установка приложения")
        case "PostflightingApplication": return L("Завершение установки")
        case "SandboxingApplication": return L("Настройка песочницы")
        case "GeneratingApplicationMap": return L("Генерация карты приложения")
        case "InstallComplete": return L("Установлено")
        default:
            if !status.isEmpty { return status }
            return phase == .transferring ? L("Копирование на устройство") : L("Установка")
        }
    }
}

enum MobileDeviceError: LocalizedError {
    case unavailable(String)
    case deviceNotFound(String)
    case notPaired
    case callFailed(String, Int32)
    case invalidResponse(String)
    case invalidPackage(String)
    case installFailed(Int32, String?)

    var errorDescription: String? {
        switch self {
        case .unavailable(let detail):
            return L("MobileDevice.framework недоступен: %@", detail)
        case .deviceNotFound(let identifier):
            return L("Устройство %@ не найдено через MobileDevice.framework", identifier)
        case .notPaired:
            return L("Устройство не сопряжено. Подтвердите доверие этому компьютеру на экране устройства.")
        case .callFailed(let name, let code):
            let hex = String(UInt32(bitPattern: code), radix: 16, uppercase: true)
            if hex == "E800002D" {
                return L("%@: устройство заблокировано или защищено паролем. Разблокируйте iPhone и не блокируйте экран во время установки.", name)
            }
            return L("%@ завершилась с ошибкой 0x%@. Разблокируйте устройство и подтвердите запрос «Доверять».", name, hex)
        case .invalidResponse(let detail):
            return L("Некорректный ответ MobileDevice.framework: %@", detail)
        case .invalidPackage(let detail):
            return L("Некорректный .ipa: %@", detail)
        case .installFailed(let code, let detail):
            return Self.installFailureMessage(code: code, detail: detail)
        }
    }

    private static func installFailureMessage(code: Int32, detail: String?) -> String {
        let hex = String(UInt32(bitPattern: code), radix: 16, uppercase: true)
        let hint: String
        switch hex {
        case "E8000007":
            hint = L("Устройство заблокировано. Разблокируйте его и повторите установку.")
        case "E8008001":
            hint = L("Устройство отклонило приложение при проверке (ApplicationVerificationFailed).")
        case "E8008014":
            hint = L("Не удалось проверить подпись приложения. Скорее всего, IPA перепакован или повреждён.")
        case "E8008015":
            hint = L("Не найдена действительная подпись кода. Подпишите IPA сертификатом разработчика.")
        case "E8008016":
            hint = L("Приложение подписано с недействительными entitlements.")
        case "E8008017":
            hint = L("Не найден provisioning profile для этого приложения.")
        case "E8008018":
            hint = L("Срок действия сертификата или профиля подписи истёк.")
        case "E8008019":
            hint = L("Устройство не поддерживает минимальную версию iOS приложения.")
        case "E8008022":
            hint = L("Недействительный сертификат подписи.")
        case "E8008024":
            hint = L("Профиль подписи не содержит это устройство.")
        default:
            hint = L("Разблокируйте устройство, подтвердите доверие компьютеру и проверьте подпись IPA.")
        }

        var message = L("Установка завершилась с ошибкой 0x%@. %@", hex, hint)
        if let detail, !detail.isEmpty, detail != hint {
            message += "\n\n" + L("Детали: %@", detail)
        }
        return message
    }
}

/// Хранит обработчик прогресса на время синхронного вызова установки.
/// installation_proxy передаёт прогресс через C-колбэк без пользовательского
/// указателя, поэтому используется один общий приёмник (установки сериализованы).
private final class InstallProgressRelay: @unchecked Sendable {
    static let shared = InstallProgressRelay()

    private let lock = NSLock()
    private var handler: (@Sendable (InstallProgress) -> Void)?
    private var lastKey = ""
    private var lastError: String?

    func begin(_ handler: @escaping @Sendable (InstallProgress) -> Void) {
        lock.lock()
        self.handler = handler
        lastKey = ""
        lastError = nil
        lock.unlock()
    }

    func end() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    func report(_ dictionary: CFDictionary?, phase: InstallPhase) {
        guard let dictionary else { return }
        let values = dictionary as NSDictionary

        let status = (values["Status"] as? String) ?? ""
        let rawPercent = (values["PercentComplete"] as? NSNumber)?.intValue ?? 0
        if let error = values["Error"] {
            let text = Self.describe(error)
            lock.lock()
            lastError = text
            lock.unlock()
        }

        let percent = phase == .transferring
            ? rawPercent / 2
            : 50 + rawPercent / 2
        let key = "\(phase.rawValue)|\(percent)|\(status)"

        lock.lock()
        guard key != lastKey else {
            lock.unlock()
            return
        }
        lastKey = key
        let handler = self.handler
        lock.unlock()

        handler?(InstallProgress(
            phase: phase,
            percent: min(100, max(0, percent)),
            status: status
        ))
    }

    var errorDescription: String? {
        lock.lock()
        defer { lock.unlock() }
        return lastError
    }

    private static func describe(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let dictionary = value as? [String: Any] {
            if let text = dictionary["ErrorDescription"] as? String { return text }
            if let text = dictionary["Description"] as? String { return text }
            if let text = dictionary["LocalizedDescription"] as? String { return text }
            return "\(dictionary)"
        }
        return "\(value)"
    }
}

private func transferProgressCallback(_ dictionary: CFDictionary?, _ argument: Int32) -> Int32 {
    InstallProgressRelay.shared.report(dictionary, phase: .transferring)
    return 0
}

private func installProgressCallback(_ dictionary: CFDictionary?, _ argument: Int32) -> Int32 {
    InstallProgressRelay.shared.report(dictionary, phase: .installing)
    return 0
}

/// Мост к системному приватному MobileDevice.framework.
/// Он используется Apple Finder/iTunes и умеет pairing, сессии и installation_proxy.
final class MobileDeviceBridge: @unchecked Sendable {
    static let shared = MobileDeviceBridge()

    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias DeviceFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    private typealias CopyValueFn = @convention(c) (UnsafeMutableRawPointer?, CFString?, CFString?) -> UnsafeMutableRawPointer?
    private typealias LookupAppsFn = @convention(c) (UnsafeMutableRawPointer?, CFDictionary?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
    private typealias InstallCallback = @convention(c) (CFDictionary?, Int32) -> Int32
    private typealias SecureInstallFn = @convention(c) (Int32, UnsafeMutableRawPointer?, CFURL?, CFDictionary?, InstallCallback, Int32) -> Int32
    private typealias SecureUninstallFn = @convention(c) (Int32, UnsafeMutableRawPointer?, CFString?, Int32, InstallCallback?, Int32) -> Int32
    private typealias StartServiceFn = @convention(c) (UnsafeMutableRawPointer?, CFString?, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> Int32

    private let frameworkHandle: UnsafeMutableRawPointer?
    private let createDeviceListFn: CreateListFn?
    private let connectFn: DeviceFn?
    private let disconnectFn: DeviceFn?
    private let isPairedFn: DeviceFn?
    private let pairFn: DeviceFn?
    private let validatePairingFn: DeviceFn?
    private let startSessionFn: DeviceFn?
    private let stopSessionFn: DeviceFn?
    private let copyValueFn: CopyValueFn?
    private let lookupApplicationsFn: LookupAppsFn?
    private let transferPathFn: SecureInstallFn?
    private let secureInstallFn: SecureInstallFn?
    private let secureUninstallFn: SecureUninstallFn?
    private let startServiceFn: StartServiceFn?
    private let lock = NSLock()

    var isAvailable: Bool {
        frameworkHandle != nil
            && createDeviceListFn != nil
            && connectFn != nil
            && isPairedFn != nil
            && pairFn != nil
            && validatePairingFn != nil
            && startSessionFn != nil
            && copyValueFn != nil
            && lookupApplicationsFn != nil
    }

    private init() {
        let path = "/System/Library/PrivateFrameworks/MobileDevice.framework/Versions/A/MobileDevice"
        let handle = dlopen(path, RTLD_NOW)
        frameworkHandle = handle

        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }

        createDeviceListFn = load("AMDCreateDeviceList", as: CreateListFn.self)
        connectFn = load("AMDeviceConnect", as: DeviceFn.self)
        disconnectFn = load("AMDeviceDisconnect", as: DeviceFn.self)
        isPairedFn = load("AMDeviceIsPaired", as: DeviceFn.self)
        pairFn = load("AMDevicePair", as: DeviceFn.self)
        validatePairingFn = load("AMDeviceValidatePairing", as: DeviceFn.self)
        startSessionFn = load("AMDeviceStartSession", as: DeviceFn.self)
        stopSessionFn = load("AMDeviceStopSession", as: DeviceFn.self)
        copyValueFn = load("AMDeviceCopyValue", as: CopyValueFn.self)
        lookupApplicationsFn = load("AMDeviceLookupApplications", as: LookupAppsFn.self)
        transferPathFn = load("AMDeviceSecureTransferPath", as: SecureInstallFn.self)
        secureInstallFn = load("AMDeviceSecureInstallApplication", as: SecureInstallFn.self)
        secureUninstallFn = load("AMDeviceSecureUninstallApplication", as: SecureUninstallFn.self)
        startServiceFn = load("AMDeviceStartService", as: StartServiceFn.self)
    }

    // MARK: - Публичный API

    func pairingStatus(identifier: String) -> PairingStatus {
        lock.lock()
        defer { lock.unlock() }

        do {
            return try withDevice(identifier: identifier) { device in
                guard let isPaired = isPairedFn else {
                    throw MobileDeviceError.unavailable("AMDeviceIsPaired")
                }
                return isPaired(device) == 1 ? .paired : .notPaired
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Выполняет полный цикл сопряжения. На экране устройства появится запрос «Доверять».
    func pair(identifier: String) throws {
        lock.lock()
        defer { lock.unlock() }

        try withDevice(identifier: identifier) { device in
            guard let isPaired = isPairedFn else {
                throw MobileDeviceError.unavailable("AMDeviceIsPaired")
            }

            if isPaired(device) != 1 {
                guard let pair = pairFn else {
                    throw MobileDeviceError.unavailable("AMDevicePair")
                }
                let result = pair(device)
                guard result == 0 else {
                    throw MobileDeviceError.callFailed("AMDevicePair", result)
                }
            }

            guard let validate = validatePairingFn else {
                throw MobileDeviceError.unavailable("AMDeviceValidatePairing")
            }
            let validateResult = validate(device)
            guard validateResult == 0 else {
                throw MobileDeviceError.callFailed("AMDeviceValidatePairing", validateResult)
            }

            guard let startSession = startSessionFn else {
                throw MobileDeviceError.unavailable("AMDeviceStartSession")
            }
            let sessionResult = startSession(device)
            guard sessionResult == 0 else {
                throw MobileDeviceError.callFailed("AMDeviceStartSession", sessionResult)
            }

            _ = stopSessionFn?(device)
        }
    }

    /// Возвращает сведения об устройстве через `AMDeviceCopyValue`.
    /// Используется как fallback, когда нативный usbmuxd/lockdownd недоступен.
    func deviceInfo(identifier: String) throws -> DeviceInfo {
        lock.lock()
        defer { lock.unlock() }

        return try withDevice(identifier: identifier) { device in
            guard let isPaired = isPairedFn, isPaired(device) == 1 else {
                throw MobileDeviceError.notPaired
            }

            if let validate = validatePairingFn {
                let result = validate(device)
                guard result == 0 else {
                    throw MobileDeviceError.callFailed("AMDeviceValidatePairing", result)
                }
            }

            if let startSession = startSessionFn {
                let result = startSession(device)
                guard result == 0 else {
                    throw MobileDeviceError.callFailed("AMDeviceStartSession", result)
                }
            }
            defer { _ = stopSessionFn?(device) }

            let keys = [
                "DeviceName", "ProductType", "ProductVersion", "BuildVersion",
                "UniqueDeviceID", "SerialNumber", "ActivationState", "ModelNumber",
                "RegionInfo", "CPUArchitecture", "WiFiAddress", "BluetoothAddress",
                "HardwarePlatform", "HardwareModel", "DeviceColor", "DeviceEnclosureColor",
                "PhysicalMemory", "MemorySize", "TotalSystemMemory", "PhysicalMemorySize",
                "FirmwareVersion", "BasebandVersion"
            ]

            var values: [String: Any] = [:]
            for key in keys {
                if let value = copyValue(device, key: key) {
                    values[key] = value
                }
            }

            // Данные батареи lockdownd отдаёт в отдельном домене.
            for key in ["BatteryCurrentCapacity", "BatteryIsCharging", "BatteryCycleCount"] {
                if let value = copyValue(device, domain: "com.apple.mobile.battery", key: key) {
                    values[key] = value
                }
            }

            // Хранилище также доступно в отдельном домене.
            for key in [
                "TotalDataCapacity", "TotalDataAvailable",
                "TotalDiskCapacity", "TotalSystemCapacity",
                "AmountDataAvailable", "AmountRestoreAvailable"
            ] {
                if let value = copyValue(device, domain: "com.apple.disk_usage", key: key) {
                    values[key] = value
                }
            }
            return DeviceInfo(values: values)
        }
    }

    /// Возвращает все установленные приложения (пользовательские и системные).
    func installedApps(identifier: String) throws -> [InstalledApp] {
        lock.lock()
        defer { lock.unlock() }

        return try withDevice(identifier: identifier) { device in
            guard let isPaired = isPairedFn else {
                throw MobileDeviceError.unavailable("AMDeviceIsPaired")
            }
            guard isPaired(device) == 1 else {
                throw MobileDeviceError.notPaired
            }

            guard let validate = validatePairingFn else {
                throw MobileDeviceError.unavailable("AMDeviceValidatePairing")
            }
            let validateResult = validate(device)
            guard validateResult == 0 else {
                throw MobileDeviceError.callFailed("AMDeviceValidatePairing", validateResult)
            }

            guard let startSession = startSessionFn else {
                throw MobileDeviceError.unavailable("AMDeviceStartSession")
            }
            let sessionResult = startSession(device)
            guard sessionResult == 0 else {
                throw MobileDeviceError.callFailed("AMDeviceStartSession", sessionResult)
            }
            defer { _ = stopSessionFn?(device) }

            guard let lookup = lookupApplicationsFn else {
                throw MobileDeviceError.unavailable("AMDeviceLookupApplications")
            }

            var rawApps: UnsafeMutableRawPointer?
            let lookupResult = lookup(device, nil, &rawApps)
            guard lookupResult == 0 else {
                throw MobileDeviceError.callFailed("AMDeviceLookupApplications", lookupResult)
            }
            guard let rawApps else {
                throw MobileDeviceError.invalidResponse(L("AMDeviceLookupApplications вернул пустой указатель"))
            }

            let dictionary = Unmanaged<CFDictionary>.fromOpaque(rawApps).takeRetainedValue() as NSDictionary
            guard let apps = dictionary as? [String: Any] else {
                throw MobileDeviceError.invalidResponse(L("список приложений не является словарём"))
            }

            return apps.compactMap { key, value -> InstalledApp? in
                guard let info = value as? [String: Any] else { return nil }

                let bundleID = (info["CFBundleIdentifier"] as? String) ?? key
                guard !bundleID.isEmpty else { return nil }

                let name = (info["CFBundleDisplayName"] as? String)
                    ?? (info["CFBundleName"] as? String)
                    ?? bundleID
                let version = (info["CFBundleShortVersionString"] as? String) ?? ""
                let buildVersion = (info["CFBundleVersion"] as? String) ?? ""
                let applicationType = (info["ApplicationType"] as? String) ?? "Unknown"

                return InstalledApp(
                    id: bundleID,
                    name: name,
                    bundleID: bundleID,
                    version: version,
                    buildVersion: buildVersion,
                    applicationType: applicationType
                )
            }
        }
    }

    /// Открывает сервис `com.apple.afc` и возвращает сокет для AFCConnectionOpen.
    /// Сессия lockdown закрывается сразу после старта сервиса — сам сокет
    /// продолжает работать независимо от сессии.
    func startAFCService(identifier: String) throws -> UInt32 {
        lock.lock()
        defer { lock.unlock() }

        return try withDevice(identifier: identifier) { device in
            guard let isPaired = isPairedFn, isPaired(device) == 1 else {
                throw MobileDeviceError.notPaired
            }

            guard let validate = validatePairingFn else {
                throw MobileDeviceError.unavailable("AMDeviceValidatePairing")
            }
            let validateResult = validate(device)
            guard validateResult == 0 else {
                throw MobileDeviceError.callFailed("AMDeviceValidatePairing", validateResult)
            }

            guard let startSession = startSessionFn else {
                throw MobileDeviceError.unavailable("AMDeviceStartSession")
            }
            let sessionResult = startSession(device)
            guard sessionResult == 0 else {
                throw MobileDeviceError.callFailed("AMDeviceStartSession", sessionResult)
            }
            defer { _ = stopSessionFn?(device) }

            guard let startService = startServiceFn else {
                throw MobileDeviceError.unavailable("AMDeviceStartService")
            }

            var handle: UInt32 = 0
            var unknown: UInt32 = 0
            let result = startService(
                device,
                "com.apple.afc" as CFString,
                &handle,
                &unknown
            )
            guard result == 0, handle != 0 else {
                throw MobileDeviceError.callFailed("AMDeviceStartService(com.apple.afc)", result)
            }

            return handle
        }
    }

    /// Устанавливает `.ipa` через installation_proxy.
    ///
    /// Сначала пакет копируется на устройство (`AMDeviceSecureTransferPath`),
    /// затем открывается сессия и выполняется установка
    /// (`AMDeviceSecureInstallApplication`). Для App Store-пакетов нужен
    /// `PackageType = Customer`, для подписанных профилем — `Developer`
    /// или `Enterprise`.
    func installApp(
        identifier: String,
        ipaPath: String,
        packageType: String,
        progress: @escaping @Sendable (InstallProgress) -> Void
    ) throws {
        guard FileManager.default.fileExists(atPath: ipaPath) else {
            throw MobileDeviceError.invalidPackage(L("файл не найден: %@", ipaPath))
        }
        guard let transferPath = transferPathFn, let secureInstall = secureInstallFn else {
            throw MobileDeviceError.unavailable(
                "AMDeviceSecureTransferPath / AMDeviceSecureInstallApplication"
            )
        }

        lock.lock()
        defer { lock.unlock() }

        try withDevice(identifier: identifier) { device in
            guard let isPaired = isPairedFn, isPaired(device) == 1 else {
                throw MobileDeviceError.notPaired
            }

            // Проверяем сопряжение до передачи большого пакета, чтобы не тратить
            // время, если устройство заблокировано или доверие потеряно.
            guard let validate = validatePairingFn else {
                throw MobileDeviceError.unavailable("AMDeviceValidatePairing")
            }
            let validateResult = validate(device)
            guard validateResult == 0 else {
                throw MobileDeviceError.callFailed("AMDeviceValidatePairing", validateResult)
            }

            let options = NSDictionary(dictionary: ["PackageType": packageType]) as CFDictionary
            let url = URL(fileURLWithPath: ipaPath) as CFURL

            InstallProgressRelay.shared.begin(progress)
            defer { InstallProgressRelay.shared.end() }

            let transferResult = transferPath(
                0,
                device,
                url,
                options,
                transferProgressCallback,
                0
            )
            guard transferResult == 0 else {
                throw MobileDeviceError.installFailed(
                    transferResult,
                    InstallProgressRelay.shared.errorDescription
                )
            }

            guard let startSession = startSessionFn else {
                throw MobileDeviceError.unavailable("AMDeviceStartSession")
            }
            let sessionResult = startSession(device)
            guard sessionResult == 0 else {
                throw MobileDeviceError.callFailed("AMDeviceStartSession", sessionResult)
            }
            defer { _ = stopSessionFn?(device) }

            let installResult = secureInstall(
                0,
                device,
                url,
                options,
                installProgressCallback,
                0
            )
            guard installResult == 0 else {
                throw MobileDeviceError.installFailed(
                    installResult,
                    InstallProgressRelay.shared.errorDescription
                )
            }
        }
    }

    /// Удаляет приложение по его Bundle ID.
    func uninstallApp(identifier: String, bundleID: String) throws {
        guard let secureUninstall = secureUninstallFn else {
            throw MobileDeviceError.unavailable("AMDeviceSecureUninstallApplication")
        }

        lock.lock()
        defer { lock.unlock() }

        try withDevice(identifier: identifier) { device in
            guard let isPaired = isPairedFn, isPaired(device) == 1 else {
                throw MobileDeviceError.notPaired
            }

            guard let validate = validatePairingFn else {
                throw MobileDeviceError.unavailable("AMDeviceValidatePairing")
            }
            let validateResult = validate(device)
            guard validateResult == 0 else {
                throw MobileDeviceError.callFailed("AMDeviceValidatePairing", validateResult)
            }

            guard let startSession = startSessionFn else {
                throw MobileDeviceError.unavailable("AMDeviceStartSession")
            }
            let sessionResult = startSession(device)
            guard sessionResult == 0 else {
                throw MobileDeviceError.callFailed("AMDeviceStartSession", sessionResult)
            }
            defer { _ = stopSessionFn?(device) }

            let result = secureUninstall(0, device, bundleID as CFString, 0, nil, 0)
            guard result == 0 else {
                throw MobileDeviceError.callFailed("AMDeviceSecureUninstallApplication", result)
            }
        }
    }

    // MARK: - Внутренняя работа с устройствами

    /// Держит CFArray устройств живым на протяжении всей операции и передаёт
    /// в замыкание уже подключённое устройство.
    private func withDevice<T>(
        identifier: String,
        _ body: (UnsafeMutableRawPointer) throws -> T
    ) throws -> T {
        guard isAvailable, let createDeviceList = createDeviceListFn else {
            throw MobileDeviceError.unavailable(L("не удалось загрузить функции"))
        }
        guard let unmanagedList = createDeviceList() else {
            throw MobileDeviceError.invalidResponse(L("AMDCreateDeviceList вернул nil"))
        }

        let list = unmanagedList.takeRetainedValue()
        let count = CFArrayGetCount(list)

        for index in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)

            guard let connect = connectFn else {
                throw MobileDeviceError.unavailable("AMDeviceConnect")
            }
            let connectResult = connect(device)

            let matches = matchesIdentifier(device, identifier: identifier)

            if matches {
                defer {
                    if connectResult == 0 {
                        _ = disconnectFn?(device)
                    }
                }
                guard connectResult == 0 else {
                    throw MobileDeviceError.callFailed("AMDeviceConnect", connectResult)
                }
                return try body(device)
            }

            if connectResult == 0 {
                _ = disconnectFn?(device)
            }
        }

        throw MobileDeviceError.deviceNotFound(identifier)
    }

    private func matchesIdentifier(_ device: UnsafeMutableRawPointer, identifier: String) -> Bool {
        if let udid = copyString(device, key: "UniqueDeviceID"), udid == identifier {
            return true
        }
        if let serial = copyString(device, key: "SerialNumber"), serial == identifier {
            return true
        }
        return false
    }

    private func copyString(_ device: UnsafeMutableRawPointer, key: String) -> String? {
        copyValue(device, key: key) as? String
    }

    private func copyValue(_ device: UnsafeMutableRawPointer, domain: String? = nil, key: String) -> Any? {
        guard let copyFn = copyValueFn else { return nil }
        let domainRef = domain.map { $0 as CFString }
        guard let raw = copyFn(device, domainRef, key as CFString) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeRetainedValue()
    }
}
