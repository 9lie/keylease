import Foundation
import Darwin

let usageText = """
keylease — 给 Agent 开一条临时密钥通道

用法:
  keylease run [--env NAME] [--wait] [--timeout 10m] -- <命令...>
                                         用当前通道运行命令；变量名由 Agent 指定
  keylease wait [--timeout 10m]          阻塞等待通道开启
  keylease set [--ttl 10m]
                                         从 stdin 读入密钥并开启通道（默认 10 分钟 / 一次使用）
  keylease revoke                        立即关闭当前通道
  keylease show                          打开菜单栏面板

示例:
  pbpaste | keylease set
  keylease run --env OPENAI_API_KEY -- python app.py
  keylease run --wait --env OPENAI_API_KEY -- python app.py
"""

let socketPath: String = {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return appSupport.appendingPathComponent("Keylease/keylease.sock").path
}()

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("keylease: \(message)\n".utf8))
    exit(1)
}

func usage() -> Never {
    print(usageText)
    exit(0)
}

func openSocket() -> Int32 {
    let pathBytes = socketPath.utf8CString
    guard pathBytes.count <= 104 else {
        fail("socket 路径过长")
    }

    var lastError: Int32 = 0

    for attempt in 0..<20 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            fail("socket() 失败")
        }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)

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

        if result == 0 {
            return fd
        }

        lastError = errno
        Darwin.close(fd)

        if attempt < 19 {
            usleep(200_000)
        }
    }

    FileHandle.standardError.write(
        Data("keylease: 无法连接菜单栏 App（errno \(lastError)）。请先打开 /Applications/Keylease.app\n".utf8)
    )
    exit(1)
}

func sendJSON(_ fd: Int32, _ object: [String: Any]) {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object) else {
        fail("内部错误：无法编码请求")
    }

    var payload = data
    payload.append(0x0A)

    payload.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return }
        var offset = 0
        while offset < buffer.count {
            let written = Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
            if written <= 0 {
                fail("写入失败")
            }
            offset += written
        }
    }
}

