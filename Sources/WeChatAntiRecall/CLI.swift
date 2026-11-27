import Foundation
import CoreFoundation
import Darwin

let defaultAppPath = "/Applications/WeChat.app"
let defaultBinaryPath = "Contents/MacOS/WeChat"
private let lcSegment64: UInt32 = 0x19
private let lcLoadDylib: UInt32 = 0xc
private let mhMagic64: UInt32 = 0xfeedfacf
private let fatMagic: UInt32 = 0xcafebabe
private let fatMagic64: UInt32 = 0xcafebabf
private let cpuTypeX8664: Int32 = 0x01000007
private let cpuTypeARM64: Int32 = 0x0100000c

enum ToolError: LocalizedError {
    case usage(String)
    case unsupportedVersion(found: String, supported: [String])
    case invalidConfig(String)
    case invalidHex(String)
    case appInfoMissing(String)
    case notAWechatApp(String)
    case unsupportedMachO(String)
    case addressNotMapped(address: UInt64, file: String)
    case bytesMismatch(address: UInt64, expected: [Data], actual: Data)
    case noMatchingSlice(String)
    case commandFailed(String, Int32)
    case signingEntitlementsMismatch([String])
    case permissionDenied(path: String, operation: String)
    case fileOperationFailed(operation: String, path: String, underlying: String)
    case appIsRunning(path: String, pids: [String])
    case unsupportedAppSignature(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .usage(let message):
            return message
        case .unsupportedVersion(let found, let supported):
            return "当前微信构建号 \(found) 不在补丁配置中。已支持构建号：\(supported.joined(separator: ", "))"
        case .invalidConfig(let message):
            return "补丁配置无效：\(message)"
        case .invalidHex(let value):
            return "十六进制字符串无效：\(value)"
        case .appInfoMissing(let key):
            return "无法从 Info.plist 读取 \(key)"
        case .notAWechatApp(let path):
            return "\(path) 看起来不是 macOS 微信应用"
        case .unsupportedMachO(let path):
            return "不支持的 Mach-O 文件：\(path)"
        case .addressNotMapped(let address, let file):
            return "地址 0x\(String(address, radix: 16)) 无法映射到文件 \(file)"
        case .bytesMismatch(let address, let expected, let actual):
            let expectedText = expected.map(\.hexString).joined(separator: " 或 ")
            return "地址 0x\(String(address, radix: 16)) 原始字节不匹配，期望 \(expectedText)，实际 \(actual.hexString)"
        case .noMatchingSlice(let path):
            return "\(path) 中没有找到配置要求的架构切片"
        case .commandFailed(let command, let status):
            return "\(command) 执行失败，退出码 \(status)"
        case .signingEntitlementsMismatch(let paths):
            return """
            重签名后有 \(paths.count) 个代码对象的 entitlements 与安装前不一致：
            \(paths.joined(separator: "\n"))
            已停止安装结果验证，避免以缺少麦克风、摄像头、网络或扩展权限的签名继续运行。
            """
        case .permissionDenied(let path, let operation):
            return """
            没有权限\(operation)：\(path)
            当前有效用户 ID：\(geteuid())，真实用户 ID：\(getuid())。
            如果有效用户 ID 为 0 仍报此错，说明系统（TCC / App Management）拦截了写操作：
            请在「系统设置 → 隐私与安全性」中给「微信防撤回」开启 App Management，
            必要时同时开启 Full Disk Access，然后完全退出并重新打开「微信防撤回」再试。
            命令行用户请用 sudo 运行，并给所用终端开启上述权限。
            """
        case .fileOperationFailed(let operation, let path, let underlying):
            return """
            \(operation)失败：\(path)
            底层错误：\(underlying)
            当前有效用户 ID：\(geteuid())。如果已经通过 sudo 运行但底层错误是 Operation not permitted，请在 macOS 系统设置的 Privacy & Security 中给当前终端应用开启 App Management，必要时同时开启 Full Disk Access，然后退出并重新打开终端再试。
            """
        case .appIsRunning(let path, let pids):
            return """
            WeChat 仍在运行，不能在运行中修改或恢复 app bundle：\(path)
            正在运行的进程 PID：\(pids.joined(separator: ", "))
            请先完全退出微信，再重新运行命令。运行中修改二进制可能触发 macOS Code Signature Invalid 崩溃。
            """
        case .unsupportedAppSignature(let path, let reason):
            return """
            拒绝修改这个微信副本：\(path)
            原因：\(reason)

            App Store 渠道的微信由 Apple 的 "Software Signing" 身份签名，bundle 内含
            Contents/_MASReceipt/receipt；本工具只能做 ad-hoc 重签名，会破坏它并导致微信无法启动。
            正确做法：完全退出并卸载微信，从微信官网 https://weixin.qq.com/ 下载官方 dmg
            重新安装（4.2.0.54 / 构建号 270390），再用本工具开启。

            注意：本工具成功开启后，微信本身就会变成 ad-hoc 签名、TeamIdentifier 为空，
            这是正常的安装结果，不是错误；请勿因此重复卸载重装。
            """
        }
    }
}

enum CPUArch: String, Decodable, Hashable {
    case arm64
    case x86_64

    var cpuType: Int32 {
        switch self {
        case .arm64:
            return cpuTypeARM64
        case .x86_64:
            return cpuTypeX8664
        }
    }
}

struct PatchEntry: Decodable, Hashable {
    let arch: CPUArch
    let address: UInt64
    let patchBytes: Data
    let expectedBytes: [Data]

    enum CodingKeys: String, CodingKey {
        case arch
        case address = "addr"
        case patchBytes = "asm"
        case expectedBytes = "expected"
    }

