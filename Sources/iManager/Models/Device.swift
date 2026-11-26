import Foundation

enum ConnectionType: String, Hashable {
    case usb = "USB"
    case network = "Wi-Fi"
    case unknown = "Неизвестно"

    var symbol: String {
        switch self {
        case .usb: return "cable.connector"
        case .network: return "wifi"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Отображаемое название с учётом языка интерфейса.
    var title: String {
        switch self {
        case .usb: return "USB"
        case .network: return "Wi-Fi"
        case .unknown: return L("Неизвестно")
        }
    }

    init(rawConnectionType: String) {
        let normalized = rawConnectionType.lowercased()
        if normalized.contains("usb") {
            self = .usb
        } else if normalized.contains("network") || normalized.contains("wifi") || normalized.contains("wi-fi") {
            self = .network
        } else {
            self = .unknown
        }
    }
}

struct Device: Identifiable, Hashable {
    let id: String
    let muxID: Int
    let name: String
    let modelName: String
    let productType: String
    let iosVersion: String
    let buildVersion: String
    let udid: String
    let serialNumber: String
    let connection: ConnectionType
    let isInfoLoaded: Bool
    let batteryLevel: Int?
    let batteryCharging: Bool?
    let batteryCycleCount: Int?
    let storageTotal: Int64?
    let storageFree: Int64?
    let totalSystemCapacity: Int64?
    let amountDataAvailable: Int64?
    let amountRestoreAvailable: Int64?
    let physicalMemory: Int64?
    let cpuArchitecture: String?
    let regionInfo: String?
    let modelNumber: String?
    let activationState: String?
    let hardwarePlatform: String?
    let hardwareModel: String?
    let deviceColor: String?
    let enclosureColor: String?
    let wifiAddress: String?
    let bluetoothAddress: String?

    var isTablet: Bool {
        productType.hasPrefix("iPad")
    }

    var storageUsed: Int64? {
        guard let total = storageTotal, let free = storageFree else { return nil }
        return max(0, total - free)
    }

    var storageUsage: Double? {
        guard let total = storageTotal, total > 0, let used = storageUsed else { return nil }
        return Double(used) / Double(total)
    }

    init(mux: MuxDevice, info: DeviceInfo?, key: String) {
        let productType = info?.productType ?? ""

        id = key
        muxID = mux.deviceID
        name = info?.deviceName ?? L("iOS-устройство")
        self.productType = productType
        modelName = DeviceModelName.marketingName(for: productType) ?? (productType.isEmpty ? L("Неизвестная модель") : productType)
        iosVersion = info?.productVersion ?? "—"
        buildVersion = info?.buildVersion ?? "—"
        udid = info?.uniqueDeviceID ?? mux.serialNumber
        serialNumber = info?.serialNumber ?? mux.serialNumber
        connection = ConnectionType(rawConnectionType: mux.connectionType)
        isInfoLoaded = info != nil
        batteryLevel = info?.batteryLevel
        batteryCharging = info?.batteryCharging
        batteryCycleCount = info?.batteryCycleCount
        storageTotal = info?.totalDiskCapacity ?? info?.totalDataCapacity
        storageFree = info?.effectiveDataAvailable
        totalSystemCapacity = info?.totalSystemCapacity
        amountDataAvailable = info?.amountDataAvailable
        amountRestoreAvailable = info?.amountRestoreAvailable
        physicalMemory = info?.physicalMemory
        cpuArchitecture = info?.cpuArchitecture
        regionInfo = info?.regionInfo
        modelNumber = info?.modelNumber
        activationState = info?.activationState
        hardwarePlatform = info?.hardwarePlatform
        hardwareModel = info?.hardwareModel
        deviceColor = info?.deviceColor
        enclosureColor = info?.enclosureColor
        wifiAddress = info?.wifiAddress
        bluetoothAddress = info?.bluetoothAddress
    }
}

enum ByteFormatter {
    static func string(_ bytes: Int64) -> String {
        guard LocalizationManager.shared.isEnglish else {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }

        // ByteCountFormatter не принимает локаль, поэтому для английского
        // интерфейса форматируем величину вручную.
        let units = ["bytes", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value < 10 ? 2 : 1
        formatter.minimumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
        return "\(number) \(units[index])"
    }
}

enum DeviceModelName {
    static func marketingName(for productType: String) -> String? {
        guard let name = models[productType] else { return nil }
        return localized(name)
    }

    /// В английском интерфейсе переводим русские суффиксы поколений.
    private static func localized(_ name: String) -> String {
        guard LocalizationManager.shared.isEnglish else { return name }
        guard let regex = try? NSRegularExpression(pattern: "\\((\\d+)-го поколения\\)") else {
            return name
        }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        let matches = regex.matches(in: name, options: [], range: range)
        guard !matches.isEmpty else { return name }

        var result = name
        for match in matches.reversed() {
            guard
                let fullRange = Range(match.range(at: 0), in: result),
                let numberRange = Range(match.range(at: 1), in: result),
                let number = Int(result[numberRange])
            else { continue }
            result.replaceSubrange(fullRange, with: "(\(ordinal(number)) generation)")
        }
        return result
    }

    private static func ordinal(_ number: Int) -> String {
        switch number % 100 {
        case 11, 12, 13: return "\(number)th"
        default: break
        }
        switch number % 10 {
        case 1: return "\(number)st"
        case 2: return "\(number)nd"
        case 3: return "\(number)rd"
        default: return "\(number)th"
        }
    }

    private static let models: [String: String] = [
        // iPhone
        "iPhone10,3": "iPhone X",
        "iPhone10,6": "iPhone X",
        "iPhone11,2": "iPhone XS",
        "iPhone11,4": "iPhone XS Max",
        "iPhone11,6": "iPhone XS Max",
        "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2-го поколения)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (3-го поколения)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
        "iPhone18,1": "iPhone 17 Pro",
        "iPhone18,2": "iPhone 17 Pro Max",
        "iPhone18,3": "iPhone 17",
        "iPhone18,4": "iPhone Air",

        // iPad
        "iPad8,1": "iPad Pro 11″",
        "iPad8,2": "iPad Pro 11″",
        "iPad8,3": "iPad Pro 11″",
        "iPad8,4": "iPad Pro 11″",
        "iPad8,5": "iPad Pro 12.9″ (3-го поколения)",
        "iPad8,6": "iPad Pro 12.9″ (3-го поколения)",
        "iPad8,7": "iPad Pro 12.9″ (3-го поколения)",
        "iPad8,8": "iPad Pro 12.9″ (3-го поколения)",
        "iPad8,9": "iPad Pro 11″ (2-го поколения)",
        "iPad8,10": "iPad Pro 11″ (2-го поколения)",
        "iPad8,11": "iPad Pro 12.9″ (4-го поколения)",
        "iPad8,12": "iPad Pro 12.9″ (4-го поколения)",
        "iPad11,1": "iPad mini (5-го поколения)",
        "iPad11,2": "iPad mini (5-го поколения)",
        "iPad11,3": "iPad Air (3-го поколения)",
        "iPad11,4": "iPad Air (3-го поколения)",
        "iPad11,6": "iPad (8-го поколения)",
        "iPad11,7": "iPad (8-го поколения)",
        "iPad12,1": "iPad (9-го поколения)",
        "iPad12,2": "iPad (9-го поколения)",
        "iPad13,1": "iPad Air (4-го поколения)",
        "iPad13,2": "iPad Air (4-го поколения)",
        "iPad13,4": "iPad Pro 11″ (3-го поколения)",
        "iPad13,5": "iPad Pro 11″ (3-го поколения)",
        "iPad13,6": "iPad Pro 11″ (3-го поколения)",
        "iPad13,7": "iPad Pro 11″ (3-го поколения)",
        "iPad13,8": "iPad Pro 12.9″ (5-го поколения)",
        "iPad13,9": "iPad Pro 12.9″ (5-го поколения)",
        "iPad13,10": "iPad Pro 12.9″ (5-го поколения)",
        "iPad13,11": "iPad Pro 12.9″ (5-го поколения)",
        "iPad13,16": "iPad Air (5-го поколения)",
        "iPad13,17": "iPad Air (5-го поколения)",
        "iPad13,18": "iPad (10-го поколения)",
        "iPad13,19": "iPad (10-го поколения)",
        "iPad14,1": "iPad mini (6-го поколения)",
        "iPad14,2": "iPad mini (6-го поколения)",
        "iPad14,3": "iPad Pro 11″ (4-го поколения)",
        "iPad14,4": "iPad Pro 11″ (4-го поколения)",
        "iPad14,5": "iPad Pro 12.9″ (6-го поколения)",
        "iPad14,6": "iPad Pro 12.9″ (6-го поколения)",
        "iPad14,8": "iPad Air 11″ (M2)",
        "iPad14,9": "iPad Air 11″ (M2)",
        "iPad14,10": "iPad Air 13″ (M2)",
        "iPad14,11": "iPad Air 13″ (M2)",
        "iPad16,1": "iPad mini (A17 Pro)",
        "iPad16,2": "iPad mini (A17 Pro)",
        "iPad16,3": "iPad Pro 11″ (M4)",
        "iPad16,4": "iPad Pro 11″ (M4)",
        "iPad16,5": "iPad Pro 13″ (M4)",
        "iPad16,6": "iPad Pro 13″ (M4)",

        // iPod touch
        "iPod9,1": "iPod touch (7-го поколения)"
    ]
}
