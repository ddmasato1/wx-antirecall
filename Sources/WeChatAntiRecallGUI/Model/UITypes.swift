import Foundation

struct GUIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

enum GUICLIProtocol {
    // Keep in lockstep with the CLI's jsonSchemaVersion (both ship from the same tree).
    static let schemaVersion = 2
}

/// Builds the CLI argument list for the only supported operation: anti-recall.
/// The GUI always passes an absolute `--config` because a launched .app's working directory is `/`.
struct InstallRequest {
    /// false = silent (skip the whole recall parser); true = keep WeChat's native recall notice.
    var withTip = false

    func arguments(appPath: String, configURL: URL, dryRun: Bool) -> [String] {
        var args = ["install", "--app", appPath, "--config", configURL.path, "--json"]
        if withTip { args += ["--with-tip"] }
        if dryRun { args += ["--dry-run"] }
        return args
    }
}

enum SupportStatus: Equatable {
    case supported
    case unsupported(build: String)
    case noWeChat
    case failed
    case unknown
}

/// Whether the silent recall patch is currently applied to the selected WeChat target.
enum InstallState: Equatable {
    case notInstalled
    case installed
    case mismatch
    case unknown

    static func classify(_ report: InstallReport) -> InstallState {
        let states = report.targets.flatMap { $0.entries.map(\.state) }
        guard !states.isEmpty else { return .mismatch }
        if states.allSatisfy({ $0 == "alreadyPatched" }) { return .installed }
        // Switching modes can legitimately produce a mix: one entry already matches the
        // target bytes (e.g. the restored cbz) while the other still needs patching.
        if states.allSatisfy({ $0 == "alreadyPatched" || $0 == "wouldPatch" || $0 == "patched" }) {
            return .notInstalled
        }
        return .mismatch
    }
}

enum InstallPreflightDisposition: Equatable {
    case invalid
    case alreadyInstalled
    case installable

    static func classify(_ report: InstallReport) -> InstallPreflightDisposition {
        let states = report.targets.flatMap { $0.entries.map(\.state) }
        guard !states.isEmpty else { return .invalid }
        guard states.allSatisfy({
            $0 == "alreadyPatched" || $0 == "wouldPatch" || $0 == "patched"
        }) else { return .invalid }
        return states.allSatisfy { $0 == "alreadyPatched" } ? .alreadyInstalled : .installable
    }
}

enum BannerKind {
    case success
    case error
    case info
    case warning
}

struct Banner: Identifiable, Equatable {
    let id = UUID()
    let kind: BannerKind
    let title: String
    let message: String
    /// Optional System Settings deep link; when set, the banner shows a one-click button.
    var settingsURL: String? = nil
    var settingsButtonTitle: String = "打开系统设置"

    static func == (lhs: Banner, rhs: Banner) -> Bool { lhs.id == rhs.id }
}
