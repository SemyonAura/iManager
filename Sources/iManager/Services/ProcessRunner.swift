import Foundation

/// Запускает внешний процесс и отдаёт его вывод построчно (по `\n` или `\r`).
/// Используется для `ipatool`: JSON-логи приходят строками, а прогресс-бар —
/// через `\r`, поэтому оба варианта нужно разбирать на лету.
final class ProcessRunner {
    private let process = Process()
    private let pipe = Pipe()
    private let lock = NSLock()

    private var buffer = Data()
    private var output = Data()
    private var lineHandler: ((String) -> Void)?
    private var waiters: [CheckedContinuation<Int32, Never>] = []
    private var exitStatus: Int32?

    private(set) var isRunning = false

    var processIdentifier: Int32 { process.processIdentifier }

    func start(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        onText: ((String) -> Void)? = nil
    ) throws {
        lineHandler = onText
        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }

        process.standardOutput = pipe
        process.standardError = pipe
        // Не даём дочернему процессу унаследовать терминал: ipatool-cpp при
        // истёкшей сессии может попытаться интерактивно спросить код 2FA.
        process.standardInput = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }

        process.terminationHandler = { [weak self] finished in
            guard let self else { return }
            self.pipe.fileHandleForReading.readabilityHandler = nil
            let remaining = self.pipe.fileHandleForReading.readDataToEndOfFile()
            if !remaining.isEmpty {
                self.consume(remaining)
            }
            self.finish(status: finished.terminationStatus)
        }

        try process.run()
        isRunning = true
    }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }

    func wait() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let exitStatus {
                lock.unlock()
                continuation.resume(returning: exitStatus)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func collectedOutput() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: output, encoding: .utf8) ?? ""
    }

    // MARK: - Private

    private func finish(status: Int32) {
        lock.lock()
        guard exitStatus == nil else {
            lock.unlock()
            return
        }
        exitStatus = status
        isRunning = false
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume(returning: status) }
    }

    private func consume(_ data: Data) {
        var chunks: [String] = []

        lock.lock()
        output.append(data)
        buffer.append(data)

        var start = buffer.startIndex
        var index = start
        while index < buffer.endIndex {
            let byte = buffer[index]
            if byte == 0x0A || byte == 0x0D {
                if index > start {
                    let slice = buffer[start..<index]
                    if let text = String(data: Data(slice), encoding: .utf8) {
                        chunks.append(text)
                    }
                }
                start = index + 1
            }
            index += 1
        }

        if start > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<start)
        }

        // Защита от неограниченного роста, если процесс не пишет переводов строк.
        if buffer.count > 1_048_576 {
            buffer.removeAll(keepingCapacity: true)
        }
        if output.count > 4_194_304 {
            output.removeAll(keepingCapacity: true)
        }

        let handler = lineHandler
        lock.unlock()

        for chunk in chunks {
            handler?(chunk)
        }
    }
}
