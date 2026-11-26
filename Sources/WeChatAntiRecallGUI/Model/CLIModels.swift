import Foundation

// Decodable mirrors of the CLI's `--json` output (see Sources/WeChatAntiRecall/JSONOutput.swift).
// The GUI is a separate target with no dependency on the CLI target, so it re-declares the
// shapes it consumes. `schemaVersion` lets us detect a CLI/GUI mismatch.

struct CLIAppInfo: Decodable, Equatable {
    let path: String
    let bundleIdentifier: String
    let marketingVersion: String
    let installedBuild: String
    let executable: String
}

struct VersionsReport: Decodable, Equatable {
    let schemaVersion: Int
    let app: CLIAppInfo
    let supported: Bool
    let installedBuildTargets: [String]
    let catalog: [CatalogEntry]

    struct CatalogEntry: Decodable, Equatable, Identifiable {
        let build: String
        let targets: [String]
        var id: String { build }
    }
}

struct InstallReport: Decodable {
    let schemaVersion: Int
    let command: String
    let dryRun: Bool
    let resigned: Bool
    let app: CLIAppInfo
    let mode: [String]
    let targets: [TargetReport]

    struct TargetReport: Decodable {
        let identifier: String
        let binary: String
        let entries: [EntryReport]
    }

    struct EntryReport: Decodable {
        let arch: String
        let address: String
        let fileOffset: String
        let state: String   // patched | wouldPatch | alreadyPatched
    }
}

// The CLI prints this envelope to stdout (exit 1) when `--json` is set and an error occurs.
struct CLIErrorEnvelope: Decodable, Error, LocalizedError {
    let schemaVersion: Int
    let error: CLIError

    var errorDescription: String? { error.message }
}

struct CLIError: Decodable {
    let kind: String
    let message: String
    var address: String?
    var expected: [String]?
    var actual: String?
    var found: String?
    var supported: [String]?
    var pids: [String]?
    var path: String?
}