func readSocketLine(_ fd: Int32) -> String? {
    var bytes: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 4096)

    while true {
        let count = chunk.withUnsafeMutableBytes { buffer -> Int in
            Darwin.recv(fd, buffer.baseAddress, buffer.count, 0)
        }

        if count <= 0 {
            return nil
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

func readResponses(_ fd: Int32) -> Never {
    while let line = readSocketLine(fd) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String else {
            continue
        }

        switch event {
        case "stdout":
            if let text = object["data"] as? String {
                FileHandle.standardOutput.write(Data(text.utf8))
            }
        case "stderr":
            if let text = object["data"] as? String {
                FileHandle.standardError.write(Data(text.utf8))
            }
        case "exit":
            exit(Int32(object["code"] as? Int ?? 0))
        case "error":
            let message = object["message"] as? String ?? "未知错误"
            fail(message)
        case "ok":
            exit(0)
        case "ready":
            FileHandle.standardError.write(Data("keylease: 通道已开启\n".utf8))
            exit(0)
        case "waiting":
            let timeout = object["timeout"] as? Double ?? 600
            let minutes = Int(timeout / 60)
            let label = minutes >= 1 ? "\(minutes) 分钟" : "\(Int(timeout)) 秒"
            FileHandle.standardError.write(
                Data("keylease: 通道未开启，正在等待（最多 \(label)）……\n".utf8)
            )
        case "start":
            break
        default:
            break
        }
    }

    fail("连接中断")
}

func parseDuration(_ string: String) -> Double {
    if let seconds = Double(string) {
        return seconds
    }

    let units: [(String, Double)] = [
        ("ms", 0.001),
        ("s", 1),
        ("m", 60),
        ("h", 3600),
        ("d", 86400),
    ]

    for (suffix, multiplier) in units {
        if string.hasSuffix(suffix), let value = Double(string.dropLast(suffix.count)) {
            return value * multiplier
        }
    }

    fail("无效时长：\(string)（例如 10m、600、1h）")
}

func readSecretFromStdin() -> String {
    if isatty(STDIN_FILENO) == 1 {
        var original = termios()
        tcgetattr(STDIN_FILENO, &original)

        var hidden = original
        hidden.c_lflag &= ~UInt(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &hidden)

        FileHandle.standardError.write(Data("密钥: ".utf8))
        let line = readLine() ?? ""

        tcsetattr(STDIN_FILENO, TCSANOW, &original)
        FileHandle.standardError.write(Data("\n".utf8))

        return line.trimmingCharacters(in: .newlines)
    }

    let data = FileHandle.standardInput.readDataToEndOfFile()
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
}

func runCommand(_ arguments: [String]) -> Never {
    var envName = "KEYLEASE_SECRET"
    var wait = false
    var timeout: Double = 600
    var command: [String] = []
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]

        if argument == "--" {
            command = Array(arguments.dropFirst(index + 1))
            break
        }

        guard argument.hasPrefix("--") else {
            command = Array(arguments[index...])
            break
        }

        switch argument {
        case "--env":
            index += 1
            guard index < arguments.count else {
                fail("--env 需要一个变量名")
            }
            envName = arguments[index]
        case "--wait":
            wait = true
        case "--timeout":
            index += 1
            guard index < arguments.count else {
                fail("--timeout 需要一个时长")
            }
            timeout = parseDuration(arguments[index])
        default:
            fail("未知参数：\(argument)")
        }

        index += 1
    }

    guard !command.isEmpty else {
        fail("用法：keylease run [--env NAME] [--wait] [--timeout 10m] -- <命令>")
    }

    guard envName.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
        fail("环境变量名不合法：\(envName)")
    }

    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "KEYLEASE_SECRET")

    let request: [String: Any] = [
        "op": "run",
        "argv": command,
        "cwd": FileManager.default.currentDirectoryPath,
        "env": environment,
        "envName": envName,
        "wait": wait,
        "timeout": timeout,
    ]

    let fd = openSocket()
    sendJSON(fd, request)
    readResponses(fd)
}

func waitCommand(_ arguments: [String]) -> Never {
    var timeout: Double = 600
    var index = 0

    while index < arguments.count {
        switch arguments[index] {
        case "--timeout":
            index += 1
            guard index < arguments.count else {
                fail("--timeout 需要一个时长")
            }
            timeout = parseDuration(arguments[index])
        default:
            fail("未知参数：\(arguments[index])")
        }
        index += 1
    }

    let request: [String: Any] = [
        "op": "wait",
        "timeout": timeout,
    ]

    let fd = openSocket()
    sendJSON(fd, request)
    readResponses(fd)
}

func setCommand(_ arguments: [String]) -> Never {
    var ttl: Double = 600
    var index = 0

    while index < arguments.count {
        switch arguments[index] {
        case "--ttl":
            index += 1
            guard index < arguments.count else {
                fail("--ttl 需要一个值")
            }
            ttl = parseDuration(arguments[index])
        default:
            fail("未知参数：\(arguments[index])")
        }
        index += 1
    }

    let secret = readSecretFromStdin()
    guard !secret.isEmpty else {
        fail("密钥为空")
    }

    let request: [String: Any] = [
        "op": "set",
        "value": secret,
        "ttl": ttl,
    ]

    let fd = openSocket()
    sendJSON(fd, request)
    readResponses(fd)
}

func revoke() -> Never {
    let fd = openSocket()
    sendJSON(fd, ["op": "revoke"])
    readResponses(fd)
}

func show() -> Never {
    let fd = openSocket()
    sendJSON(fd, ["op": "show"])
    readResponses(fd)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    usage()
}

switch command {
case "run":
    runCommand(Array(arguments.dropFirst()))
case "wait":
    waitCommand(Array(arguments.dropFirst()))
case "set":
    setCommand(Array(arguments.dropFirst()))
case "revoke":
    revoke()
case "show":
    show()
case "help", "-h", "--help":
    usage()
default:
    fail("未知命令：\(command)\n\n\(usageText)")
}
