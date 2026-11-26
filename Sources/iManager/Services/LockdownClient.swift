import Foundation
import Darwin

struct DeviceInfo: Sendable {
    var deviceName: String?
    var productType: String?
    var productVersion: String?
    var buildVersion: String?
    var uniqueDeviceID: String?
    var serialNumber: String?
    var activationState: String?
    var modelNumber: String?
    var regionInfo: String?
    var cpuArchitecture: String?
    var wifiAddress: String?
    var bluetoothAddress: String?
    var batteryLevel: Int?
    var batteryCharging: Bool?
    var batteryCycleCount: Int?
    var totalDataCapacity: Int64?
    var totalDataAvailable: Int64?
    var totalDiskCapacity: Int64?
    var totalSystemCapacity: Int64?
    var amountDataAvailable: Int64?
    var amountRestoreAvailable: Int64?
    var physicalMemory: Int64?
    var hardwarePlatform: String?
    var hardwareModel: String?
    var deviceColor: String?
    var enclosureColor: String?

    /// «Доступно» так, как это показывает iOS в «Настройках»:
    /// свободное место плюс вытесняемые (purgeable) данные.
    var effectiveDataAvailable: Int64? {
        if let amount = amountDataAvailable, let restore = amountRestoreAvailable {
            return amount + restore
        }
        return totalDataAvailable
    }

    init(values: [String: Any]) {
        deviceName = values["DeviceName"] as? String
        productType = values["ProductType"] as? String
        productVersion = values["ProductVersion"] as? String
        buildVersion = values["BuildVersion"] as? String
        uniqueDeviceID = values["UniqueDeviceID"] as? String
        serialNumber = values["SerialNumber"] as? String
        activationState = values["ActivationState"] as? String
        modelNumber = values["ModelNumber"] as? String
        regionInfo = values["RegionInfo"] as? String
        cpuArchitecture = values["CPUArchitecture"] as? String
        wifiAddress = values["WiFiAddress"] as? String
        bluetoothAddress = values["BluetoothAddress"] as? String
        batteryLevel = LockdownClient.intValue(values["BatteryCurrentCapacity"])
        batteryCharging = values["BatteryIsCharging"] as? Bool
        batteryCycleCount = LockdownClient.intValue(values["BatteryCycleCount"])
        totalDataCapacity = LockdownClient.int64Value(values["TotalDataCapacity"])
        totalDataAvailable = LockdownClient.int64Value(values["TotalDataAvailable"])
        totalDiskCapacity = LockdownClient.int64Value(values["TotalDiskCapacity"])
        totalSystemCapacity = LockdownClient.int64Value(values["TotalSystemCapacity"])
        amountDataAvailable = LockdownClient.int64Value(values["AmountDataAvailable"])
        amountRestoreAvailable = LockdownClient.int64Value(values["AmountRestoreAvailable"])
        physicalMemory = LockdownClient.int64Value(values["PhysicalMemory"])
            ?? LockdownClient.int64Value(values["MemorySize"])
            ?? LockdownClient.int64Value(values["TotalSystemMemory"])
            ?? LockdownClient.int64Value(values["PhysicalMemorySize"])
        hardwarePlatform = values["HardwarePlatform"] as? String
        hardwareModel = values["HardwareModel"] as? String
        deviceColor = values["DeviceColor"] as? String
        enclosureColor = values["DeviceEnclosureColor"] as? String
    }
}

enum LockdownError: LocalizedError {
    case requestFailed(String)
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message):
            return L("lockdownd вернул ошибку: %@", message)
        case .malformedResponse(let message):
            return L("Некорректный ответ lockdownd: %@", message)
        }
    }
}

/// Клиент lockdownd поверх туннеля usbmuxd (порт 62078).
/// На этом этапе выполняется только QueryType All — базовые сведения,
/// доступные без установки доверительных отношений (pairing).
final class LockdownClient {
    private let fd: Int32
    private var isClosed = false

    init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        if !isClosed {
            Darwin.close(fd)
        }
    }

    static func fetchInfo(deviceID: Int, timeout: TimeInterval = 6) throws -> DeviceInfo {
        let fd = try USBMuxClient.connect(deviceID: deviceID, port: 62078, timeout: timeout)
        let client = LockdownClient(fd: fd)
        let values = try client.queryAll()
        return DeviceInfo(values: values)
    }

    func queryAll() throws -> [String: Any] {
        let request: [String: Any] = [
            "Label": "iManager",
            "Request": "QueryType",
            "QueryType": "All"
        ]

        try send(request)
        let response = try receive()

        if let error = response["Error"] as? String {
            throw LockdownError.requestFailed(error)
        }
        if let values = response["Value"] as? [String: Any] {
            return values
        }
        return response
    }

    // MARK: - Кадрирование lockdownd (big-endian длина + plist)

    private func send(_ payload: [String: Any]) throws {
        let body = try PropertyListSerialization.data(
            fromPropertyList: payload,
            format: .xml,
            options: 0
        )

        var packet = Data()
        packet.appendUInt32BE(UInt32(body.count))
        packet.append(body)

        try SocketIO.writeAll(fd: fd, data: packet)
    }

    private func receive() throws -> [String: Any] {
        let header = try SocketIO.readExactly(fd: fd, count: 4)
        let length = Int(header.readUInt32BE(at: 0))

        guard length > 0, length <= 64 * 1024 * 1024 else {
            throw LockdownError.malformedResponse(L("некорректная длина пакета: %d", length))
        }

        let body = try SocketIO.readExactly(fd: fd, count: length)
        guard let plist = try PropertyListSerialization.propertyList(
            from: body,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw LockdownError.malformedResponse(L("plist не является словарём"))
        }

        return plist
    }

    static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let integer = value as? Int { return integer }
        if let string = value as? String { return Int(string) }
        return nil
    }

    static func int64Value(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let integer = value as? Int64 { return integer }
        if let integer = value as? Int { return Int64(integer) }
        if let string = value as? String { return Int64(string) }
        return nil
    }
}
