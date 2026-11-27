import Foundation

// Resolves the two artifacts this GUI ships (CLI and the bundled patches.json),
// plus the writable working directory used for admin-run logs. In a packaged .app these live
// in Contents/Resources; during development (`swift run AntiRecallGUI`) they are resolved
// from the repo's `.build` and root so the app is testable before packaging.
enum BundledPaths {
    static var resourcesURL: URL {
        Bundle.main.resourceURL ?? Bundle.main.bundleURL
    }

    private static func firstReadable(_ candidates: [URL]) -> URL? {
        candidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    /// Walks upward until it finds this package's stable repository markers. SwiftPM's
    /// product directory has changed across toolchain versions, so fixed parent counts are
    /// deliberately avoided.
    static func repositoryRoot(startingAt directoryURL: URL, fileManager: FileManager = .default) -> URL? {
        var current = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
        while true {
            let package = current.appendingPathComponent("Package.swift")
            let sources = current.appendingPathComponent("Sources/AntiRecallGUI", isDirectory: true)
            var sourcesIsDirectory = ObjCBool(false)
            if fileManager.fileExists(atPath: package.path),
               fileManager.fileExists(atPath: sources.path, isDirectory: &sourcesIsDirectory),
               sourcesIsDirectory.boolValue {
                return current
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path || parent.path.count >= current.path.count { return nil }
            current = parent
        }
    }

    private static var devRepoRoot: URL? {
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        return repositoryRoot(startingAt: executableDirectory)
            ?? repositoryRoot(startingAt: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }

    private static var devBuildDirs: [URL] {
        guard let root = devRepoRoot else { return [] }
        return [
            root.appendingPathComponent(".build/debug"),
            root.appendingPathComponent(".build/release"),
            root.appendingPathComponent(".build/out/Products/Debug"),
            root.appendingPathComponent(".build/out/Products/Release"),
            root.appendingPathComponent(".build/arm64-apple-macosx/debug"),
            root.appendingPathComponent(".build/arm64-apple-macosx/release")
        ]
    }

    static var cli: URL {
        firstReadable(devBuildDirs.map { $0.appendingPathComponent("wx-antirecall") }
                      + [resourcesURL.appendingPathComponent("wx-antirecall")])
            ?? resourcesURL.appendingPathComponent("wx-antirecall")
    }

    /// The bundled catalog is the single offline source of truth.
    static var effectivePatchesJSON: URL {
        let bundled = resourcesURL.appendingPathComponent("patches.json")
        if FileManager.default.isReadableFile(atPath: bundled.path) { return bundled }
        return devRepoRoot?.appendingPathComponent("patches.json") ?? bundled
    }

    static var appSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AntiRecall", isDirectory: true)
    }

    static var logsDir: URL {
        appSupportDir.appendingPathComponent("logs", isDirectory: true)
    }

    @discardableResult
    static func ensureWorkingDirectories() -> Bool {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    /// Minimal sanity: decodes as a non-empty array of objects each having `version` + `targets`.
    static func isValidCatalog(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !array.isEmpty else {
            return false
        }
        return array.allSatisfy { $0["version"] is String && $0["targets"] is [Any] }
    }
}
