import Foundation
import Darwin

enum ServerError: Error, LocalizedError {
    case socket(String)
    case alreadyRunning

    var errorDescription: String? {
        switch self {
        case .socket(let message):
            return message
        case .alreadyRunning:
            return "Keylease is already running"
        }
    }
}

struct LeaseRequest: Decodable {
    let op: String
    var argv: [String]?
    var cwd: String?
    var env: [String: String]?
    var value: String?
    var envName: String?
    var ttl: Double?
    var wait: Bool?
    var timeout: Double?
}

final class ClientWriter {
    private let fd: Int32
    private let lock = NSLock()
    private var closed = false
    private var fdClosed = false
    var onFailure: (() -> Void)?

    init(fd: Int32) {
        self.fd = fd
    }

    func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }

        var failure: (() -> Void)?
        lock.lock()
        if closed {
            lock.unlock()
            return
        }

        var payload = data
        payload.append(0x0A)
        let ok = payload.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return true }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
                if written <= 0 {
                    return false
                }
                offset += written
            }
            return true
        }

        if !ok {
            closed = true
            failure = onFailure
        }
        lock.unlock()
        failure?()
    }

    func close() {
        lock.lock()
        closed = true
        let shouldClose = !fdClosed
        fdClosed = true
        lock.unlock()
        if shouldClose {
            Darwin.close(fd)
        }
    }
}

final class Redactor {
    private let secret: String
    private var buffer = ""

    init(secret: String) {
        self.secret = secret
    }

    func feed(_ chunk: String) -> String {
        guard !secret.isEmpty else { return chunk }

        buffer += chunk
        var output = ""

        while let range = buffer.range(of: secret) {
            output += String(buffer[..<range.lowerBound])
            output += "[REDACTED]"
            buffer = String(buffer[range.upperBound...])
        }

        let maximumKeep = min(secret.count - 1, buffer.count)
        var keep = 0
        if maximumKeep > 0 {
            for length in stride(from: maximumKeep, through: 1, by: -1) {
                let suffix = String(buffer.suffix(length))
                if secret.hasPrefix(suffix) {
                    keep = length
                    break
                }
            }
        }

        if keep > 0 {
            output += String(buffer.dropLast(keep))
            buffer = String(buffer.suffix(keep))
        } else {
            output += buffer
            buffer = ""
        }

        return output
    }

    func flush() -> String {
        guard !buffer.isEmpty else { return "" }
        let output = secret.hasPrefix(buffer) ? "[REDACTED]" : buffer
        buffer = ""
        return output
    }
}

final class LeaseServer {
    private let store: LeaseStore
    private let socketPath: String
    private var listenFD: Int32 = -1
    private var running = false
    private let acceptQueue = DispatchQueue(label: "dev.lie.keylease.accept")

    var onShow: (() -> Void)?

    init(store: LeaseStore) {
        self.store = store

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("Keylease", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        socketPath = directory.appendingPathComponent("keylease.sock").path
    }

    func start() throws {
        if isExistingServerAlive() {
            throw ServerError.alreadyRunning
        }

        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ServerError.socket("socket() failed")
        }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(fd)
            throw ServerError.socket("socket path too long")
        }

        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { cString in
                for (index, byte) in pathBytes.enumerated() {
                    cString[index] = byte
                }
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            Darwin.close(fd)
            throw ServerError.socket("bind failed: errno \(errno)")
        }

        chmod(socketPath, 0o600)

        guard Darwin.listen(fd, 16) == 0 else {
            Darwin.close(fd)
            throw ServerError.socket("listen failed: errno \(errno)")
        }