    init(arch: CPUArch, address: UInt64, patchBytes: Data, expectedBytes: [Data]) {
        self.arch = arch
        self.address = address
        self.patchBytes = patchBytes
        self.expectedBytes = expectedBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        arch = try container.decode(CPUArch.self, forKey: .arch)

        let addressString = try container.decode(String.self, forKey: .address)
        guard let parsedAddress = UInt64(addressString, radix: 16) else {
            throw ToolError.invalidHex(addressString)
        }
        address = parsedAddress

        let patchString = try container.decode(String.self, forKey: .patchBytes)
        patchBytes = try Data(hexString: patchString)

        if container.contains(.expectedBytes) {
            if let expectedString = try? container.decode(String.self, forKey: .expectedBytes) {
                expectedBytes = [try Data(hexString: expectedString)]
            } else if let expectedStrings = try? container.decode([String].self, forKey: .expectedBytes) {
                expectedBytes = try expectedStrings.map { try Data(hexString: $0) }
            } else {
                throw ToolError.invalidConfig("addr \(addressString) 的 expected 必须是字符串或字符串数组")
            }
        } else {
            expectedBytes = []
        }
    }
}

struct PatchTarget: Decodable {
    let identifier: String
    let binary: String?
    let entries: [PatchEntry]

    var binaryPath: String {
        binary ?? defaultBinaryPath
    }
}

struct VersionConfig: Decodable {
    let version: String
    let targets: [PatchTarget]
}

struct AppInfo {
    let appURL: URL
    let executableURL: URL
    let shortVersion: String
    let buildVersion: String
    let bundleIdentifier: String
}

enum PatchStatus {
    case patched
    case wouldPatch
    case alreadyPatched
}

struct PatchReport {
    let arch: CPUArch
    let address: UInt64
    let fileOffset: UInt64
    let status: PatchStatus
}



@main
struct WeChatAntiRecall {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            try CLI().run(arguments: arguments)
        } catch {
            // In --json mode, emit a structured error envelope to stdout (still exit 1) so
            // the GUI has one machine-readable channel for both success and failure.
            if arguments.contains("--json") {
                JSONOutput.emit(ErrorEnvelope(error))
            } else {
                fputs("error: \(error.localizedDescription)\n", stderr)
            }
            exit(1)
        }
    }
}

struct CLI {
    func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            printUsage()
            return
        }

        let rest = Array(arguments.dropFirst())
        switch command {
        case "versions":
            try versions(rest)
        case "install", "patch":
            try install(rest)
        case "restore":
            try restore(rest)
        case "clone":
            try clone(rest)
        case "help", "--help", "-h":
            printUsage()
        default:
            throw ToolError.usage("未知命令：\(command)。支持命令：versions、install、restore、clone。运行 `wechat-antirecall help` 查看用法。")
        }
    }

    private func versions(_ arguments: [String]) throws {
        let options = try CommonOptions(arguments)
        let configs = try loadConfigs(path: options.configPath)
        let appInfo = try readAppInfo(appPath: options.appPath)

        if options.json {
            JSONOutput.emit(VersionsReport(appInfo: appInfo, configs: configs))
            return
        }

        print("WeChat: \(appInfo.shortVersion) (\(appInfo.buildVersion))")
        print("Bundle: \(appInfo.bundleIdentifier)")
        print("Executable: \(appInfo.executableURL.path)")
        print("")
        print("Supported patch targets:")
        for config in configs {
            print("- \(config.version): \(config.targets.map(\.identifier).joined(separator: ", "))")
        }
        if configs.contains(where: { $0.version == appInfo.buildVersion }) {
            print("")
            print("Status: current WeChat build is supported.")
        } else {
            print("")
            print("Status: current WeChat build is not supported by patches.json.")
        }
    }

    private func install(_ arguments: [String]) throws {
        let options = try InstallOptions(arguments)
        let configs = try loadConfigs(path: options.configPath)
        let appInfo = try readAppInfo(appPath: options.appPath)
        try validateAppSignatureIsPatchable(appURL: appInfo.appURL)
        let config = try configForInstalledApp(appInfo, configs: configs)
        let targetIdentifier = options.withTip ? "revoke-tip" : "revoke"
        guard let target = config.targets.first(where: { $0.identifier == targetIdentifier }) else {
            throw ToolError.invalidConfig("构建号 \(config.version) 没有 \(targetIdentifier) 目标；该构建号可能只支持静默防撤回。")
        }
        let targets = [target]
        let modeLabel = options.withTip ? "patch with recall tip" : "patch silent"
        let modeComponents = [modeLabel]
        var patchedBinaries: [URL] = []
        var backedUpBinaryPaths = Set<String>()
        var jsonTargetReports: [InstallReport.TargetReportDTO] = []

        func emitInstallJSON(resigned: Bool) {
            JSONOutput.emit(InstallReport(
                schemaVersion: jsonSchemaVersion,
                dryRun: options.dryRun,
                resigned: resigned,
                app: AppInfoDTO(appInfo),
                mode: modeComponents,
                targets: jsonTargetReports
            ))
        }

        if !options.json {
            print("WeChat: \(appInfo.shortVersion) (\(appInfo.buildVersion))")
            print(options.dryRun ? "Mode: dry-run (\(modeLabel))" : "Mode: \(modeLabel)")
            print("Checking whether WeChat is running...")
        }
        try ensureAppNotRunning(appInfo: appInfo, dryRun: options.dryRun)
        if !options.json { print("Checking install permissions...") }
        try validateInstallPermissions(appInfo: appInfo, targets: targets, options: options)

        for target in targets {
            let binaryURL = appInfo.appURL.appendingPathComponent(target.binaryPath)
            if !FileManager.default.fileExists(atPath: binaryURL.path) {
                throw ToolError.invalidConfig("找不到目标二进制：\(target.binaryPath)")
            }
            patchedBinaries.append(binaryURL)

            if !options.dryRun && !options.noBackup && backedUpBinaryPaths.insert(binaryURL.standardizedFileURL.path).inserted {
                if !options.json { print("Creating backup for \(target.binaryPath)...") }
                let backupURL = try makeBackup(of: binaryURL)
                if !options.json { print("Backup: \(backupURL.path)") }
            }

            let reports = try MachOPatcher(fileURL: binaryURL).patch(entries: target.entries, dryRun: options.dryRun)
            jsonTargetReports.append(InstallReport.TargetReportDTO(
                identifier: target.identifier,
                binary: target.binaryPath,
                entries: reports.map(InstallReport.EntryReportDTO.init)
            ))
            if !options.json {
                print("Patched target: \(target.binaryPath)")
                for report in reports {
                    let statusText: String
                    switch report.status {
                    case .patched: statusText = "patched"
                    case .wouldPatch: statusText = "would patch"
                    case .alreadyPatched: statusText = "already patched"
                    }
                    print("  - \(report.arch.rawValue) 0x\(String(report.address, radix: 16)) -> file+0x\(String(report.fileOffset, radix: 16)) (\(statusText))")
                }
            }
        }

        if options.dryRun {
            if options.json {
                emitInstallJSON(resigned: false)
            } else {
                print("Dry-run complete. No files were changed.")
            }
            return
        }

        var resigned = false
        if options.skipResign {
            if !options.json { print("Skipped code signing.") }
        } else {
            try resign(appURL: appInfo.appURL, nestedBinaries: patchedBinaries)
            resigned = true
            if !options.json { print("Code signing complete.") }
        }

        if options.json {
            emitInstallJSON(resigned: resigned)
        }
    }

    private func restore(_ arguments: [String]) throws {
        let options = try RestoreOptions(arguments)
        let appInfo = try readAppInfo(appPath: options.appPath)
        let binaryURL = appInfo.appURL.appendingPathComponent(options.binaryPath)
        let backupURL = URL(fileURLWithPath: options.backupPath)

        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw ToolError.usage("备份文件不存在：\(backupURL.path)")
        }

        try ensureAppNotRunning(appInfo: appInfo, dryRun: false)
        let data = try Data(contentsOf: backupURL)
        try validateRestorePermissions(appInfo: appInfo, binaryURL: binaryURL, skipResign: options.skipResign)
        try data.write(to: binaryURL, options: .atomic)
        print("Restored \(options.binaryPath) from \(backupURL.path)")

        if options.skipResign {
            print("Skipped code signing.")
        } else {
            try resign(appURL: appInfo.appURL, nestedBinaries: [binaryURL])
            print("Code signing complete.")
        }
    }

    private func printUsage() {
        print("""
        wechat-antirecall (anti-recall + multi-instance clone)

        Usage:
          wechat-antirecall versions [--app /Applications/WeChat.app] [--config patches.json] [--json]
          wechat-antirecall install  [--app /Applications/WeChat.app] [--config patches.json] [--with-tip] [--dry-run] [--no-backup] [--skip-resign] [--json]
          wechat-antirecall restore  --backup <path> [--binary Contents/Resources/wechat.dylib] [--app /Applications/WeChat.app] [--skip-resign]
          wechat-antirecall clone list   [--output-dir /Applications] [--config patches.json] [--json]
          wechat-antirecall clone create [--app /Applications/WeChat.app] [--output-dir /Applications] [--index <N>] [--patch-mode none|silent|with-tip] [--config patches.json] [--replace] [--keep-url-schemes] [--dry-run] [--skip-resign] [--json]
          wechat-antirecall clone remove --target <path> [--dry-run] [--json]

        Notes:
          Supported builds: 270390 and 270601 (silent + --with-tip native recall notice), 270416 (silent only).
          --with-tip keeps the message AND shows WeChat's own "recalled a message" notice.
          `clone` creates standalone WeChat app bundles with isolated bundle IDs and localized names.
          Unknown WeChat builds are refused for binary patching instead of guessed.
          --json emits machine-readable output (used by the GUI); on error it prints a JSON
          envelope to stdout and still exits non-zero.
        """)
    }
}

