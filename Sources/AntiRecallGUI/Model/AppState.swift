import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let defaultAppPath = "/Applications/WeChat.app"
    static let applicationsDir = "/Applications"
    private static let selectedAppPathKey = "selectedWeChatAppPath"
    private static let withTipKey = "withTipEnabled"

    @Published private(set) var appPath: String
    /// false = silent recall; true = keep the message and show WeChat's native recall notice.
    @Published private(set) var withTip: Bool

    @Published var versions: VersionsReport?
    @Published var directInfo: DirectAppInfo?
    @Published var supportStatus: SupportStatus = .unknown
    @Published var installState: InstallState = .unknown
    @Published var wechatRunning: Bool = false
    @Published var clones: [CloneInstanceInfo] = []

    @Published var busy: Bool = false
    @Published var busyMessage: String = ""
    @Published var banner: Banner?
    @Published var logLines: [String] = []

    private var runningPoll: Task<Void, Never>?
    private let defaults: UserDefaults
    private var statusRevision: UInt64 = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.withTip = defaults.bool(forKey: Self.withTipKey)
        if let saved = defaults.string(forKey: Self.selectedAppPathKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !saved.isEmpty {
            appPath = saved
        } else {
            appPath = Self.defaultAppPath
        }
    }

    // MARK: - Lifecycle

    func onAppear() {
        BundledPaths.ensureWorkingDirectories()
        startRunningPoll()
        Task { await refresh() }
    }

    private func startRunningPoll() {
        runningPoll?.cancel()
        runningPoll = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                wechatRunning = WeChatStatusProbe.isRunning(appPath: appPath)
                updateCloneRunningStates()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func updateCloneRunningStates() {
        for idx in clones.indices {
            let running = WeChatStatusProbe.isRunning(appPath: clones[idx].path)
            if clones[idx].isRunning != running {
                clones[idx].isRunning = running
            }
        }
    }

    // MARK: - Derived

    var displayBuild: String {
        versions?.app.installedBuild ?? directInfo?.installedBuild ?? "—"
    }

    var displayVersion: String {
        versions?.app.marketingVersion ?? directInfo?.marketingVersion ?? "—"
    }

    /// Whether the selected mode has a patch target for this build.
    var silentAvailable: Bool {
        guard let versions, versions.supported else { return false }
        return versions.installedBuildTargets.contains(withTip ? "revoke-tip" : "revoke")
    }

    /// True when this build ships the revoke-tip (native recall notice) patch.
    var tipAvailable: Bool {
        versions?.installedBuildTargets.contains("revoke-tip") ?? false
    }

    /// Next free clone slot starting at 2, accounting for existing clones and bundle names on disk.
    var nextCloneIndex: Int {
        let used = Set(clones.map(\.index))
        var candidate = 2
        while used.contains(candidate)
            || FileManager.default.fileExists(atPath: "\(Self.applicationsDir)/WeChat \(candidate).app") {
            candidate += 1
        }
        return candidate
    }

    func setWithTip(_ enabled: Bool) async {
        guard enabled != withTip else { return }
        withTip = enabled
        defaults.set(enabled, forKey: Self.withTipKey)
        await refresh()
    }

    var isUsingDefaultAppPath: Bool {
        URL(fileURLWithPath: appPath).standardizedFileURL.path
            == URL(fileURLWithPath: Self.defaultAppPath).standardizedFileURL.path
    }

    private func beginStatusRequest() -> UInt64 {
        statusRevision &+= 1
        return statusRevision
    }

    private func statusRequestIsCurrent(_ revision: UInt64, appPath expectedPath: String) -> Bool {
        statusRevision == revision && appPath == expectedPath
    }

    // MARK: - Target selection

    func selectTargetApp(at url: URL) async {
        guard !busy else { return }
        busy = true
        busyMessage = "正在验证所选微信…"
        banner = nil
        defer {
            busy = false
            busyMessage = ""
        }

        let candidate = url.standardizedFileURL.path
        guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
              WeChatStatusProbe.appExists(at: candidate),
              let info = WeChatStatusProbe.readInfo(appPath: candidate) else {
            banner = Banner(
                kind: .error,
                title: "无法选择此 App",
                message: "请选择一个完整、可读取的 macOS 微信 App。")
            return
        }
        guard WeChatStatusProbe.officialBundleIDs.contains(info.bundleIdentifier) else {
            banner = Banner(
                kind: .error,
                title: "不是官方主微信",
                message: "首页用于管理官方主微信（com.tencent.xinWeChat / com.tencent.xin）；如需创建或管理多开分身，请前往「微信多开」页。")
            return
        }

        do {
            let report = try await versionsReport(appPath: candidate)
            let state = try await dryRunInstallState(appPath: candidate)
            _ = beginStatusRequest()
            appPath = candidate
            defaults.set(candidate, forKey: Self.selectedAppPathKey)
            versions = report
            directInfo = nil
            supportStatus = report.supported ? .supported : .unsupported(build: report.app.installedBuild)
            installState = state
            wechatRunning = WeChatStatusProbe.isRunning(appPath: candidate)
            await refreshClones()
        } catch {
            banner = Banner(kind: .error, title: "无法使用所选微信", message: error.localizedDescription)
        }
    }

    func resetTargetApp() async {
        guard !busy else { return }
        busy = true
        busyMessage = "正在恢复默认微信…"
        _ = beginStatusRequest()
        appPath = Self.defaultAppPath
        defaults.removeObject(forKey: Self.selectedAppPathKey)
        await refresh()
        busy = false
        busyMessage = ""
    }

    // MARK: - Refresh

    func refresh(preserveBanner: Bool = false) async {
        let targetPath = appPath
        let revision = beginStatusRequest()
        if !preserveBanner { banner = nil }
        supportStatus = .unknown
        versions = nil
        directInfo = nil
        installState = .unknown
        wechatRunning = WeChatStatusProbe.isRunning(appPath: targetPath)

        guard WeChatStatusProbe.appExists(at: targetPath) else {
            supportStatus = .noWeChat
            await refreshClones()
            return
        }

        guard let info = WeChatStatusProbe.readInfo(appPath: targetPath) else {
            supportStatus = .failed
            banner = Banner(
                kind: .error,
                title: "无法读取所选 App",
                message: "所选路径存在，但不是完整、可读取的 macOS App。请在首页重新选择官方微信。")
            await refreshClones()
            return
        }

        directInfo = info
        guard WeChatStatusProbe.officialBundleIDs.contains(info.bundleIdentifier) else {
            supportStatus = .failed
            banner = Banner(
                kind: .error,
                title: "所选 App 不是官方主微信",
                message: "首页用于管理官方主微信；如需管理多开分身，请前往「微信多开」页，或在首页重新选择官方微信。")
            await refreshClones()
            return
        }

        do {
            let report = try await versionsReport(appPath: targetPath)
            // A saved "show tip" preference is meaningless on a build without that patch
            // (e.g. 270416); fall back to silent so the user is never stuck.
            if withTip && !report.installedBuildTargets.contains("revoke-tip") {
                withTip = false
                defaults.set(false, forKey: Self.withTipKey)
            }
            let state = report.supported ? try await dryRunInstallState(appPath: targetPath) : .unknown
            guard statusRequestIsCurrent(revision, appPath: targetPath) else { return }
            versions = report
            directInfo = nil
            supportStatus = report.supported ? .supported : .unsupported(build: report.app.installedBuild)
            installState = state
            await refreshClones()
        } catch {
            guard statusRequestIsCurrent(revision, appPath: targetPath) else { return }
            versions = nil
            directInfo = info
            supportStatus = .failed
            installState = .unknown
            appendLog("检测失败：\(error.localizedDescription)")
            // A refresh triggered right after a successful install must not replace the
            // success banner with a transient detection error; the log still records it.
            if !(preserveBanner && banner?.kind == .success) {
                banner = Banner(
                    kind: .error,
                    title: "检测失败",
                    message: "\(error.localizedDescription) 请确认 App 文件完整；若问题持续，请查看下方日志。")
            }
            await refreshClones()
        }
    }

    // MARK: - CLI plumbing

    private func versionsReport(appPath: String) async throws -> VersionsReport {
        let cliURL = BundledPaths.cli
        guard FileManager.default.isExecutableFile(atPath: cliURL.path) else {
            throw GUIError("找不到可执行的内置命令行工具：\(cliURL.path)。")
        }
        let configURL = BundledPaths.effectivePatchesJSON
        guard BundledPaths.isValidCatalog(configURL) else {
            throw GUIError("补丁数据不可读取或格式无效：\(configURL.path)。")
        }

        let result = await CLIRunner.runUser(cliURL, [
            "versions", "--app", appPath, "--config", configURL.path, "--json"
        ])
        guard result.exitCode == 0 else {
            if let envelope = try? JSONDecoder().decode(CLIErrorEnvelope.self, from: Data(result.output.utf8)) {
                if quarantineStaleBuiltCLI(envelope.schemaVersion) {
                    return try await versionsReport(appPath: appPath)
                }
                try requireSupportedSchema(envelope.schemaVersion)
                throw GUIError(envelope.error.message)
            }
            throw GUIError(commandFailureMessage(result, operation: "读取微信版本"))
        }
        guard let report = try? JSONDecoder().decode(VersionsReport.self, from: Data(result.output.utf8)) else {
            throw GUIError("命令行工具返回了无法解析的版本信息。")
        }
        if quarantineStaleBuiltCLI(report.schemaVersion) {
            return try await versionsReport(appPath: appPath)
        }
        try requireSupportedSchema(report.schemaVersion)
        return report
    }

    private func dryRunInstallState(appPath: String) async throws -> InstallState {
        let args = InstallRequest(withTip: withTip).arguments(
            appPath: appPath,
            configURL: BundledPaths.effectivePatchesJSON,
            dryRun: true)
        let result = await CLIRunner.runUser(BundledPaths.cli, args)
        if result.exitCode != 0 {
            if let envelope = try? JSONDecoder().decode(CLIErrorEnvelope.self, from: Data(result.output.utf8)) {
                if quarantineStaleBuiltCLI(envelope.schemaVersion) {
                    return try await dryRunInstallState(appPath: appPath)
                }
                try requireSupportedSchema(envelope.schemaVersion)
                if envelope.error.kind == "bytesMismatch" { return .mismatch }
                throw GUIError(envelope.error.message)
            }
            throw GUIError(commandFailureMessage(result, operation: "检查补丁状态"))
        }
        if let raw = try? JSONDecoder().decode(InstallReport.self, from: Data(result.output.utf8)),
           raw.command == "install", quarantineStaleBuiltCLI(raw.schemaVersion) {
            return try await dryRunInstallState(appPath: appPath)
        }
        let report = try decodeInstallReport(result.output)
        return InstallState.classify(report)
    }

    private func decodeInstallReport(_ output: String) throws -> InstallReport {
        guard let report = try? JSONDecoder().decode(InstallReport.self, from: Data(output.utf8)),
              report.command == "install" else {
            throw GUIError("命令行工具返回了无法解析的安装检查结果。")
        }
        try requireSupportedSchema(report.schemaVersion)
        return report
    }

    private func requireSupportedSchema(_ schemaVersion: Int) throws {
        guard schemaVersion == GUICLIProtocol.schemaVersion else {
            throw GUIError(
                "命令行接口版本不兼容（GUI 支持 \(GUICLIProtocol.schemaVersion)，工具返回 \(schemaVersion)）。")
        }
    }

    @discardableResult
    private func quarantineStaleBuiltCLI(_ reportedSchemaVersion: Int) -> Bool {
        guard reportedSchemaVersion < GUICLIProtocol.schemaVersion else { return false }
        let fm = FileManager.default
        let builtDir = BundledPaths.appSupportDir.appendingPathComponent("build", isDirectory: true)
        let stale = builtDir.appendingPathComponent("wx-antirecall")
        guard fm.isExecutableFile(atPath: stale.path) else { return false }
        let suffix = ".stale-schema\(reportedSchemaVersion)-\(Int(Date().timeIntervalSince1970))"
        do {
            try fm.moveItem(at: stale, to: builtDir.appendingPathComponent("wx-antirecall\(suffix)"))
            return true
        } catch {
            return false
        }
    }

    private func commandFailureMessage(_ result: CLIResult, operation: String) -> String {
        let detail = (result.stderr + "\n" + result.output)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty
            ? "\(operation)失败（退出码 \(result.exitCode)）。"
            : "\(operation)失败：\(detail)"
    }

    // MARK: - Quit WeChat

    func quitWeChat() async {
        guard !busy else { return }
        busy = true
        busyMessage = "正在退出所选微信…"
        await WeChatStatusProbe.quit(appPath: appPath)
        wechatRunning = WeChatStatusProbe.isRunning(appPath: appPath)
        busy = false
        busyMessage = ""
    }

    // MARK: - Install

    enum InstallAccess: Equatable {
        case writableAsUser
        case needsElevation
        case blockedByTCC
    }

    private func fullDiskAccessBanner() -> Banner {
        Banner(
            kind: .warning,
            title: "需要「完全磁盘访问」",
            message: "macOS 的「App 管理」阻止本 App 修改微信。请在「系统设置 → 隐私与安全性 → 完全磁盘访问」里把本 App 加进去并打开，然后退出并重新打开本 App 再重试。",
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            settingsButtonTitle: "打开完全磁盘访问设置")
    }

    static func probeInstallAccess(appPath: String) -> InstallAccess {
        let fm = FileManager.default
        let resources = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Resources", isDirectory: true)
        let probe = resources.appendingPathComponent(".wx-antirecall-access-probe-\(UUID().uuidString)")
        if (try? Data().write(to: probe, options: .withoutOverwriting)) != nil {
            try? fm.removeItem(at: probe)
            return .writableAsUser
        }
        if let uid = (try? fm.attributesOfItem(atPath: appPath))?[.ownerAccountID] as? NSNumber,
           uid.uint32Value == getuid() {
            return .blockedByTCC
        }
        return .needsElevation
    }

    func install(_ request: InstallRequest) async {
        guard !busy else { return }
        banner = nil
        let modeTitle = request.withTip ? "防撤回（显示提示）" : "静默防撤回"
        appendLog("——— 开始：\(modeTitle) ———")
        guard silentAvailable else {
            banner = Banner(
                kind: .warning,
                title: "当前版本不可用",
                message: "补丁数据没有提供该构建号的\(modeTitle)补丁。")
            return
        }
        if WeChatStatusProbe.isRunning(appPath: appPath) {
            banner = Banner(kind: .warning, title: "请先退出微信", message: "安装前需要完全退出微信，避免签名失效导致崩溃。")
            return
        }

        busy = true
        defer { busy = false; busyMessage = "" }

        let configURL = BundledPaths.effectivePatchesJSON

        // 1) Dry-run: unprivileged and side-effect free.
        busyMessage = "正在检查补丁点…"
        let dryArgs = request.arguments(appPath: appPath, configURL: configURL, dryRun: true)
        let dry = await CLIRunner.runUser(BundledPaths.cli, dryArgs, onLine: { [weak self] line in
            Task { @MainActor in self?.appendLog(line) }
        })
        if dry.exitCode != 0 {
            let message = decodeErrorMessage(from: dry) ?? dry.stderr
            banner = Banner(kind: .error, title: "检查未通过", message: message.isEmpty ? "补丁点检查失败。" : message)
            appendLog("检查失败：\(message)")
            return
        }
        let report: InstallReport
        do {
            report = try decodeInstallReport(dry.output)
        } catch {
            banner = Banner(kind: .error, title: "检查结果不可用", message: error.localizedDescription)
            return
        }
        switch InstallPreflightDisposition.classify(report) {
        case .invalid:
            banner = Banner(kind: .error, title: "检查结果无效", message: "安装检查没有返回有效步骤，或包含无法安全继续的状态。请先查看日志并还原备份。")
            return
        case .alreadyInstalled:
            banner = Banner(kind: .info, title: "已经开启", message: "\(modeTitle)已经在生效中，无需重复安装。")
            installState = .installed
            return
        case .installable:
            break
        }

        // 2) Real install.
        var realArgs = request.arguments(appPath: appPath, configURL: configURL, dryRun: false)
        realArgs.removeAll { $0 == "--json" }

        let access = Self.probeInstallAccess(appPath: appPath)
        let real: CLIResult
        switch access {
        case .blockedByTCC:
            banner = fullDiskAccessBanner()
            appendLog("安装前检查失败：微信归当前用户但无写入权限（被 App 管理/TCC 拦截）。")
            return
        case .writableAsUser:
            busyMessage = "正在安装…"
            appendLog("安装前检查：可直接写入，无需管理员密码。")
            real = await CLIRunner.runUser(BundledPaths.cli, realArgs, onLine: { [weak self] line in
                Task { @MainActor in self?.appendLog(line) }
            })
        case .needsElevation:
            busyMessage = "正在安装（需要管理员密码）…"
            real = await CLIRunner.runAdmin(BundledPaths.cli, realArgs, operation: "install", onLine: { [weak self] line in
                Task { @MainActor in self?.appendLog(line) }
            })
        }

        if real.cancelled {
            banner = Banner(kind: .info, title: "已取消", message: "你取消了管理员授权，未做任何修改。")
        } else if real.succeeded {
            banner = Banner(kind: .success,
                            title: request.withTip ? "防撤回已开启（显示提示）" : "静默防撤回已开启",
                            message: "请完全退出并重新打开微信。首次使用建议用另一账号发消息再撤回，验证效果。")
            await refresh(preserveBanner: true)
        } else {
            banner = Banner(kind: .error, title: "安装失败", message: friendlyFailure(real))
            appendLog("安装失败（退出码 \(real.exitCode)）")
        }
    }

    // MARK: - Check only

    func checkOnly(_ request: InstallRequest) async {
        guard !busy else { return }
        banner = nil
        let modeTitle = request.withTip ? "防撤回（显示提示）" : "静默防撤回"
        guard silentAvailable else {
            banner = Banner(kind: .warning, title: "当前版本不可用", message: "该构建号没有\(modeTitle)补丁。")
            return
        }
        busy = true
        busyMessage = "正在检查补丁点…"
        defer { busy = false; busyMessage = "" }

        let args = request.arguments(
            appPath: appPath,
            configURL: BundledPaths.effectivePatchesJSON,
            dryRun: true)
        let result = await CLIRunner.runUser(BundledPaths.cli, args, onLine: { [weak self] line in
            Task { @MainActor in self?.appendLog(line) }
        })
        if result.exitCode != 0 {
            banner = Banner(kind: .error, title: "检查未通过", message: decodeErrorMessage(from: result) ?? "补丁点检查失败。")
            return
        }
        do {
            switch InstallPreflightDisposition.classify(try decodeInstallReport(result.output)) {
            case .invalid:
                banner = Banner(kind: .error, title: "检查结果无效", message: "安装检查返回了无法安全继续的状态。请查看日志并先还原备份。")
            case .alreadyInstalled:
                banner = Banner(kind: .info, title: "已经安装", message: "\(modeTitle)补丁已经在生效中。")
            case .installable:
                banner = Banner(kind: .success, title: "检查通过", message: "补丁字节匹配，可以安全安装。")
            }
        } catch {
            banner = Banner(kind: .error, title: "检查结果不可用", message: error.localizedDescription)
        }
    }

    // MARK: - Multi-instance Clones

    static func canWriteDirectory(_ path: String) -> Bool {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: path, isDirectory: true)
        let probeURL = dirURL.appendingPathComponent(".wx-antirecall-dir-probe-\(UUID().uuidString)")
        if (try? Data().write(to: probeURL, options: .withoutOverwriting)) != nil {
            try? fm.removeItem(at: probeURL)
            return true
        }
        return false
    }

    func refreshClones() async {
        let cliURL = BundledPaths.cli
        guard FileManager.default.isExecutableFile(atPath: cliURL.path) else { return }
        let configURL = BundledPaths.effectivePatchesJSON
        var args = ["clone", "list", "--output-dir", Self.applicationsDir, "--json"]
        if BundledPaths.isValidCatalog(configURL) {
            args += ["--config", configURL.path]
        }

        let result = await CLIRunner.runUser(cliURL, args)
        guard result.exitCode == 0 else {
            if let envelope = try? JSONDecoder().decode(CLIErrorEnvelope.self, from: Data(result.output.utf8)),
               quarantineStaleBuiltCLI(envelope.schemaVersion) {
                await refreshClones()
                return
            }
            appendLog("刷新分身列表失败：\(decodeErrorMessage(from: result) ?? result.stderr)")
            return
        }

        guard let report = try? JSONDecoder().decode(CloneListReport.self, from: Data(result.output.utf8)),
              report.command == "clone.list" else {
            appendLog("刷新分身列表失败：无法解析返回结果。")
            return
        }
        if quarantineStaleBuiltCLI(report.schemaVersion) {
            await refreshClones()
            return
        }
        guard report.schemaVersion == GUICLIProtocol.schemaVersion else {
            appendLog("刷新分身列表失败：命令行接口版本不兼容（\(report.schemaVersion)）。")
            return
        }

        clones = report.clones.map { item in
            CloneInstanceInfo(
                index: item.index,
                path: item.path,
                displayName: item.displayName,
                bundleIdentifier: item.bundleIdentifier,
                marketingVersion: item.marketingVersion,
                installedBuild: item.installedBuild,
                patchState: ClonePatchState(rawState: item.patchState),
                isRunning: WeChatStatusProbe.isRunning(appPath: item.path)
            )
        }
    }

    func createClone(patchMode: String) async {
        guard !busy else { return }
        banner = nil
        let slotIndex = nextCloneIndex
        appendLog("——— 开始：创建微信分身（微信 \(slotIndex)，补丁模式：\(patchMode)） ———")

        busy = true
        defer { busy = false; busyMessage = "" }

        let cliURL = BundledPaths.cli
        let configURL = BundledPaths.effectivePatchesJSON
        var baseArgs = [
            "clone", "create",
            "--app", appPath,
            "--output-dir", Self.applicationsDir,
            "--index", "\(slotIndex)",
            "--patch-mode", patchMode
        ]
        if BundledPaths.isValidCatalog(configURL) {
            baseArgs += ["--config", configURL.path]
        }

        busyMessage = "正在预检分身创建环境…"
        let dryArgs = baseArgs + ["--dry-run", "--json"]
        let dry = await CLIRunner.runUser(cliURL, dryArgs, onLine: { [weak self] line in
            Task { @MainActor in self?.appendLog(line) }
        })
        if dry.exitCode != 0 {
            let message = decodeErrorMessage(from: dry) ?? dry.stderr
            banner = Banner(kind: .error, title: "分身预检未通过", message: message.isEmpty ? "无法创建微信分身。" : message)
            appendLog("分身预检失败：\(message)")
            return
        }
        guard let dryReport = try? JSONDecoder().decode(CloneCreateReport.self, from: Data(dry.output.utf8)),
              dryReport.command == "clone.create",
              dryReport.schemaVersion == GUICLIProtocol.schemaVersion else {
            banner = Banner(kind: .error, title: "预检结果不可用", message: "命令行工具返回了无法识别的分身预检数据。")
            return
        }

        let real: CLIResult
        if Self.canWriteDirectory(Self.applicationsDir) {
            busyMessage = "正在生成微信 \(slotIndex) 并重签名…"
            appendLog("目录检查：\(Self.applicationsDir) 可直接写入，无需管理员密码。")
            real = await CLIRunner.runUser(cliURL, baseArgs, onLine: { [weak self] line in
                Task { @MainActor in self?.appendLog(line) }
            })
        } else {
            busyMessage = "正在生成微信 \(slotIndex)（需要管理员密码）…"
            real = await CLIRunner.runAdmin(cliURL, baseArgs, operation: "clone-create", onLine: { [weak self] line in
                Task { @MainActor in self?.appendLog(line) }
            })
        }

        if real.cancelled {
            banner = Banner(kind: .info, title: "已取消", message: "你取消了管理员授权，未创建微信分身。")
        } else if real.succeeded {
            await refreshClones()
            let modeSummary = Self.patchModeSummary(patchMode)
            banner = Banner(
                kind: .success,
                title: "已创建「微信 \(slotIndex)」",
                message: "分身已安装至 \(dryReport.clone.path)（\(modeSummary)）。点击下方「启动」即可登录其他微信号。"
            )
        } else {
            banner = Banner(kind: .error, title: "创建分身失败", message: friendlyFailure(real))
            appendLog("创建分身失败（退出码 \(real.exitCode)）")
        }
    }

    func rebuildClone(_ clone: CloneInstanceInfo, patchMode: String) async {
        guard !busy else { return }
        banner = nil
        if WeChatStatusProbe.isRunning(appPath: clone.path) {
            updateCloneRunningStates()
            banner = Banner(
                kind: .warning,
                title: "请先退出「\(clone.displayName)」",
                message: "同步重建会替换该分身应用包，请先退出正在运行的「\(clone.displayName)」（主微信无需退出）。"
            )
            return
        }

        appendLog("——— 开始：同步重建分身（\(clone.displayName)，补丁模式：\(patchMode)） ———")
        busy = true
        defer { busy = false; busyMessage = "" }

        let cliURL = BundledPaths.cli
        let configURL = BundledPaths.effectivePatchesJSON
        var baseArgs = [
            "clone", "create",
            "--app", appPath,
            "--output-dir", Self.applicationsDir,
            "--index", "\(clone.index)",
            "--patch-mode", patchMode,
            "--replace"
        ]
        if BundledPaths.isValidCatalog(configURL) {
            baseArgs += ["--config", configURL.path]
        }

        busyMessage = "正在检查同步条件…"
        let dry = await CLIRunner.runUser(cliURL, baseArgs + ["--dry-run", "--json"], onLine: { [weak self] line in
            Task { @MainActor in self?.appendLog(line) }
        })
        if dry.exitCode != 0 {
            let message = decodeErrorMessage(from: dry) ?? dry.stderr
            banner = Banner(kind: .error, title: "同步预检未通过", message: message.isEmpty ? "无法同步重建该分身。" : message)
            appendLog("同步预检失败：\(message)")
            return
        }

        let parentDir = URL(fileURLWithPath: clone.path).deletingLastPathComponent().path
        let real: CLIResult
        if Self.canWriteDirectory(parentDir) {
            busyMessage = "正在同步重建 \(clone.displayName)…"
            real = await CLIRunner.runUser(cliURL, baseArgs, onLine: { [weak self] line in
                Task { @MainActor in self?.appendLog(line) }
            })
        } else {
            busyMessage = "正在同步重建 \(clone.displayName)（需要管理员密码）…"
            real = await CLIRunner.runAdmin(cliURL, baseArgs, operation: "clone-rebuild", onLine: { [weak self] line in
                Task { @MainActor in self?.appendLog(line) }
            })
        }

        if real.cancelled {
            banner = Banner(kind: .info, title: "已取消", message: "你取消了管理员授权，未修改「\(clone.displayName)」。")
        } else if real.succeeded {
            await refreshClones()
            let modeSummary = Self.patchModeSummary(patchMode)
            banner = Banner(
                kind: .success,
                title: "已同步更新「\(clone.displayName)」",
                message: "分身已更新至当前主微信版本（\(modeSummary)），本地聊天记录完好保留。"
            )
        } else {
            banner = Banner(kind: .error, title: "同步重建失败", message: friendlyFailure(real))
            appendLog("同步重建失败（退出码 \(real.exitCode)）")
        }
    }

    func removeClone(_ clone: CloneInstanceInfo) async {
        guard !busy else { return }
        banner = nil
        if WeChatStatusProbe.isRunning(appPath: clone.path) {
            updateCloneRunningStates()
            banner = Banner(
                kind: .warning,
                title: "请先退出「\(clone.displayName)」",
                message: "删除前请先退出正在运行的「\(clone.displayName)」。"
            )
            return
        }

        appendLog("——— 开始：删除分身（\(clone.displayName)） ———")
        busy = true
        defer { busy = false; busyMessage = "" }

        let cliURL = BundledPaths.cli
        let baseArgs = ["clone", "remove", "--target", clone.path]

        busyMessage = "正在校验分身信息…"
        let dry = await CLIRunner.runUser(cliURL, baseArgs + ["--dry-run", "--json"], onLine: { [weak self] line in
            Task { @MainActor in self?.appendLog(line) }
        })
        if dry.exitCode != 0 {
            let message = decodeErrorMessage(from: dry) ?? dry.stderr
            banner = Banner(kind: .error, title: "无法删除该分身", message: message.isEmpty ? "分身校验未通过。" : message)
            return
        }

        let parentDir = URL(fileURLWithPath: clone.path).deletingLastPathComponent().path
        let real: CLIResult
        if Self.canWriteDirectory(parentDir) {
            busyMessage = "正在删除 \(clone.displayName)…"
            real = await CLIRunner.runUser(cliURL, baseArgs, onLine: { [weak self] line in
                Task { @MainActor in self?.appendLog(line) }
            })
        } else {
            busyMessage = "正在删除 \(clone.displayName)（需要管理员密码）…"
            real = await CLIRunner.runAdmin(cliURL, baseArgs, operation: "clone-remove", onLine: { [weak self] line in
                Task { @MainActor in self?.appendLog(line) }
            })
        }

        if real.cancelled {
            banner = Banner(kind: .info, title: "已取消", message: "你取消了管理员授权，未删除「\(clone.displayName)」。")
        } else if real.succeeded {
            await refreshClones()
            banner = Banner(
                kind: .success,
                title: "已删除「\(clone.displayName)」",
                message: "已移除 \(clone.path)，本地微信聊天数据未被删除。"
            )
        } else {
            banner = Banner(kind: .error, title: "删除分身失败", message: friendlyFailure(real))
            appendLog("删除分身失败（退出码 \(real.exitCode)）")
        }
    }

    func launchClone(_ clone: CloneInstanceInfo) async {
        let appURL = URL(fileURLWithPath: clone.path)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            try? await Task.sleep(nanoseconds: 450_000_000)
            updateCloneRunningStates()
        } catch {
            banner = Banner(
                kind: .error,
                title: "无法启动「\(clone.displayName)」",
                message: error.localizedDescription
            )
        }
    }

    func quitClone(_ clone: CloneInstanceInfo) async {
        guard !busy else { return }
        busy = true
        busyMessage = "正在退出 \(clone.displayName)…"
        await WeChatStatusProbe.quit(appPath: clone.path)
        updateCloneRunningStates()
        busy = false
        busyMessage = ""
    }

    private static func patchModeSummary(_ patchMode: String) -> String {
        switch patchMode {
        case "silent":
            return "已写入静默防撤回补丁"
        case "with-tip", "withTip":
            return "已写入撤回提示模式补丁"
        default:
            return "纯净未打补丁"
        }
    }

    // MARK: - Logging & helpers

    func appendLog(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logLines.append(trimmed)
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
    }

    func clearLog() { logLines.removeAll() }

    private func decodeErrorMessage(from result: CLIResult) -> String? {
        guard let envelope = try? JSONDecoder().decode(
            CLIErrorEnvelope.self,
            from: Data(result.output.utf8)
        ) else { return nil }
        guard envelope.schemaVersion == GUICLIProtocol.schemaVersion else {
            return "命令行接口版本不兼容（GUI 支持 \(GUICLIProtocol.schemaVersion)，工具返回 \(envelope.schemaVersion)）。"
        }
        return envelope.error.message
    }

    private func friendlyFailure(_ result: CLIResult) -> String {
        let log = result.output
        if log.contains("App Management") || log.contains("Operation not permitted") {
            return "写入被 macOS 拦截。请到「系统设置 → 隐私与安全性 → App 管理」给本 App 授权后重试（详见「权限」页）。"
        }
        if log.contains("仍在运行") || log.contains("appIsRunning") {
            return "微信仍在运行，请完全退出后重试。"
        }
        if let envelope = try? JSONDecoder().decode(CLIErrorEnvelope.self, from: Data(log.utf8)) {
            guard envelope.schemaVersion == GUICLIProtocol.schemaVersion else {
                return "命令行接口版本不兼容（GUI 支持 \(GUICLIProtocol.schemaVersion)，工具返回 \(envelope.schemaVersion)）。"
            }
            return envelope.error.message
        }
        let tail = log.split(separator: "\n").suffix(4).joined(separator: "\n")
        return tail.isEmpty ? "操作失败（退出码 \(result.exitCode)）。可在下方日志查看详情。" : tail
    }
}
