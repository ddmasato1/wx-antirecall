import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let defaultAppPath = "/Applications/WeChat.app"
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
                try? await Task.sleep(nanoseconds: 2_000_000_000)
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
                title: "不是官方微信",
                message: "本精简版只支持官方 macOS 微信（com.tencent.xinWeChat / com.tencent.xin）。")
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
            return
        }

        guard let info = WeChatStatusProbe.readInfo(appPath: targetPath) else {
            supportStatus = .failed
            banner = Banner(
                kind: .error,
                title: "无法读取所选 App",
                message: "所选路径存在，但不是完整、可读取的 macOS App。请在首页重新选择官方微信。")
            return
        }

        directInfo = info
        guard WeChatStatusProbe.officialBundleIDs.contains(info.bundleIdentifier) else {
            supportStatus = .failed
            banner = Banner(
                kind: .error,
                title: "所选 App 不是官方微信",
                message: "请在首页重新选择官方 macOS 微信。")
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
        let stale = builtDir.appendingPathComponent("wechat-antirecall")
        guard fm.isExecutableFile(atPath: stale.path) else { return false }
        let suffix = ".stale-schema\(reportedSchemaVersion)-\(Int(Date().timeIntervalSince1970))"
        do {
            try fm.moveItem(at: stale, to: builtDir.appendingPathComponent("wechat-antirecall\(suffix)"))
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
        let probe = resources.appendingPathComponent(".wechat-antirecall-access-probe-\(UUID().uuidString)")
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
        appendLog("——— 开始：静默防撤回 ———")
        guard silentAvailable else {
            banner = Banner(
                kind: .warning,
                title: "当前版本不可用",
                message: "补丁数据没有提供该构建号的静默防撤回补丁。")
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
            banner = Banner(kind: .info, title: "已经开启", message: "静默防撤回已经在生效中，无需重复安装。")
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
                            title: withTip ? "防撤回已开启（显示提示）" : "静默防撤回已开启",
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
        guard silentAvailable else {
            banner = Banner(kind: .warning, title: "当前版本不可用", message: "该构建号没有静默防撤回补丁。")
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
                banner = Banner(kind: .info, title: "已经安装", message: "静默防撤回补丁已经在生效中。")
            case .installable:
                banner = Banner(kind: .success, title: "检查通过", message: "补丁字节匹配，可以安全安装。")
            }
        } catch {
            banner = Banner(kind: .error, title: "检查结果不可用", message: error.localizedDescription)
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