struct CommonOptions {
    var appPath = defaultAppPath
    var configPath: String?
    var json = false

    init(_ arguments: [String]) throws {
        var parser = ArgumentCursor(arguments)
        while let argument = parser.next() {
            switch argument {
            case "--app":
                appPath = try parser.requiredValue(after: argument)
            case "--config":
                configPath = try parser.requiredValue(after: argument)
            case "--json":
                json = true
            default:
                throw ToolError.usage("未知参数：\(argument)")
            }
        }
    }
}

struct InstallOptions {
    var appPath = defaultAppPath
    var configPath: String?
    var dryRun = false
    var noBackup = false
    var skipResign = false
    /// true = keep the message AND show WeChat's own recall notice (revoke-tip target).
    var withTip = false
    var json = false

    var targetIdentifiers: [String] {
        [withTip ? "revoke-tip" : "revoke"]
    }

    init(_ arguments: [String]) throws {
        var parser = ArgumentCursor(arguments)
        while let argument = parser.next() {
            switch argument {
            case "--app":
                appPath = try parser.requiredValue(after: argument)
            case "--config":
                configPath = try parser.requiredValue(after: argument)
            case "--dry-run":
                dryRun = true
            case "--no-backup":
                noBackup = true
            case "--skip-resign":
                skipResign = true
            case "--with-tip":
                withTip = true
            case "--json":
                json = true
            default:
                throw ToolError.usage("未知参数：\(argument)。本精简版支持静默防撤回（默认）与 --with-tip 原生撤回提示。")
            }
        }
    }
}

struct RestoreOptions {
    var appPath = defaultAppPath
    var binaryPath = defaultBinaryPath
    var backupPath = ""
    var skipResign = false

    init(_ arguments: [String]) throws {
        var parsedBackupPath: String?
        var parser = ArgumentCursor(arguments)
        while let argument = parser.next() {
            switch argument {
            case "--app":
                appPath = try parser.requiredValue(after: argument)
            case "--binary":
                binaryPath = try parser.requiredValue(after: argument)
            case "--backup":
                parsedBackupPath = try parser.requiredValue(after: argument)
            case "--skip-resign":
                skipResign = true
            default:
                throw ToolError.usage("未知参数：\(argument)")
            }
        }

        guard let parsedBackupPath else {
            throw ToolError.usage("restore 需要 --backup <path>")
        }

        backupPath = parsedBackupPath
    }
}

struct ArgumentCursor {
    private let arguments: [String]
    private var index = 0

    init(_ arguments: [String]) {
        self.arguments = arguments
    }

    mutating func next() -> String? {
        guard index < arguments.count else {
            return nil
        }
        let value = arguments[index]
        index += 1
        return value
    }

    mutating func requiredValue(after option: String) throws -> String {
        guard let value = next(), !value.hasPrefix("--") else {
            throw ToolError.usage("\(option) 需要一个值")
        }
        return value
    }
}

