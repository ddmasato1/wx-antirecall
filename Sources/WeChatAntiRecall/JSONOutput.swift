import Foundation

// Machine-readable output for the GUI. Only the silent recall patch remains in this
// small-build-matrix (270390 / 270416 / 270601) fork, so the DTO surface is intentionally small.
//
// Every top-level report carries `schemaVersion` so a mismatched CLI/GUI pair is detectable.

let jsonSchemaVersion = 3

enum JSONOutput {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    /// Serialize `value` and print it to stdout. Falls back to a minimal error envelope
    /// if encoding somehow fails (should not happen for these fixed DTOs).
    static func emit<T: Encodable>(_ value: T) {
        do {
            let data = try encoder.encode(value)
            if let text = String(data: data, encoding: .utf8) {
                print(text)
            }
        } catch {
            print(#"{"schemaVersion":\#(jsonSchemaVersion),"error":{"kind":"encoding","message":"failed to encode JSON output"}}"#)
        }
    }
}

// MARK: - Shared DTOs

struct AppInfoDTO: Encodable {
    let path: String
    let bundleIdentifier: String
    let marketingVersion: String
    let installedBuild: String
    let executable: String

    init(_ info: AppInfo) {
        path = info.appURL.path
        bundleIdentifier = info.bundleIdentifier
        marketingVersion = info.shortVersion
        installedBuild = info.buildVersion
        executable = info.executableURL.path
    }
}

// MARK: - versions --json

struct VersionsReport: Encodable {
    let schemaVersion: Int
    let app: AppInfoDTO
    let supported: Bool
    let installedBuildTargets: [String]
    let catalog: [CatalogEntryDTO]

    struct CatalogEntryDTO: Encodable {
        let build: String
        let targets: [String]
    }

    init(appInfo: AppInfo, configs: [VersionConfig]) {
        schemaVersion = jsonSchemaVersion
        app = AppInfoDTO(appInfo)

        let installedConfig = configs.first { $0.version == appInfo.buildVersion }
        supported = installedConfig != nil
        installedBuildTargets = installedConfig?.targets.map(\.identifier) ?? []
        catalog = configs.map { CatalogEntryDTO(build: $0.version, targets: $0.targets.map(\.identifier)) }
    }
}

// MARK: - install --json

struct InstallReport: Encodable {
    let schemaVersion: Int
    let command = "install"
    let dryRun: Bool
    let resigned: Bool
    let app: AppInfoDTO
    let mode: [String]
    let targets: [TargetReportDTO]

    struct TargetReportDTO: Encodable {
        let identifier: String
        let binary: String
        let entries: [EntryReportDTO]
    }

    struct EntryReportDTO: Encodable {
        let arch: String
        let address: String
        let fileOffset: String
        let state: String

        init(_ report: PatchReport) {
            arch = report.arch.rawValue
            address = "0x" + String(report.address, radix: 16)
            fileOffset = "0x" + String(report.fileOffset, radix: 16)
            switch report.status {
            case .patched: state = "patched"
            case .wouldPatch: state = "wouldPatch"
            case .alreadyPatched: state = "alreadyPatched"
            }
        }
    }
}

// MARK: - clone --json

struct CloneItemDTO: Encodable {
    let index: Int
    let path: String
    let displayName: String
    let bundleIdentifier: String
    let sourceBundleIdentifier: String?
    let marketingVersion: String
    let installedBuild: String
    let patchState: String
}

struct CloneListReport: Encodable {
    let schemaVersion: Int
    let command = "clone.list"
    let outputDir: String
    let nextAvailableIndex: Int
    let clones: [CloneItemDTO]
}

struct CloneCreateReport: Encodable {
    let schemaVersion: Int
    let command = "clone.create"
    let dryRun: Bool
    let replaced: Bool
    let resigned: Bool
    let patchMode: String
    let sourceApp: AppInfoDTO
    let clone: CloneItemDTO
}

struct CloneRemoveReport: Encodable {
    let schemaVersion: Int
    let command = "clone.remove"
    let dryRun: Bool
    let removedPath: String
    let index: Int?
    let bundleIdentifier: String
}

// MARK: - error envelope

struct ErrorEnvelope: Encodable {
    let schemaVersion: Int
    let error: ErrorDTO

    init(_ error: Error) {
        schemaVersion = jsonSchemaVersion
        self.error = ErrorDTO(error)
    }
}

struct ErrorDTO: Encodable {
    let kind: String
    let message: String
    // Structured extras for the cases a GUI benefits from parsing.
    var address: String?
    var expected: [String]?
    var actual: String?
    var found: String?
    var supported: [String]?
    var pids: [String]?
    var path: String?

    init(_ error: Error) {
        message = error.localizedDescription
        guard let toolError = error as? ToolError else {
            kind = "unknown"
            return
        }
        switch toolError {
        case .usage:
            kind = "usage"
        case .unsupportedVersion(let found, let supported):
            kind = "unsupportedVersion"
            self.found = found
            self.supported = supported
        case .invalidConfig:
            kind = "invalidConfig"
        case .invalidHex:
            kind = "invalidHex"
        case .appInfoMissing:
            kind = "appInfoMissing"
        case .notAWechatApp(let path):
            kind = "notAWechatApp"
            self.path = path
        case .unsupportedMachO(let path):
            kind = "unsupportedMachO"
            self.path = path
        case .addressNotMapped(let address, let file):
            kind = "addressNotMapped"
            self.address = "0x" + String(address, radix: 16)
            self.path = file
        case .bytesMismatch(let address, let expected, let actual):
            kind = "bytesMismatch"
            self.address = "0x" + String(address, radix: 16)
            self.expected = expected.map(\.hexString)
            self.actual = actual.hexString
        case .noMatchingSlice(let path):
            kind = "noMatchingSlice"
            self.path = path
        case .commandFailed:
            kind = "commandFailed"
        case .signingEntitlementsMismatch(let paths):
            kind = "signingEntitlementsMismatch"
            self.path = paths.first
        case .permissionDenied(let path, _):
            kind = "permissionDenied"
            self.path = path
        case .fileOperationFailed(_, let path, _):
            kind = "fileOperationFailed"
            self.path = path
        case .appIsRunning(let path, let pids):
            kind = "appIsRunning"
            self.path = path
            self.pids = pids
        case .unsupportedAppSignature(let path, _):
            kind = "unsupportedAppSignature"
            self.path = path
        }
    }
}
