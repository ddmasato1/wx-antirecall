import Foundation

let defaultCloneOutputDir = "/Applications"

// MARK: - Clone Identity & Metadata

enum WeChatCloneMetadata {
    static let bundleIdentifierPrefix = "com.tencent.xinWeChat.antirecall.clone"
    static let markerKey = "WeChatAntiRecallClone"
    static let cloneIndexKey = "WeChatAntiRecallCloneIndex"
    static let sourceBundleIdentifierKey = "WeChatAntiRecallCloneSourceBundleIdentifier"

    static func bundleIdentifier(for index: Int) -> String {
        "\(bundleIdentifierPrefix)\(index)"
    }

    static func bundleAppName(for index: Int) -> String {
        "WeChat \(index)"
    }

    static func localizedDisplayName(for index: Int, localeFolder: String) -> String {
        if localeFolder.lowercased().hasPrefix("zh") {
            return "微信 \(index)"
        }
        return "WeChat \(index)"
    }

    static func isAcceptedClone(plist: [String: Any], bundleIdentifier: String) -> Bool {
        bundleIdentifier.hasPrefix(bundleIdentifierPrefix) && (plist[markerKey] as? Bool == true)
    }

    static func extractCloneIndex(plist: [String: Any], bundleIdentifier: String) -> Int? {
        if let index = plist[cloneIndexKey] as? Int, index >= 1 {
            return index
        }
        if let number = plist[cloneIndexKey] as? NSNumber, number.intValue >= 1 {
            return number.intValue
        }
        guard bundleIdentifier.hasPrefix(bundleIdentifierPrefix) else {
            return nil
        }
        let suffix = String(bundleIdentifier.dropFirst(bundleIdentifierPrefix.count))
        guard let parsed = Int(suffix), parsed >= 1, String(parsed) == suffix else {
            return nil
        }
        return parsed
    }
}

// MARK: - Patch Modes & States

enum ClonePatchMode: String, Equatable {
    case none = "none"
    case silent = "silent"
    case withTip = "withTip"

    var cliFlagValue: String {
        switch self {
        case .none: return "none"
        case .silent: return "silent"
        case .withTip: return "with-tip"
        }
    }

    static func parse(_ raw: String) throws -> ClonePatchMode {
        switch raw {
        case "none":
            return .none
        case "silent":
            return .silent
        case "with-tip", "withTip":
            return .withTip
        default:
            throw ToolError.usage("无效的 --patch-mode 值：\(raw)。可选值：none、silent、with-tip")
        }
    }
}

enum ClonePatchState: String, Equatable {
    case none = "none"
    case silent = "silent"
    case withTip = "withTip"
    case unsupported = "unsupported"
    case mismatch = "mismatch"
}

// MARK: - CLI Subcommand Routing & Options

extension CLI {
    func clone(_ arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw ToolError.usage("clone 需要指定子命令：list、create 或 remove。运行 `wechat-antirecall help` 查看用法。")
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "list":
            let options = try CloneListOptions(rest)
            let configs = try loadOptionalConfigs(explicitPath: options.configPath)
            let report = try WeChatCloneScanner.listReport(
                outputDir: options.outputDir,
                configs: configs
            )
            if options.json {
                JSONOutput.emit(report)
            } else {
                printCloneList(report)
            }
        case "create":
            let options = try CloneCreateOptions(rest)
            let configs: [VersionConfig]
            if options.patchMode == .none {
                configs = try loadOptionalConfigs(explicitPath: options.configPath)
            } else {
                configs = try loadConfigs(path: options.configPath)
            }
            let report = try WeChatCloneInstaller.create(options: options, configs: configs)
            if options.json {
                JSONOutput.emit(report)
            } else {
                printCloneCreate(report)
            }
        case "remove":
            let options = try CloneRemoveOptions(rest)
            let report = try WeChatCloneInstaller.remove(options: options)
            if options.json {
                JSONOutput.emit(report)
            } else {
                printCloneRemove(report)
            }
        default:
            throw ToolError.usage("未知的 clone 子命令：\(subcommand)。支持：list、create、remove。")
        }
    }

    private func loadOptionalConfigs(explicitPath: String?) throws -> [VersionConfig] {
        if let explicitPath {
            return try loadConfigs(path: explicitPath)
        }
        return (try? loadConfigs(path: nil)) ?? []
    }

    private func printCloneList(_ report: CloneListReport) {
        print("Output directory: \(report.outputDir)")
        print("Next available slot: \(report.nextAvailableIndex)")
        if report.clones.isEmpty {
            print("No WeChat clones found.")
            return
        }
        print("Clones (\(report.clones.count)):")
        for item in report.clones {
            print("  - [\(item.index)] \(item.displayName) | \(item.marketingVersion) (\(item.installedBuild)) | patch=\(item.patchState) | \(item.path)")
        }
    }

    private func printCloneCreate(_ report: CloneCreateReport) {
        let prefix = report.dryRun ? "[Dry-run] Would create" : (report.replaced ? "Updated" : "Created")
        print("\(prefix) clone: \(report.clone.displayName) -> \(report.clone.path)")
        print("  Bundle ID: \(report.clone.bundleIdentifier)")
        print("  Source build: \(report.sourceApp.marketingVersion) (\(report.sourceApp.installedBuild))")
        print("  Patch mode: \(report.patchMode) (state: \(report.clone.patchState))")
        if !report.dryRun {
            print("  Code signed: \(report.resigned ? "yes (ad-hoc, entitlements stripped)" : "skipped")")
        }
    }

    private func printCloneRemove(_ report: CloneRemoveReport) {
        if report.dryRun {
            print("[Dry-run] Would remove clone: \(report.removedPath) (\(report.bundleIdentifier))")
        } else {
            print("Removed clone: \(report.removedPath)")
        }
    }
}