final class MachOPatcher {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func patch(entries: [PatchEntry], dryRun: Bool) throws -> [PatchReport] {
        let handle: FileHandle = dryRun
            ? try FileHandle(forReadingFrom: fileURL)
            : try FileHandle(forUpdating: fileURL)
        defer {
            try? handle.close()
        }

        let magicData = try handle.readData(at: 0, length: 4)
        let nativeMagic = magicData.leUInt32(at: 0)
        let bigEndianMagic = magicData.beUInt32(at: 0)

        if bigEndianMagic == fatMagic || bigEndianMagic == fatMagic64 {
            return try patchFat(handle: handle, is64BitFat: bigEndianMagic == fatMagic64, entries: entries, dryRun: dryRun)
        }

        if nativeMagic == mhMagic64 {
            return try patchThin(handle: handle, machOffset: 0, entries: entries, dryRun: dryRun)
        }

        throw ToolError.unsupportedMachO(fileURL.path)
    }

    private func patchFat(handle: FileHandle, is64BitFat: Bool, entries: [PatchEntry], dryRun: Bool) throws -> [PatchReport] {
        let nfat = Int(try handle.readData(at: 4, length: 4).beUInt32(at: 0))
        var offset: UInt64 = 8
        var reports: [PatchReport] = []

        for _ in 0..<nfat {
            let length = is64BitFat ? 32 : 20
            let data = try handle.readData(at: offset, length: length)
            let cpuType = Int32(bitPattern: data.beUInt32(at: 0))
            let sliceOffset = is64BitFat ? data.beUInt64(at: 8) : UInt64(data.beUInt32(at: 8))
            offset += UInt64(length)

            let matchingEntries = entries.filter { $0.arch.cpuType == cpuType }
            guard !matchingEntries.isEmpty else {
                continue
            }

            let sliceReports = try patchThin(handle: handle, machOffset: sliceOffset, entries: matchingEntries, dryRun: dryRun)
            reports.append(contentsOf: sliceReports)
        }

        if reports.isEmpty {
            throw ToolError.noMatchingSlice(fileURL.path)
        }

        return reports
    }

    private func patchThin(handle: FileHandle, machOffset: UInt64, entries: [PatchEntry], dryRun: Bool) throws -> [PatchReport] {
        let header = try handle.readData(at: machOffset, length: 32)
        guard header.leUInt32(at: 0) == mhMagic64 else {
            throw ToolError.unsupportedMachO(fileURL.path)
        }

        let cpuType = Int32(bitPattern: header.leUInt32(at: 4))
        let ncmds = Int(header.leUInt32(at: 16))
        let matchingEntries = entries.filter { $0.arch.cpuType == cpuType }
        guard !matchingEntries.isEmpty else {
            return []
        }

        var reports: [PatchReport] = []
        for entry in matchingEntries {
            let mappedOffset = try mappedFileOffset(forAddress: entry.address, byteCount: entry.patchBytes.count, handle: handle, machOffset: machOffset, ncmds: ncmds)
            let actualBytes = try handle.readData(at: mappedOffset, length: entry.patchBytes.count)

            if actualBytes == entry.patchBytes {
                reports.append(PatchReport(arch: entry.arch, address: entry.address, fileOffset: mappedOffset, status: .alreadyPatched))
                continue
            }

            if !entry.expectedBytes.isEmpty && !entry.expectedBytes.contains(actualBytes) {
                throw ToolError.bytesMismatch(address: entry.address, expected: entry.expectedBytes, actual: actualBytes)
            }

            if dryRun {
                reports.append(PatchReport(arch: entry.arch, address: entry.address, fileOffset: mappedOffset, status: .wouldPatch))
            } else {
                try handle.seek(toOffset: mappedOffset)
                handle.write(entry.patchBytes)
                reports.append(PatchReport(arch: entry.arch, address: entry.address, fileOffset: mappedOffset, status: .patched))
            }
        }

        return reports
    }

    private func mappedFileOffset(forAddress address: UInt64, byteCount: Int, handle: FileHandle, machOffset: UInt64, ncmds: Int) throws -> UInt64 {
        var commandOffset = machOffset + 32
        for _ in 0..<ncmds {
            let command = try handle.readData(at: commandOffset, length: 8)
            let cmd = command.leUInt32(at: 0)
            let cmdsize = UInt64(command.leUInt32(at: 4))

            if cmd == lcSegment64 {
                let segment = try handle.readData(at: commandOffset, length: 72)
                let vmaddr = segment.leUInt64(at: 24)
                let vmsize = segment.leUInt64(at: 32)
                let fileoff = segment.leUInt64(at: 40)
                let filesize = segment.leUInt64(at: 48)
                let endAddress = address + UInt64(byteCount)

                if address >= vmaddr && endAddress <= vmaddr + vmsize {
                    let relative = address - vmaddr
                    if relative + UInt64(byteCount) <= filesize {
                        return machOffset + fileoff + relative
                    }
                }
            }

            commandOffset += cmdsize
        }

        throw ToolError.addressNotMapped(address: address, file: fileURL.path)
    }
}

func loadConfigs(path: String?) throws -> [VersionConfig] {
    let configURL = try resolveConfigURL(path: path)
    let data = try Data(contentsOf: configURL)
    return try JSONDecoder().decode([VersionConfig].self, from: data)
}

private func resolveConfigURL(path: String?) throws -> URL {
    if let path {
        return URL(fileURLWithPath: path)
    }

    let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("patches.json")
    if FileManager.default.fileExists(atPath: cwdURL.path) {
        return cwdURL
    }

    let executableDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let executableConfig = executableDir.appendingPathComponent("patches.json")
    if FileManager.default.fileExists(atPath: executableConfig.path) {
        return executableConfig
    }

    throw ToolError.invalidConfig("找不到 patches.json，请使用 --config 指定路径")
}

private func isSafePreferenceDomain(_ domain: String) -> Bool {
    let components = domain.split(separator: ".", omittingEmptySubsequences: false)
    guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty }) else { return false }
    return domain.unicodeScalars.allSatisfy { scalar in
        let value = scalar.value
        let isASCIILetter = (65...90).contains(value) || (97...122).contains(value)
        let isDigit = (48...57).contains(value)
        return isASCIILetter || isDigit || scalar == "." || scalar == "-"
    }
}