        listenFD = fd
        running = true
        acceptQueue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        running = false
        if listenFD >= 0 {
            shutdown(listenFD, SHUT_RDWR)
            Darwin.close(listenFD)
            listenFD = -1
        }
        unlink(socketPath)
    }

    private func isExistingServerAlive() -> Bool {
        guard FileManager.default.fileExists(atPath: socketPath) else { return false }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return false }

        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { cString in
                for (index, byte) in pathBytes.enumerated() {
                    cString[index] = byte
                }
            }
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
    }

    private func acceptLoop() {
        while running {
            let client = accept(listenFD, nil, nil)
            if client < 0 {
                if !running {
                    break
                }
                continue
            }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleClient(client)
            }
        }
    }

    private func handleClient(_ fd: Int32) {
        let writer = ClientWriter(fd: fd)
        defer { writer.close() }

        guard let request = readRequest(fd) else {
            writer.send(["event": "error", "message": "Invalid request"])
            return
        }

        switch request.op {
        case "run":
            run(request, writer: writer)
        case "wait":
            waitForChannel(request, writer: writer)
        case "set":
            guard let value = request.value, !value.isEmpty else {
                writer.send(["event": "error", "message": "Empty secret"])
                return
            }
            store.activate(
                secret: value,
                ttl: request.ttl ?? LeaseStore.defaultTTL
            )
            writer.send(["event": "ok"])
        case "revoke":
            store.revoke()
            writer.send(["event": "ok"])
        case "show":
            DispatchQueue.main.async { [weak self] in
                self?.onShow?()
            }
            writer.send(["event": "ok"])
        default:
            writer.send(["event": "error", "message": "Unknown op: \(request.op)"])
        }
    }

    private func readRequest(_ fd: Int32) -> LeaseRequest? {
        guard let line = readLine(fd) else { return nil }
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LeaseRequest.self, from: data)
    }

    private func readLine(_ fd: Int32) -> String? {
        var bytes: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = chunk.withUnsafeMutableBytes { buffer -> Int in
                Darwin.recv(fd, buffer.baseAddress, buffer.count, 0)
            }

            if count <= 0 {
                return bytes.isEmpty ? nil : String(bytes: bytes, encoding: .utf8)
            }

            for index in 0..<count {
                let byte = chunk[index]
                if byte == 0x0A {
                    return String(bytes: bytes, encoding: .utf8)
                }
                bytes.append(byte)
            }
        }
    }

    private func run(_ request: LeaseRequest, writer: ClientWriter) {
        guard let argv = request.argv, !argv.isEmpty, !argv[0].isEmpty else {
            writer.send(["event": "error", "message": "Missing command. Usage: keylease run -- <command>"])
            return
        }

        let wait = request.wait ?? false
        let timeout = max(1, request.timeout ?? LeaseStore.defaultTTL)
        var lease = store.consume()

        if lease == nil, wait {
            writer.send(["event": "waiting", "timeout": timeout])
            let deadline = Date().addingTimeInterval(timeout)

            while Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
                lease = store.consume()
                if lease != nil {
                    break
                }
            }
        }

        guard let lease else {
            if wait {
                writer.send([
                    "event": "error",
                    "message": "Timed out waiting for a channel. Open the Keylease menu bar and enable a channel.",
                ])
                return
            }
            writer.send([
                "event": "error",
                "message": "No active channel. Open the Keylease menu bar and enable a channel (default 10 min / 1 use).",
            ])
            return
        }

        let requestedEnvName = request.envName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let envName = requestedEnvName.isEmpty ? LeaseStore.defaultEnvName : requestedEnvName
        guard isValidEnvName(envName) else {
            writer.send([
                "event": "error",
                "message": "Invalid environment variable name: \(envName)",
            ])
            store.refund(lease)
            return
        }

        var environment = request.env ?? [:]
        environment.removeValue(forKey: LeaseStore.defaultEnvName)
        environment[envName] = lease.secret
        if environment["PATH"]?.isEmpty != false {
            environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }

        let cwd = request.cwd ?? FileManager.default.homeDirectoryForCurrentUser.path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = argv
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        writer.send([
            "event": "start",
            "usesLeft": lease.usesLeft,
            "expiresAt": Int(lease.expiresAt.timeIntervalSince1970),
            "envName": envName,
        ])

        let stdoutRedactor = Redactor(secret: lease.secret)
        let stderrRedactor = Redactor(secret: lease.secret)
        let group = DispatchGroup()

        group.enter()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                let tail = stdoutRedactor.flush()
                if !tail.isEmpty {
                    writer.send(["event": "stdout", "data": tail])
                }
                group.leave()
                return
            }

            let text = String(decoding: data, as: UTF8.self)
            let redacted = stdoutRedactor.feed(text)
            if !redacted.isEmpty {
                writer.send(["event": "stdout", "data": redacted])
            }
        }

        group.enter()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                let tail = stderrRedactor.flush()
                if !tail.isEmpty {
                    writer.send(["event": "stderr", "data": tail])
                }
                group.leave()
                return
            }

            let text = String(decoding: data, as: UTF8.self)
            let redacted = stderrRedactor.feed(text)
            if !redacted.isEmpty {
                writer.send(["event": "stderr", "data": redacted])
            }
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            writer.send([
                "event": "error",
                "message": "Failed to start: \(error.localizedDescription)",
            ])
            store.refund(lease)
            return
        }

        writer.onFailure = { [weak process] in
            process?.terminate()
        }

        process.waitUntilExit()
        group.wait()

        let code: Int32
        if process.terminationReason == .uncaughtSignal {
            code = 128 + process.terminationStatus
        } else {
            code = process.terminationStatus
        }

        writer.send(["event": "exit", "code": Int(code)])
    }

    private func waitForChannel(_ request: LeaseRequest, writer: ClientWriter) {
        let timeout = max(1, request.timeout ?? LeaseStore.defaultTTL)
        let deadline = Date().addingTimeInterval(timeout)

        if store.hasActiveLease() {
            writer.send(["event": "ready"])
            return
        }

        writer.send(["event": "waiting", "timeout": timeout])

        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            if store.hasActiveLease() {
                writer.send(["event": "ready"])
                return
            }
        }

        writer.send([
            "event": "error",
            "message": "Timed out waiting for a channel. Open the Keylease menu bar and enable a channel.",
        ])
    }

    private func isValidEnvName(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
    }
}