struct CloneListOptions {
    var outputDir = defaultCloneOutputDir
    var configPath: String?
    var json = false

    init(_ arguments: [String]) throws {
        var parser = ArgumentCursor(arguments)
        while let argument = parser.next() {
            switch argument {
            case "--output-dir":
                outputDir = try parser.requiredValue(after: argument)
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

struct CloneCreateOptions {
    var appPath = defaultAppPath
    var outputDir = defaultCloneOutputDir
    var index: Int?
    var patchMode: ClonePatchMode = .none
    var configPath: String?
    var replace = false
    var keepURLSchemes = false
    var dryRun = false
    var skipResign = false
    var json = false

    init(_ arguments: [String]) throws {
        var parser = ArgumentCursor(arguments)
        while let argument = parser.next() {
            switch argument {
            case "--app":
                appPath = try parser.requiredValue(after: argument)
            case "--output-dir":
                outputDir = try parser.requiredValue(after: argument)
            case "--index":
                let raw = try parser.requiredValue(after: argument)
                guard let value = Int(raw), value >= 1 else {
                    throw ToolError.usage("--index 必须是大于等于 1 的正整数，收到：\(raw)")
                }
                index = value
            case "--patch-mode":
                let raw = try parser.requiredValue(after: argument)
                patchMode = try ClonePatchMode.parse(raw)
            case "--config":
                configPath = try parser.requiredValue(after: argument)
            case "--replace":
                replace = true
            case "--keep-url-schemes":
                keepURLSchemes = true
            case "--dry-run":
                dryRun = true
            case "--skip-resign":
                skipResign = true
            case "--json":
                json = true
            default:
                throw ToolError.usage("未知参数：\(argument)")
            }
        }
    }
}

struct CloneRemoveOptions {
    var targetPath = ""
    var dryRun = false
    var json = false

    init(_ arguments: [String]) throws {
        var parsedTarget: String?
        var parser = ArgumentCursor(arguments)
        while let argument = parser.next() {
            switch argument {
            case "--target":
                parsedTarget = try parser.requiredValue(after: argument)
            case "--dry-run":
                dryRun = true
            case "--json":
                json = true
            default:
                throw ToolError.usage("未知参数：\(argument)")
            }
        }
        guard let parsedTarget, !parsedTarget.isEmpty else {
            throw ToolError.usage("clone remove 需要 --target <path>")
        }
        targetPath = parsedTarget
    }
}

// MARK: - Scanner

enum WeChatCloneScanner {
    struct DiscoveredClone {
        let index: Int
        let appURL: URL
        let displayName: String
        let bundleIdentifier: String
        let sourceBundleIdentifier: String?
        let marketingVersion: String
        let installedBuild: String
        let patchState: ClonePatchState

        var dto: CloneItemDTO {
            CloneItemDTO(
                index: index,
                path: appURL.path,
                displayName: displayName,
                bundleIdentifier: bundleIdentifier,
                sourceBundleIdentifier: sourceBundleIdentifier,
                marketingVersion: marketingVersion,
                installedBuild: installedBuild,
                patchState: patchState.rawValue
            )
        }
    }

    static func listReport(outputDir: String, configs: [VersionConfig]) throws -> CloneListReport {
        let outputDirURL = URL(fileURLWithPath: outputDir, isDirectory: true).standardizedFileURL
        let clones = try scan(in: outputDirURL, configs: configs)
        let nextIndex = nextAvailableSlot(in: outputDirURL, existingClones: clones)
        return CloneListReport(
            schemaVersion: jsonSchemaVersion,
            outputDir: outputDirURL.path,
            nextAvailableIndex: nextIndex,
            clones: clones.map(\.dto)
        )
    }

    static func scan(in outputDirURL: URL, configs: [VersionConfig]) throws -> [DiscoveredClone] {
        let fm = FileManager.default
        var isDir = ObjCBool(false)
        guard fm.fileExists(atPath: outputDirURL.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        let children = try fm.contentsOfDirectory(
            at: outputDirURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var discovered: [DiscoveredClone] = []
        for childURL in children where childURL.pathExtension.lowercased() == "app" {
            guard let item = inspectClone(at: childURL, configs: configs) else {
                continue
            }
            discovered.append(item)
        }

        return discovered.sorted { lhs, rhs in
            if lhs.index != rhs.index {
                return lhs.index < rhs.index
            }
            return lhs.appURL.path < rhs.appURL.path
        }
    }

    static func inspectClone(at appURL: URL, configs: [VersionConfig]) -> DiscoveredClone? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String,
              WeChatCloneMetadata.isAcceptedClone(plist: plist, bundleIdentifier: bundleID),
              let index = WeChatCloneMetadata.extractCloneIndex(plist: plist, bundleIdentifier: bundleID) else {
            return nil
        }

        let shortVersion = (plist["CFBundleShortVersionString"] as? String) ?? "—"
        let buildVersion = (plist["CFBundleVersion"] as? String) ?? "—"
        let sourceBundleID = plist[WeChatCloneMetadata.sourceBundleIdentifierKey] as? String
        let displayName = resolveChinesePreferredDisplayName(appURL: appURL, plist: plist, index: index)
        let patchState = detectPatchState(appURL: appURL, buildVersion: buildVersion, configs: configs)

        return DiscoveredClone(
            index: index,
            appURL: appURL.standardizedFileURL,
            displayName: displayName,
            bundleIdentifier: bundleID,
            sourceBundleIdentifier: sourceBundleID,
            marketingVersion: shortVersion,
            installedBuild: buildVersion,
            patchState: patchState
        )
    }

    static func nextAvailableSlot(in outputDirURL: URL, existingClones: [DiscoveredClone]) -> Int {
        let fm = FileManager.default
        let usedIndices = Set(existingClones.map(\.index))
        var candidate = 2
        while true {
            let bundleURL = outputDirURL.appendingPathComponent(
                "\(WeChatCloneMetadata.bundleAppName(for: candidate)).app",
                isDirectory: true
            )
            let pathOccupied = (try? fm.attributesOfItem(atPath: bundleURL.path)) != nil
            if !usedIndices.contains(candidate) && !pathOccupied {
                return candidate
            }
            candidate += 1
        }
    }

    static func detectPatchState(
        appURL: URL,
        buildVersion: String,
        configs: [VersionConfig]
    ) -> ClonePatchState {
        guard !configs.isEmpty,
              let config = configs.first(where: { $0.version == buildVersion }) else {
            return .unsupported
        }

        var hasError = false
        var silentInstalled = false
        var tipInstalled = false

        if let revokeTarget = config.targets.first(where: { $0.identifier == "revoke" }) {
            switch evaluateTargetInstalled(revokeTarget, in: appURL) {
            case .installed:
                silentInstalled = true
            case .notInstalled:
                silentInstalled = false
            case .mismatch:
                hasError = true
            }
        }

        if let tipTarget = config.targets.first(where: { $0.identifier == "revoke-tip" }) {
            switch evaluateTargetInstalled(tipTarget, in: appURL) {
            case .installed:
                tipInstalled = true
            case .notInstalled:
                tipInstalled = false
            case .mismatch:
                hasError = true
            }
        }

        if hasError {
            return .mismatch
        }
        if silentInstalled && !tipInstalled {
            return .silent
        }
        if tipInstalled && !silentInstalled {
            return .withTip
        }
        if !silentInstalled && !tipInstalled {
            return .none
        }
        return .mismatch
    }

    private enum TargetEvaluation {
        case installed
        case notInstalled
        case mismatch
    }

    private static func evaluateTargetInstalled(_ target: PatchTarget, in appURL: URL) -> TargetEvaluation {
        let binaryURL = appURL.appendingPathComponent(target.binaryPath)
        guard FileManager.default.fileExists(atPath: binaryURL.path) else {
            return .mismatch
        }
        do {
            let reports = try MachOPatcher(fileURL: binaryURL).patch(entries: target.entries, dryRun: true)
            guard !reports.isEmpty else {
                return .mismatch
            }
            if reports.allSatisfy({ $0.status == .alreadyPatched }) {
                return .installed
            }
            return .notInstalled
        } catch {
            return .mismatch
        }
    }

    private static func resolveChinesePreferredDisplayName(
        appURL: URL,
        plist: [String: Any],
        index: Int
    ) -> String {
        let zhStringsURL = appURL.appendingPathComponent("Contents/Resources/zh-Hans.lproj/InfoPlist.strings")
        if let data = try? Data(contentsOf: zhStringsURL),
           let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] {
            if let name = dict["CFBundleDisplayName"] as? String, !name.isEmpty {
                return name
            }
            if let name = dict["CFBundleName"] as? String, !name.isEmpty {
                return name
            }
        }
        return WeChatCloneMetadata.localizedDisplayName(for: index, localeFolder: "zh-Hans")
    }
}

// MARK: - Installer (Create / Replace / Remove)

enum WeChatCloneInstaller {
    private struct BinaryEntryKey: Hashable {
        let binaryPath: String
        let arch: CPUArch
        let address: UInt64
    }

    private struct PlannedBinaryStep {
        let binaryPath: String
        let entries: [PatchEntry]
    }

    static func create(options: CloneCreateOptions, configs: [VersionConfig]) throws -> CloneCreateReport {
        let fm = FileManager.default
        let sourceAppInfo = try readAppInfo(appPath: options.appPath)
        try validateAppSignatureIsPatchable(appURL: sourceAppInfo.appURL)

        let outputDirURL = URL(fileURLWithPath: options.outputDir, isDirectory: true).standardizedFileURL
        var outputIsDir = ObjCBool(false)
        guard fm.fileExists(atPath: outputDirURL.path, isDirectory: &outputIsDir), outputIsDir.boolValue else {
            throw ToolError.usage("输出目录不存在或不是文件夹：\(outputDirURL.path)")
        }

        let existingClones = try WeChatCloneScanner.scan(in: outputDirURL, configs: configs)
        let targetIndex = options.index ?? WeChatCloneScanner.nextAvailableSlot(
            in: outputDirURL,
            existingClones: existingClones
        )
        let destinationURL = outputDirURL.appendingPathComponent(
            "\(WeChatCloneMetadata.bundleAppName(for: targetIndex)).app",
            isDirectory: true
        )

        try validateSafeClonePaths(
            sourceURL: sourceAppInfo.appURL,
            outputDirURL: outputDirURL,
            destinationURL: destinationURL
        )

        let targetExists = (try? fm.attributesOfItem(atPath: destinationURL.path)) != nil
        if targetExists {
            guard options.replace else {
                throw ToolError.usage("目标分身已存在：\(destinationURL.path)。如需覆盖更新请传入 --replace。")
            }
            try validateExistingTargetIsAcceptedClone(at: destinationURL, actionDescription: "覆盖")
            try ensureAppAtURLNotRunning(destinationURL, dryRun: options.dryRun)
        }

        let patchSteps = try buildPatchSteps(
            for: sourceAppInfo,
            patchMode: options.patchMode,
            configs: configs
        )

        // Preflight patch/revert steps on the source bundle before copying hundreds of MBs.
        for step in patchSteps {
            let sourceBinaryURL = sourceAppInfo.appURL.appendingPathComponent(step.binaryPath)
            guard fm.fileExists(atPath: sourceBinaryURL.path) else {
                if options.patchMode == .none {
                    continue
                }
                throw ToolError.invalidConfig("找不到目标二进制：\(step.binaryPath)")
            }
            if options.patchMode == .none {
                _ = try? MachOPatcher(fileURL: sourceBinaryURL).patch(entries: step.entries, dryRun: true)
            } else {
                _ = try MachOPatcher(fileURL: sourceBinaryURL).patch(entries: step.entries, dryRun: true)
            }
        }

        let resultingPatchState = predictedPatchState(
            for: sourceAppInfo,
            patchMode: options.patchMode,
            configs: configs
        )

        if options.dryRun {
            let dryCloneDTO = CloneItemDTO(
                index: targetIndex,
                path: destinationURL.path,
                displayName: WeChatCloneMetadata.localizedDisplayName(for: targetIndex, localeFolder: "zh-Hans"),
                bundleIdentifier: WeChatCloneMetadata.bundleIdentifier(for: targetIndex),
                sourceBundleIdentifier: sourceAppInfo.bundleIdentifier,
                marketingVersion: sourceAppInfo.shortVersion,
                installedBuild: sourceAppInfo.buildVersion,
                patchState: resultingPatchState.rawValue
            )
            return CloneCreateReport(
                schemaVersion: jsonSchemaVersion,
                dryRun: true,
                replaced: targetExists,
                resigned: false,
                patchMode: options.patchMode.rawValue,
                sourceApp: AppInfoDTO(sourceAppInfo),
                clone: dryCloneDTO
            )
        }

        try requireDirectoryWritable(outputDirURL, operation: "在目标目录创建微信分身")

        let temporaryURL = outputDirURL.appendingPathComponent(
            ".WeChat \(targetIndex).wechat-antirecall-\(UUID().uuidString).app",
            isDirectory: true
        )
        defer {
            try? fm.removeItem(at: temporaryURL)
        }

        do {
            try fm.copyItem(at: sourceAppInfo.appURL, to: temporaryURL)
        } catch {
            throw ToolError.fileOperationFailed(
                operation: "复制微信应用包",
                path: temporaryURL.path,
                underlying: error.localizedDescription
            )
        }

        removeInheritedBackupFiles(in: temporaryURL)

        var modifiedBinaries: [URL] = []
        for step in patchSteps {
            let tempBinaryURL = temporaryURL.appendingPathComponent(step.binaryPath)
            guard fm.fileExists(atPath: tempBinaryURL.path) else {
                if options.patchMode == .none {
                    continue
                }
                throw ToolError.invalidConfig("找不到目标二进制：\(step.binaryPath)")
            }
            if options.patchMode == .none {
                if let reports = try? MachOPatcher(fileURL: tempBinaryURL).patch(entries: step.entries, dryRun: false),
                   reports.contains(where: { $0.status == .patched }) {
                    modifiedBinaries.append(tempBinaryURL)
                }
            } else {
                let reports = try MachOPatcher(fileURL: tempBinaryURL).patch(entries: step.entries, dryRun: false)
                if reports.contains(where: { $0.status == .patched }) {
                    modifiedBinaries.append(tempBinaryURL)
                }
            }
        }

        try rewriteCloneInfoPlist(
            in: temporaryURL,
            index: targetIndex,
            sourceAppInfo: sourceAppInfo,
            keepURLSchemes: options.keepURLSchemes
        )
        try rewriteLocalizedInfoPlistStrings(in: temporaryURL, index: targetIndex)

        var resigned = false
        if !options.skipResign {
            try resign(
                appURL: temporaryURL,
                nestedBinaries: modifiedBinaries,
                preserveEntitlements: false
            )
            resigned = true
        }

        try commitCloneBundle(
            from: temporaryURL,
            to: destinationURL,
            in: outputDirURL,
            index: targetIndex,
            replacingExisting: targetExists
        )

        let finalClone = WeChatCloneScanner.inspectClone(at: destinationURL, configs: configs)?.dto
            ?? CloneItemDTO(
                index: targetIndex,
                path: destinationURL.path,
                displayName: WeChatCloneMetadata.localizedDisplayName(for: targetIndex, localeFolder: "zh-Hans"),
                bundleIdentifier: WeChatCloneMetadata.bundleIdentifier(for: targetIndex),
                sourceBundleIdentifier: sourceAppInfo.bundleIdentifier,
                marketingVersion: sourceAppInfo.shortVersion,
                installedBuild: sourceAppInfo.buildVersion,
                patchState: resultingPatchState.rawValue
            )

        return CloneCreateReport(
            schemaVersion: jsonSchemaVersion,
            dryRun: false,
            replaced: targetExists,
            resigned: resigned,
            patchMode: options.patchMode.rawValue,
            sourceApp: AppInfoDTO(sourceAppInfo),
            clone: finalClone
        )
    }

    static func remove(options: CloneRemoveOptions) throws -> CloneRemoveReport {
        let fm = FileManager.default
        let targetURL = URL(fileURLWithPath: options.targetPath, isDirectory: true).standardizedFileURL
        var isDir = ObjCBool(false)
        guard fm.fileExists(atPath: targetURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw ToolError.usage("目标分身不存在：\(targetURL.path)")
        }

        let metadata = try validateExistingTargetIsAcceptedClone(at: targetURL, actionDescription: "删除")
        try ensureAppAtURLNotRunning(targetURL, dryRun: options.dryRun)

        if !options.dryRun {
            let parentDirURL = targetURL.deletingLastPathComponent()
            try requireDirectoryWritable(parentDirURL, operation: "删除微信分身")
            do {
                try fm.removeItem(at: targetURL)
            } catch {
                throw ToolError.fileOperationFailed(
                    operation: "删除微信分身",
                    path: targetURL.path,
                    underlying: error.localizedDescription
                )
            }
        }

        return CloneRemoveReport(
            schemaVersion: jsonSchemaVersion,
            dryRun: options.dryRun,
            removedPath: targetURL.path,
            index: metadata.index,
            bundleIdentifier: metadata.bundleIdentifier
        )
    }

    // MARK: - Internal Helpers

    private static func validateSafeClonePaths(
        sourceURL: URL,
        outputDirURL: URL,
        destinationURL: URL
    ) throws {
        let sourceResolved = sourceURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let outputResolved = outputDirURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let destinationViaParentResolved = outputDirURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .appendingPathComponent(destinationURL.lastPathComponent, isDirectory: true)
            .standardizedFileURL
            .path
        let destinationDirectResolved = destinationURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path

        let sourcePrefix = sourceResolved.hasSuffix("/") ? sourceResolved : "\(sourceResolved)/"
        if outputResolved == sourceResolved || outputResolved.hasPrefix(sourcePrefix) {
            throw ToolError.usage("输出目录不能是源微信本身或位于源微信包内部：\(outputDirURL.path)")
        }

        for candidate in [destinationViaParentResolved, destinationDirectResolved] {
            if candidate == sourceResolved || candidate.hasPrefix(sourcePrefix) {
                throw ToolError.usage("目标分身路径不能覆盖源微信或位于源微信包内部：\(destinationURL.path)")
            }
            let candidatePrefix = candidate.hasSuffix("/") ? candidate : "\(candidate)/"
            if sourceResolved.hasPrefix(candidatePrefix) {
                throw ToolError.usage("源微信位于目标分身路径内部，拒绝操作：\(destinationURL.path)")
            }
        }
    }

    @discardableResult
    private static func validateExistingTargetIsAcceptedClone(
        at appURL: URL,
        actionDescription: String
    ) throws -> (bundleIdentifier: String, index: Int?) {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String else {
            throw ToolError.usage("拒绝\(actionDescription) \(appURL.path)：无法读取有效的 Info.plist。")
        }

        guard WeChatCloneMetadata.isAcceptedClone(plist: plist, bundleIdentifier: bundleID) else {
            throw ToolError.usage("拒绝\(actionDescription) \(appURL.path)：该应用不是由本工具创建的微信多开分身。")
        }

        let index = WeChatCloneMetadata.extractCloneIndex(plist: plist, bundleIdentifier: bundleID)
        return (bundleID, index)
    }

    /// Builds ordered patch/revert steps so that regardless of whether the source WeChat is
    /// pristine, silent-patched, or tip-patched, the clone lands cleanly in `patchMode`.
    private static func buildPatchSteps(
        for appInfo: AppInfo,
        patchMode: ClonePatchMode,
        configs: [VersionConfig]
    ) throws -> [PlannedBinaryStep] {
        let selectedTarget: PatchTarget?
        let matchingConfig: VersionConfig?

        switch patchMode {
        case .none:
            matchingConfig = configs.first(where: { $0.version == appInfo.buildVersion })
            selectedTarget = nil
        case .silent:
            let config = try configForInstalledApp(appInfo, configs: configs)
            guard let target = config.targets.first(where: { $0.identifier == "revoke" }) else {
                throw ToolError.invalidConfig("构建号 \(config.version) 没有 revoke 目标。")
            }
            matchingConfig = config
            selectedTarget = target
        case .withTip:
            let config = try configForInstalledApp(appInfo, configs: configs)
            guard let target = config.targets.first(where: { $0.identifier == "revoke-tip" }) else {
                throw ToolError.invalidConfig("构建号 \(config.version) 没有 revoke-tip 目标；该构建号仅支持静默防撤回。")
            }
            matchingConfig = config
            selectedTarget = target
        }

        guard let config = matchingConfig else {
            return []
        }

        var selectedKeys = Set<BinaryEntryKey>()
        if let selectedTarget {
            for entry in selectedTarget.entries {
                selectedKeys.insert(BinaryEntryKey(
                    binaryPath: selectedTarget.binaryPath,
                    arch: entry.arch,
                    address: entry.address
                ))
            }
        }

        // Revert entries from unselected targets whose addresses are independent of `selectedTarget`
        // (e.g. build 270601 where `revoke` and `revoke-tip` patch distinct addresses, or `none` mode).
        var revertKeys = Set<BinaryEntryKey>()
        var steps: [PlannedBinaryStep] = []

        for target in config.targets {
            if let selectedTarget, target.identifier == selectedTarget.identifier {
                continue
            }
            var revertEntries: [PatchEntry] = []
            for entry in target.entries {
                let key = BinaryEntryKey(
                    binaryPath: target.binaryPath,
                    arch: entry.arch,
                    address: entry.address
                )
                guard !selectedKeys.contains(key),
                      !entry.expectedBytes.isEmpty,
                      entry.expectedBytes[0] != entry.patchBytes,
                      revertKeys.insert(key).inserted else {
                    continue
                }
                var allowed = entry.expectedBytes
                if !allowed.contains(entry.patchBytes) {
                    allowed.append(entry.patchBytes)
                }
                revertEntries.append(PatchEntry(
                    arch: entry.arch,
                    address: entry.address,
                    patchBytes: entry.expectedBytes[0],
                    expectedBytes: allowed
                ))
            }
            if !revertEntries.isEmpty {
                steps.append(PlannedBinaryStep(binaryPath: target.binaryPath, entries: revertEntries))
            }
        }

        if let selectedTarget {
            steps.append(PlannedBinaryStep(binaryPath: selectedTarget.binaryPath, entries: selectedTarget.entries))
        }

        return steps
    }

    private static func predictedPatchState(
        for appInfo: AppInfo,
        patchMode: ClonePatchMode,
        configs: [VersionConfig]
    ) -> ClonePatchState {
        switch patchMode {
        case .silent:
            return .silent
        case .withTip:
            return .withTip
        case .none:
            if configs.contains(where: { $0.version == appInfo.buildVersion }) {
                return .none
            }
            return .unsupported
        }
    }

    private static func removeInheritedBackupFiles(in appURL: URL) {
        let fm = FileManager.default
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        guard let enumerator = fm.enumerator(
            at: contentsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return
        }

        var toDelete: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent.contains(".wechat-antirecall-backup-") {
                toDelete.append(fileURL)
            }
        }
        for fileURL in toDelete {
            try? fm.removeItem(at: fileURL)
        }
    }

    private static func rewriteCloneInfoPlist(
        in appURL: URL,
        index: Int,
        sourceAppInfo: AppInfo,
        keepURLSchemes: Bool
    ) throws {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let plistData = try Data(contentsOf: plistURL)
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard var plist = try PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: &format
        ) as? [String: Any] else {
            throw ToolError.notAWechatApp(appURL.path)
        }

        let appName = WeChatCloneMetadata.bundleAppName(for: index)
        plist["CFBundleIdentifier"] = WeChatCloneMetadata.bundleIdentifier(for: index)
        plist["CFBundleName"] = appName
        plist["CFBundleDisplayName"] = appName
        plist["CFBundleGetInfoString"] = "\(appName) (\(sourceAppInfo.shortVersion))"
        plist[WeChatCloneMetadata.markerKey] = true
        plist[WeChatCloneMetadata.cloneIndexKey] = index
        plist[WeChatCloneMetadata.sourceBundleIdentifierKey] = sourceAppInfo.bundleIdentifier

        if !keepURLSchemes {
            plist.removeValue(forKey: "CFBundleURLTypes")
        }

        // Disable Sparkle background auto-update and XPC launcher lookups on clones so a
        // clone never fails XPC lookup (`<bundleID>-spks`) or overwrites its own identity/patch.
        plist["SUEnableAutomaticChecks"] = false
        plist["SUAutomaticallyUpdate"] = false
        plist["SUAllowsAutomaticUpdates"] = false
        plist.removeValue(forKey: "SUEnableInstallerLauncherService")
        plist.removeValue(forKey: "SUEnableDownloaderService")
        plist.removeValue(forKey: "SUEnableInstallerConnectionService")
        plist.removeValue(forKey: "SUEnableInstallerStatusService")
        plist.removeValue(forKey: "SUFeedURL")

        let outputFormat: PropertyListSerialization.PropertyListFormat =
            (format == .binary) ? .binary : .xml
        let updatedData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: outputFormat,
            options: 0
        )
        try updatedData.write(to: plistURL, options: .atomic)
    }

    static func rewriteLocalizedInfoPlistStrings(in appURL: URL, index: Int) throws {
        let fm = FileManager.default
        let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        guard let children = try? fm.contentsOfDirectory(
            at: resourcesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for lprojURL in children where lprojURL.pathExtension.lowercased() == "lproj" {
            let stringsURL = lprojURL.appendingPathComponent("InfoPlist.strings")
            guard fm.fileExists(atPath: stringsURL.path) else {
                continue
            }

            let rawData = try Data(contentsOf: stringsURL)
            var format = PropertyListSerialization.PropertyListFormat.openStep
            guard var dictionary = try PropertyListSerialization.propertyList(
                from: rawData,
                options: [],
                format: &format
            ) as? [String: Any] else {
                continue
            }

            let localeName = lprojURL.deletingPathExtension().lastPathComponent
            let localizedName = WeChatCloneMetadata.localizedDisplayName(for: index, localeFolder: localeName)
            dictionary["CFBundleDisplayName"] = localizedName
            dictionary["CFBundleName"] = localizedName

            let serialized: Data
            switch format {
            case .binary:
                serialized = try PropertyListSerialization.data(
                    fromPropertyList: dictionary,
                    format: .binary,
                    options: 0
                )
            case .xml:
                serialized = try PropertyListSerialization.data(
                    fromPropertyList: dictionary,
                    format: .xml,
                    options: 0
                )
            case .openStep:
                serialized = serializeStringsDictionary(dictionary)
            @unknown default:
                serialized = try PropertyListSerialization.data(
                    fromPropertyList: dictionary,
                    format: .xml,
                    options: 0
                )
            }
            try serialized.write(to: stringsURL, options: .atomic)
        }
    }

    private static func serializeStringsDictionary(_ dictionary: [String: Any]) -> Data {
        let lines = dictionary.keys.sorted().map { key -> String in
            let value = String(describing: dictionary[key] ?? "")
            return "\"\(escapeStringsValue(key))\" = \"\(escapeStringsValue(value))\";"
        }
        let content = lines.isEmpty ? "" : (lines.joined(separator: "\n") + "\n")
        return Data(content.utf8)
    }

    private static func escapeStringsValue(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private static func commitCloneBundle(
        from temporaryURL: URL,
        to destinationURL: URL,
        in outputDirURL: URL,
        index: Int,
        replacingExisting: Bool
    ) throws {
        let fm = FileManager.default
        if !replacingExisting {
            do {
                try fm.moveItem(at: temporaryURL, to: destinationURL)
            } catch {
                throw ToolError.fileOperationFailed(
                    operation: "移入新微信分身",
                    path: destinationURL.path,
                    underlying: error.localizedDescription
                )
            }
            return
        }

        let stagingOldURL = outputDirURL.appendingPathComponent(
            ".WeChat \(index).replacing-\(UUID().uuidString).app",
            isDirectory: true
        )
        do {
            try fm.moveItem(at: destinationURL, to: stagingOldURL)
        } catch {
            throw ToolError.fileOperationFailed(
                operation: "暂存旧微信分身",
                path: destinationURL.path,
                underlying: error.localizedDescription
            )
        }

        do {
            try fm.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            try? fm.moveItem(at: stagingOldURL, to: destinationURL)
            throw ToolError.fileOperationFailed(
                operation: "替换微信分身",
                path: destinationURL.path,
                underlying: error.localizedDescription
            )
        }

        try? fm.removeItem(at: stagingOldURL)
    }
}