func readAppInfo(appPath: String) throws -> AppInfo {
    let appURL = URL(fileURLWithPath: appPath)
    var isDirectory = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: appURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw ToolError.notAWechatApp(appPath)
    }

    let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
    let plistData = try Data(contentsOf: plistURL)
    var plistFormat = PropertyListSerialization.PropertyListFormat.xml
    guard let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: &plistFormat) as? [String: Any] else {
        throw ToolError.notAWechatApp(appPath)
    }

    guard let executable = plist["CFBundleExecutable"] as? String else {
        throw ToolError.appInfoMissing("CFBundleExecutable")
    }
    guard let shortVersion = plist["CFBundleShortVersionString"] as? String else {
        throw ToolError.appInfoMissing("CFBundleShortVersionString")
    }
    guard let buildVersion = plist["CFBundleVersion"] as? String else {
        throw ToolError.appInfoMissing("CFBundleVersion")
    }
    guard let bundleIdentifier = plist["CFBundleIdentifier"] as? String else {
        throw ToolError.appInfoMissing("CFBundleIdentifier")
    }
    guard isSafePreferenceDomain(bundleIdentifier) else {
        throw ToolError.notAWechatApp(appPath)
    }
    let isOfficialWechat = bundleIdentifier == "com.tencent.xinWeChat" || bundleIdentifier == "com.tencent.xin"
    guard isOfficialWechat else {
        throw ToolError.notAWechatApp(appPath)
    }

    return AppInfo(
        appURL: appURL,
        executableURL: appURL.appendingPathComponent("Contents/MacOS/\(executable)"),
        shortVersion: shortVersion,
        buildVersion: buildVersion,
        bundleIdentifier: bundleIdentifier
    )
}

func configForInstalledApp(_ appInfo: AppInfo, configs: [VersionConfig]) throws -> VersionConfig {
    if let config = configs.first(where: { $0.version == appInfo.buildVersion }) {
        return config
    }
    throw ToolError.unsupportedVersion(found: appInfo.buildVersion, supported: configs.map(\.version))
}


private func validateInstallPermissions(
    appInfo: AppInfo,
    targets: [PatchTarget],
    options: InstallOptions
) throws {
    guard !options.dryRun else {
        return
    }

    for target in targets {
        let binaryURL = appInfo.appURL.appendingPathComponent(target.binaryPath)
        guard FileManager.default.fileExists(atPath: binaryURL.path) else {
            continue
        }

        try requireWritable(binaryURL, operation: "修改目标二进制")

        if !options.noBackup {
            try requireDirectoryWritable(binaryURL.deletingLastPathComponent(), operation: "在目标目录创建备份")
        }
    }

    if !options.skipResign {
        try requireDirectoryWritable(appInfo.appURL, operation: "重签名 WeChat.app")
    }
}

private func validateRestorePermissions(appInfo: AppInfo, binaryURL: URL, skipResign: Bool) throws {
    try requireWritable(binaryURL, operation: "恢复目标二进制")

    if !skipResign {
        try requireDirectoryWritable(appInfo.appURL, operation: "重签名 WeChat.app")
    }
}

func ensureAppNotRunning(appInfo: AppInfo, dryRun: Bool) throws {
    try ensureAppAtURLNotRunning(appInfo.appURL, dryRun: dryRun)
}

func ensureAppAtURLNotRunning(_ appURL: URL, dryRun: Bool) throws {
    guard !dryRun else {
        return
    }

    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-axo", "pid=,comm="]
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw ToolError.commandFailed("/bin/ps -axo pid=,comm=", process.terminationStatus)
    }

    let text = String(data: output, encoding: .utf8) ?? ""
    let runningPIDs = text.split(separator: "\n").compactMap { line -> String? in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let separator = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return nil
        }

        let pid = String(trimmed[..<separator])
        let command = String(trimmed[separator...]).trimmingCharacters(in: .whitespaces)
        if processExecutablePath(command, belongsToAppAt: appURL) {
            return pid
        }
        return nil
    }

    if !runningPIDs.isEmpty {
        throw ToolError.appIsRunning(path: appURL.path, pids: runningPIDs)
    }
}

func processExecutablePath(_ candidatePath: String, belongsToAppAt appURL: URL) -> Bool {
    let appPath = appURL
        .standardizedFileURL
        .resolvingSymlinksInPath()
        .standardizedFileURL
        .path
    let candidate = URL(fileURLWithPath: candidatePath)
        .standardizedFileURL
        .resolvingSymlinksInPath()
        .standardizedFileURL
        .path
    let appPrefix = appPath.hasSuffix("/") ? appPath : "\(appPath)/"
    return candidate == appPath || candidate.hasPrefix(appPrefix)
}

/// Channel check, kept as a pure function so it can be unit tested.
///
/// The ONLY reliable App Store signal is `Contents/_MASReceipt/receipt`: the official
/// weixin.qq.com dmg never has one, and ad-hoc re-signing does not create one. Signature
/// state is NOT a channel signal — every successful install by this tool leaves the app
/// ad-hoc with no Authority at all. Judging by `Signature=adhoc` (or by a missing
/// `Developer ID Application` Authority) made every post-install detection fail with
/// "unsupportedAppSignature" even though the patch was already applied and verified.
enum AppSignaturePolicy {
    enum Verdict: Equatable {
        case patchable
        case appStoreChannel(reason: String)
    }

    static func classify(hasMASReceipt: Bool, codesignInfo: String) -> Verdict {
        if hasMASReceipt {
            return .appStoreChannel(
                reason: "bundle 内存在 Contents/_MASReceipt/receipt，这是 App Store 渠道版本"
            )
        }
        if codesignInfo.contains("Authority=Software Signing") ||
            (codesignInfo.contains("Apple Code Signing Certification Authority") &&
                !codesignInfo.contains("Developer ID Application")) {
            return .appStoreChannel(
                reason: "当前签名是 Apple Software Signing（App Store 版本），不是官网 Developer ID 版"
            )
        }
        // Pristine official dmg (Developer ID) and this tool's own install result (ad-hoc)
        // are both safe. Anything else falls through to the byte-level checks.
        return .patchable
    }
}

