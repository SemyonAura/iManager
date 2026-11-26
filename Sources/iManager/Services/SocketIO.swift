import Foundation
import Darwin

/// Низкоуровневые операции чтения/записи для сокетов usbmuxd и lockdownd.
enum SocketIO {
    static func readExactly(fd: Int32, count: Int) throws -> Data {
        guard count > 0 else { return Data() }

        var data = Data(count: count)
        var offset = 0

        while offset < count {
            let bytesRead = data.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.read(fd, base.advanced(by: offset), count - offset)
            }

            if bytesRead == 0 {
                throw SocketError.connectionClosed
            }
            if bytesRead < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw SocketError.timeout
                }
                throw SocketError.io(String(cString: strerror(errno)))
            }
            offset += bytesRead
        }

        return data
    }

    static func writeAll(fd: Int32, data: Data) throws {
        guard !data.isEmpty else { return }

        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let bytesWritten = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if bytesWritten < 0 {
                    if errno == EINTR { continue }
                    if errno == EAGAIN || errno == EWOULDBLOCK {
                        throw SocketError.timeout
                    }
                    throw SocketError.io(String(cString: strerror(errno)))
                }
                offset += bytesWritten
            }
        }
    }
}

enum SocketError: LocalizedError {
    case connectionClosed
    case timeout
    case io(String)

    var errorDescription: String? {
        switch self {
        case .connectionClosed:
            return L("Соединение закрыто удалённой стороной")
        case .timeout:
            return L("Истекло время ожидания ответа")
        case .io(let message):
            return L("Ошибка ввода-вывода: %@", message)
        }
    }
}

extension Data {
    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        var value: UInt32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { destination in
            copyBytes(to: destination, from: offset..<(offset + 4))
        }
        return UInt32(littleEndian: value)
    }

    func readUInt32BE(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        var value: UInt32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { destination in
            copyBytes(to: destination, from: offset..<(offset + 4))
        }
        return UInt32(bigEndian: value)
    }
}
