import Foundation
import Darwin

struct MuxDevice: Sendable {
    let deviceID: Int
    let serialNumber: String
    let connectionType: String
    let productID: Int
}

enum USBMuxError: LocalizedError {
    case socketCreation(String)
    case connection(String)
    case malformedResponse(String)
    case connectionRefused(Int)

    var errorDescription: String? {
        switch self {
        case .socketCreation(let message):
            return L("Не удалось создать сокет: %@", message)
        case .connection(let message):
            return L("Не удалось подключиться к usbmuxd: %@", message)
        case .malformedResponse(let message):
            return L("Некорректный ответ usbmuxd: %@", message)
        case .connectionRefused(let code):
            return L("usbmuxd отклонил подключение к устройству (код %d)", code)
        }
    }
}

/// Минимальный нативный клиент демона usbmuxd.
/// Работает через UNIX-сокет /var/run/usbmuxd и plist-протокол, без libimobiledevice.
enum USBMuxClient {
    static let socketPath = "/var/run/usbmuxd"

    private enum MessageType: UInt32 {
        case plist = 8
        case connect = 6
    }

    /// Возвращает список подключённых устройств (USB и Wi-Fi).
    static func listDevices(timeout: TimeInterval = 4) throws -> [MuxDevice] {
        let fd = try openSocket(timeout: timeout)
        defer { Darwin.close(fd) }

        let request: [String: Any] = [
            "MessageType": "ListDevices",
            "ClientVersionString": "iManager 0.2.0",
            "ProgName": "iManager",
            "kLibUSBMuxVersion": 3
        ]

        try sendPlist(fd: fd, messageType: .plist, tag: 1, payload: request)
        let response = try receivePlist(fd: fd)

        guard let entries = response["DeviceList"] as? [[String: Any]] else {
            throw USBMuxError.malformedResponse(L("отсутствует поле DeviceList"))
        }

        return entries.compactMap { entry -> MuxDevice? in
            let properties = entry["Properties"] as? [String: Any] ?? [:]
            let deviceID = intValue(properties["DeviceID"]) ?? intValue(entry["DeviceID"]) ?? 0
            guard deviceID > 0 else { return nil }

            return MuxDevice(
                deviceID: deviceID,
                serialNumber: (properties["SerialNumber"] as? String) ?? "",
                connectionType: (properties["ConnectionType"] as? String) ?? "USB",
                productID: intValue(properties["ProductID"]) ?? 0
            )
        }
    }

    /// Открывает туннель к TCP-порту устройства через usbmuxd.
    /// Возвращённый файловый дескриптор переходит во владение вызывающего кода.
    static func connect(deviceID: Int, port: UInt16, timeout: TimeInterval = 6) throws -> Int32 {
        let fd = try openSocket(timeout: timeout)
        var handedOver = false
        defer { if !handedOver { Darwin.close(fd) } }

        // usbmuxd ожидает номер порта в сетевом порядке байт внутри plist-числа.
        let networkPort = Int(UInt16(port).bigEndian)
        let request: [String: Any] = [
            "MessageType": "Connect",
            "DeviceID": deviceID,
            "PortNumber": networkPort,
            "ClientVersionString": "iManager 0.2.0",
            "ProgName": "iManager",
            "kLibUSBMuxVersion": 3
        ]

        try sendPlist(fd: fd, messageType: .connect, tag: 2, payload: request)
        let response = try receivePlist(fd: fd)

        if let result = intValue(response["Number"]), result != 0 {
            throw USBMuxError.connectionRefused(result)
        }
        if let type = response["MessageType"] as? String, type != "Result" {
            throw USBMuxError.malformedResponse(L("ожидался Result, получен %@", type))
        }

        handedOver = true
        return fd
    }

    // MARK: - Сокет

    private static func openSocket(timeout: TimeInterval) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw USBMuxError.socketCreation(String(cString: strerror(errno)))
        }

        var timeval = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeval, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeval, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = Array(socketPath.utf8)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < pathCapacity else {
            Darwin.close(fd)
            throw USBMuxError.connection(L("слишком длинный путь сокета"))
        }

        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(fd)
            throw USBMuxError.connection(message)
        }

        return fd
    }

    // MARK: - Кадрирование usbmuxd

    private static func sendPlist(
        fd: Int32,
        messageType: MessageType,
        tag: UInt32,
        payload: [String: Any]
    ) throws {
        let body = try PropertyListSerialization.data(
            fromPropertyList: payload,
            format: .xml,
            options: 0
        )

        var packet = Data()
        packet.appendUInt32LE(UInt32(16 + body.count))
        packet.appendUInt32LE(1)
        packet.appendUInt32LE(messageType.rawValue)
        packet.appendUInt32LE(tag)
        packet.append(body)

        try SocketIO.writeAll(fd: fd, data: packet)
    }

    private static func receivePlist(fd: Int32) throws -> [String: Any] {
        let header = try SocketIO.readExactly(fd: fd, count: 16)
        let length = Int(header.readUInt32LE(at: 0))

        guard length >= 16, length <= 64 * 1024 * 1024 else {
            throw USBMuxError.malformedResponse(L("некорректная длина пакета: %d", length))
        }

        let body = try SocketIO.readExactly(fd: fd, count: length - 16)
        guard let plist = try PropertyListSerialization.propertyList(
            from: body,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw USBMuxError.malformedResponse(L("plist не является словарём"))
        }

        return plist
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let integer = value as? Int { return integer }
        if let string = value as? String { return Int(string) }
        return nil
    }
}