func validateAppSignatureIsPatchable(appURL: URL) throws {
    let hasMASReceipt = FileManager.default.fileExists(
        atPath: appURL.appendingPathComponent("Contents/_MASReceipt/receipt").path
    )
    let result = try captureProcessOutput(
        "/usr/bin/codesign", ["-dv", "--verbose=4", appURL.path]
    )
    let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
    let stderr = String(data: result.stderr, encoding: .utf8) ?? ""

    switch AppSignaturePolicy.classify(hasMASReceipt: hasMASReceipt, codesignInfo: stdout + stderr) {
    case .patchable:
        return
    case .appStoreChannel(let reason):
        throw ToolError.unsupportedAppSignature(path: appURL.path, reason: reason)
    }
}

private func requireWritable(_ url: URL, operation: String) throws {
    // access(_:W_OK) checks the REAL uid, not the effective uid. When the GUI elevates via
    // `osascript ... with administrator privileges`, only the effective uid becomes root;
    // the real uid stays as the invoking user. That made access() falsely report no-write on
    // root-owned targets like /Applications/WeChat.app/.../wechat.dylib even though the
    // subsequent write (which uses the effective uid) succeeds. Probe with a real write
    // handle instead — opening without writing reflects the credentials the actual patch
    // will use and does not modify the file.
    let fd = url.path.withCString { Darwin.open($0, O_WRONLY) }
    guard fd >= 0 else {
        throw ToolError.permissionDenied(path: url.path, operation: operation)
    }
    Darwin.close(fd)
}

func requireDirectoryWritable(_ url: URL, operation: String) throws {
    // Same reason as requireWritable: use a real create/delete probe rather than access().
    let probeURL = url.appendingPathComponent(".wechat-antirecall-write-test-\(UUID().uuidString)")
    do {
        try Data().write(to: probeURL, options: .withoutOverwriting)
        try FileManager.default.removeItem(at: probeURL)
    } catch {
        try? FileManager.default.removeItem(at: probeURL)
        throw ToolError.fileOperationFailed(
            operation: operation,
            path: url.path,
            underlying: error.localizedDescription
        )
    }
}

private func makeBackup(of fileURL: URL) throws -> URL {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let suffix = formatter.string(from: Date())
    let backupURL = fileURL
        .deletingLastPathComponent()
        .appendingPathComponent("\(fileURL.lastPathComponent).wechat-antirecall-backup-\(suffix)")

    do {
        let data = try Data(contentsOf: fileURL)
        try data.write(to: backupURL, options: .withoutOverwriting)
    } catch {
        throw ToolError.fileOperationFailed(
            operation: "创建备份",
            path: backupURL.path,
            underlying: error.localizedDescription
        )
    }

    return backupURL
}

/// Ad-hoc re-signing preserves Hardened Runtime (`--preserve-metadata=...,runtime`) and the
/// original entitlements, which is correct in principle but breaks the app in two ways under an
/// ad-hoc identity:
///
/// 1. WeChat's entitlements carry Tencent's Team ID via `com.apple.application-identifier`
///    (5A4RE8SF68…), so AMFI treats the re-signed main binary as belonging to that Team ID,
///    while the re-signed frameworks are Team-less ad-hoc. Launching then aborts with "mapping
///    process and mapped file (non-platform) have different Team IDs" the moment the main binary
///    loads one of its own frameworks (e.g. WCDYWrapper.framework). Disabling library validation
///    fixes this.
/// 2. At login, `wechat.dylib` jumps into anonymously mapped RX memory (runtime-generated code
///    next to roam_server.framework's `__LINKEDIT`). Hardened Runtime rejects unsigned anonymous
///    executable pages with `Invalid Page` (SIGKILL, Namespace CODESIGNING). The original
///    Developer-ID build runs this via `allow-jit`, but that only covers `MAP_JIT` mappings;
///    `allow-unsigned-executable-memory` additionally covers plain mmap'd RX trampolines, which
///    the Tencent code path uses under the re-signed identity.
///
/// Both entitlements are injected on every component that already carries entitlements. Returns
/// the input unchanged when there are no entitlements or the plist cannot be parsed.
private func injectDisableLibraryValidation(_ entitlements: Data?) -> Data? {
    guard let entitlements else { return nil }
    guard var dictionary = try? PropertyListSerialization.propertyList(
        from: entitlements,
        options: [],
        format: nil
    ) as? [String: Any] else {
        return entitlements
    }
    dictionary["com.apple.security.cs.disable-library-validation"] = true
    dictionary["com.apple.security.cs.allow-unsigned-executable-memory"] = true
    return (try? PropertyListSerialization.data(
        fromPropertyList: dictionary,
        format: .xml,
        options: 0
    )) ?? entitlements
}

struct CodeSigningEntitlementsSnapshot {
    struct Entry {
        let url: URL
        let plistData: Data?
    }

    let entries: [Entry]

    static let empty = CodeSigningEntitlementsSnapshot(entries: [])

    static func capture(in appURL: URL) throws -> CodeSigningEntitlementsSnapshot {
        var entries: [Entry] = []
        for candidate in codeSigningCandidates(in: appURL) {
            if let signedCode = try inspectSignedCode(at: candidate) {
                entries.append(Entry(url: candidate, plistData: injectDisableLibraryValidation(signedCode.entitlements)))
            }
        }
        return CodeSigningEntitlementsSnapshot(entries: entries)
    }

    func plistData(for url: URL) -> Data? {
        let path = url.standardizedFileURL.path
        return entries.first { $0.url.standardizedFileURL.path == path }?.plistData
    }

    func mismatchingPaths() throws -> [String] {
        var mismatches: [String] = []
        for entry in entries {
            guard let inspected = try inspectSignedCode(at: entry.url) else {
                mismatches.append(entry.url.path)
                continue
            }

            switch (entry.plistData, inspected.entitlements) {
            case (nil, nil):
                break
            case let (expected?, current?) where entitlementPlistsAreEqual(expected, current):
                break
            default:
                mismatches.append(entry.url.path)
            }
        }
        return mismatches.sorted()
    }
}

func resign(
    appURL: URL,
    nestedBinaries: [URL],
    preserveEntitlements: Bool = true
) throws {
    // Snapshot every signed code object and its optional entitlement profile before touching
    // any signature. In particular, patchedBinaries normally contains Contents/MacOS/WeChat.
    // Removing that signature first used to erase the app's microphone/camera/network/sandbox
    // profile before the final --deep signing pass had a chance to preserve it.
    let entitlementSnapshot = preserveEntitlements
        ? try CodeSigningEntitlementsSnapshot.capture(in: appURL)
        : .empty

    for binaryURL in uniqueURLs(nestedBinaries) {
        try signMachO(
            at: binaryURL,
            entitlements: entitlementSnapshot.plistData(for: binaryURL),
            preserveMetadata: preserveEntitlements
        )
    }

    try signAppBundle(
        at: appURL,
        // Supplying the root plist together with --deep also applies it to nested code
        // objects that originally had no entitlements. First create a clean ad-hoc signing
        // tree, then restore only the saved profiles below.
        entitlements: nil,
        preserveMetadata: preserveEntitlements
    )

    if preserveEntitlements {
        var mismatches = try entitlementSnapshot.mismatchingPaths()
        if !mismatches.isEmpty {
            // --preserve-metadata is the fast path. If a macOS/codesign version drops one of
            // the nested profiles, explicitly restore each saved plist from the deepest code
            // object outward and seal the root app last.
            try restoreCapturedEntitlements(entitlementSnapshot, appURL: appURL)
            mismatches = try entitlementSnapshot.mismatchingPaths()
            guard mismatches.isEmpty else {
                throw ToolError.signingEntitlementsMismatch(mismatches)
            }
        }
    }

    // Remove quarantine only: nested non-Mach-O code (e.g. vk_swiftshader_icd.json)
    // stores its signature in com.apple.cs.* xattrs. Clearing all attributes destroys
    // those signatures. Leave provenance and all other metadata intact; quarantine
    // removal remains best-effort when macOS does not permit changing an attribute.
    _ = runProcessStatus("/usr/bin/xattr", ["-dr", "com.apple.quarantine", appURL.path])

    // Verify the final state after all bundle mutations, including quarantine cleanup.
    try runProcess(
        "/usr/bin/codesign",
        ["--verify", "--deep", "--strict", "--verbose=2", appURL.path]
    )
}

private func signMachO(
    at url: URL,
    entitlements: Data?,
    preserveMetadata: Bool
) throws {
    if runCodesignStatus(
        url: url,
        deep: false,
        entitlements: entitlements,
        preserveMetadata: preserveMetadata
    ) == 0 {
        return
    }

    try signMachOUsingTemporaryCopy(
        at: url,
        entitlements: entitlements,
        preserveMetadata: preserveMetadata
    )
}

private func signMachOUsingTemporaryCopy(
    at url: URL,
    entitlements: Data?,
    preserveMetadata: Bool
) throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("wechat-antirecall-sign-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let temporaryURL = temporaryDirectory.appendingPathComponent(url.lastPathComponent)
    try FileManager.default.copyItem(at: url, to: temporaryURL)
    try runCodesign(
        url: temporaryURL,
        deep: false,
        entitlements: entitlements,
        preserveMetadata: preserveMetadata
    )
    try runProcess("/bin/cp", ["-p", temporaryURL.path, url.path])
}

private func signAppBundle(
    at appURL: URL,
    entitlements: Data?,
    preserveMetadata: Bool
) throws {
    try runCodesign(
        url: appURL,
        deep: true,
        entitlements: entitlements,
        preserveMetadata: preserveMetadata
    )
}

private func restoreCapturedEntitlements(
    _ snapshot: CodeSigningEntitlementsSnapshot,
    appURL: URL
) throws {
    let appPath = appURL.standardizedFileURL.path
    let entitlementPaths = snapshot.entries.compactMap { entry -> String? in
        guard entry.plistData != nil else {
            return nil
        }
        return entry.url.standardizedFileURL.path
    }
    let entriesToRestore = snapshot.entries.filter { entry in
        let path = entry.url.standardizedFileURL.path
        let prefix = path.hasSuffix("/") ? path : "\(path)/"
        return entry.plistData != nil || entitlementPaths.contains { $0.hasPrefix(prefix) }
    }
    let deepestFirst = entriesToRestore.sorted {
        let lhsDepth = $0.url.standardizedFileURL.pathComponents.count
        let rhsDepth = $1.url.standardizedFileURL.pathComponents.count
        if lhsDepth == rhsDepth {
            return $0.url.path > $1.url.path
        }
        return lhsDepth > rhsDepth
    }

    for entry in deepestFirst {
        guard entry.url.standardizedFileURL.path != appPath else {
            continue
        }
        try runCodesign(
            url: entry.url,
            deep: false,
            entitlements: entry.plistData,
            preserveMetadata: true
        )
    }

    // The initial recursive pass has already converted the Developer-ID nested requirements
    // to ad-hoc requirements. Seal the root without --deep so codesign cannot rewrite the
    // entitlement profiles that were just restored on the children.
    try runCodesign(
        url: appURL,
        deep: false,
        entitlements: snapshot.plistData(for: appURL),
        preserveMetadata: true
    )
}

private func runCodesign(
    url: URL,
    deep: Bool,
    entitlements: Data?,
    preserveMetadata: Bool
) throws {
    try withTemporaryEntitlementsFile(entitlements) { entitlementsURL in
        try runProcess(
            "/usr/bin/codesign",
            codesignArguments(
                url: url,
                deep: deep,
                entitlementsURL: entitlementsURL,
                preserveMetadata: preserveMetadata
            )
        )
    }
}

private func runCodesignStatus(
    url: URL,
    deep: Bool,
    entitlements: Data?,
    preserveMetadata: Bool
) -> Int32 {
    do {
        return try withTemporaryEntitlementsFile(entitlements) { entitlementsURL in
            runProcessStatus(
                "/usr/bin/codesign",
                codesignArguments(
                    url: url,
                    deep: deep,
                    entitlementsURL: entitlementsURL,
                    preserveMetadata: preserveMetadata
                )
            )
        }
    } catch {
        return 127
    }
}

private func codesignArguments(
    url: URL,
    deep: Bool,
    entitlementsURL: URL?,
    preserveMetadata: Bool
) -> [String] {
    var arguments = ["--force"]
    if deep {
        arguments.append("--deep")
    }
    if preserveMetadata {
        arguments.append(
            // Requirements bind the original Developer ID identity. Preserving them while
            // changing to an ad-hoc identity leaves nested code valid in isolation but
            // unacceptable to its parent resource envelope.
            "--preserve-metadata=identifier,flags,runtime"
        )
    }
    arguments.append(contentsOf: ["--sign", "-"])
    if let entitlementsURL {
        if ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        ) {
            // macOS 15+ no longer embeds supplied entitlements in libraries by default.
            arguments.append("--force-library-entitlements")
        }
        arguments.append(contentsOf: ["--entitlements", entitlementsURL.path])
    }
    arguments.append(url.path)
    return arguments
}

private func withTemporaryEntitlementsFile<T>(
    _ plistData: Data?,
    body: (URL?) throws -> T
) throws -> T {
    guard let plistData else {
        return try body(nil)
    }

    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("wechat-antirecall-entitlements-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    let plistURL = temporaryDirectory.appendingPathComponent("entitlements.plist")
    try plistData.write(to: plistURL, options: .atomic)
    return try body(plistURL)
}

private func codeSigningCandidates(in appURL: URL) -> [URL] {
    let codeBundleExtensions: Set<String> = [
        "app", "appex", "bundle", "framework", "plugin", "service", "xpc"
    ]
    let looseCodeExtensions: Set<String> = ["dylib", "so"]
    let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey
    ]

    var candidates = [appURL]
    if let enumerator = FileManager.default.enumerator(
        at: appURL,
        includingPropertiesForKeys: resourceKeys,
        options: [],
        errorHandler: { _, _ in true }
    ) {
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)),
                  values.isSymbolicLink != true else {
                continue
            }

            if values.isDirectory == true,
               codeBundleExtensions.contains(url.pathExtension.lowercased()) {
                candidates.append(url)
            } else if values.isRegularFile == true,
                      FileManager.default.isExecutableFile(atPath: url.path)
                        || looseCodeExtensions.contains(url.pathExtension.lowercased()) {
                candidates.append(url)
            }
        }
    }

    return uniqueURLs(candidates)
}

private struct InspectedSignedCode {
    let entitlements: Data?
}

private func inspectSignedCode(at url: URL) throws -> InspectedSignedCode? {
    let result = try runProcessCapture(
        "/usr/bin/codesign",
        ["-d", "--entitlements", "-", "--xml", url.path]
    )
    guard result.status == 0 else {
        return nil
    }
    guard !result.stdout.isEmpty else {
        return InspectedSignedCode(entitlements: nil)
    }

    var format = PropertyListSerialization.PropertyListFormat.xml
    guard let dictionary = try PropertyListSerialization.propertyList(
        from: result.stdout,
        options: [],
        format: &format
    ) as? [String: Any],
          !dictionary.isEmpty else {
        return InspectedSignedCode(entitlements: nil)
    }

    let plistData = try PropertyListSerialization.data(
        fromPropertyList: dictionary,
        format: .xml,
        options: 0
    )
    return InspectedSignedCode(entitlements: plistData)
}

private func entitlementPlistsAreEqual(_ lhs: Data, _ rhs: Data) -> Bool {
    guard let lhsDictionary = try? PropertyListSerialization.propertyList(
        from: lhs,
        options: [],
        format: nil
    ) as? [String: Any],
          let rhsDictionary = try? PropertyListSerialization.propertyList(
              from: rhs,
              options: [],
              format: nil
          ) as? [String: Any] else {
        return false
    }

    return NSDictionary(dictionary: lhsDictionary).isEqual(
        to: rhsDictionary
    )
}

private func uniqueURLs(_ urls: [URL]) -> [URL] {
    var seen = Set<String>()
    var result: [URL] = []

    for url in urls {
        let path = url.standardizedFileURL.path
        if seen.insert(path).inserted {
            result.append(url)
        }
    }

    return result
}

private func runProcess(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        throw ToolError.commandFailed(([executable] + arguments).joined(separator: " "), process.terminationStatus)
    }
}

private func runProcessCapture(
    _ executable: String,
    _ arguments: [String]
) throws -> (status: Int32, stdout: Data) {
    let process = Process()
    let outputPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = outputPipe
    process.standardError = FileHandle.nullDevice

    try process.run()
    let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, output)
}

private func captureProcessOutput(
    _ executable: String,
    _ arguments: [String]
) throws -> (stdout: Data, stderr: Data) {
    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    try process.run()
    let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (stdout, stderr)
}

private func runProcessStatus(_ executable: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        return 127
    }
}

extension FileHandle {
    func readData(at offset: UInt64, length: Int) throws -> Data {
        try seek(toOffset: offset)
        let data = readData(ofLength: length)
        guard data.count == length else {
            throw ToolError.unsupportedMachO("unexpected EOF")
        }
        return data
    }
}

extension Data {
    init(hexString: String) throws {
        let cleaned = hexString.filter { !$0.isWhitespace }
        guard cleaned.count.isMultiple(of: 2) else {
            throw ToolError.invalidHex(hexString)
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)

        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            let byteString = String(cleaned[index..<nextIndex])
            guard let byte = UInt8(byteString, radix: 16) else {
                throw ToolError.invalidHex(hexString)
            }
            bytes.append(byte)
            index = nextIndex
        }

        self = Data(bytes)
    }

    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }

    func leUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    func beUInt32(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }

    func leUInt64(at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for byteIndex in 0..<8 {
            value |= UInt64(self[offset + byteIndex]) << (byteIndex * 8)
        }
        return value
    }

    func beUInt64(at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for byteIndex in 0..<8 {
            value = (value << 8) | UInt64(self[offset + byteIndex])
        }
        return value
    }

    mutating func setLEUInt32(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(value & 0xff)
        self[offset + 1] = UInt8((value >> 8) & 0xff)
        self[offset + 2] = UInt8((value >> 16) & 0xff)
        self[offset + 3] = UInt8((value >> 24) & 0xff)
    }
}
