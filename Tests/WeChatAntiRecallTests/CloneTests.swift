import Foundation
import XCTest
@testable import WeChatAntiRecall

final class CloneTests: XCTestCase {
    func testCloneMetadataAndLocalizationRules() {
        XCTAssertEqual(
            WeChatCloneMetadata.bundleIdentifier(for: 2),
            "com.tencent.xinWeChat.antirecall.clone2"
        )
        XCTAssertEqual(WeChatCloneMetadata.bundleAppName(for: 2), "WeChat 2")
        XCTAssertEqual(WeChatCloneMetadata.localizedDisplayName(for: 2, localeFolder: "zh-Hans"), "微信 2")
        XCTAssertEqual(WeChatCloneMetadata.localizedDisplayName(for: 3, localeFolder: "zh-Hant"), "微信 3")
        XCTAssertEqual(WeChatCloneMetadata.localizedDisplayName(for: 2, localeFolder: "en"), "WeChat 2")

        let validPlist: [String: Any] = [
            WeChatCloneMetadata.markerKey: true,
            WeChatCloneMetadata.cloneIndexKey: 2
        ]
        XCTAssertTrue(WeChatCloneMetadata.isAcceptedClone(
            plist: validPlist,
            bundleIdentifier: "com.tencent.xinWeChat.antirecall.clone2"
        ))
        XCTAssertFalse(WeChatCloneMetadata.isAcceptedClone(
            plist: [:],
            bundleIdentifier: "com.tencent.xinWeChat.antirecall.clone2"
        ))
        XCTAssertFalse(WeChatCloneMetadata.isAcceptedClone(
            plist: validPlist,
            bundleIdentifier: "com.tencent.xinWeChat"
        ))

        XCTAssertEqual(
            WeChatCloneMetadata.extractCloneIndex(
                plist: validPlist,
                bundleIdentifier: "com.tencent.xinWeChat.antirecall.clone9"
            ),
            2
        )
        XCTAssertEqual(
            WeChatCloneMetadata.extractCloneIndex(
                plist: [WeChatCloneMetadata.markerKey: true],
                bundleIdentifier: "com.tencent.xinWeChat.antirecall.clone5"
            ),
            5
        )
        XCTAssertNil(
            WeChatCloneMetadata.extractCloneIndex(
                plist: [WeChatCloneMetadata.markerKey: true],
                bundleIdentifier: "com.tencent.xinWeChat.antirecall.clone0"
            )
        )
    }

    func testSlotAllocationStartsAtTwoAndSkipsOccupiedSlots() throws {
        let fixture = try makeWeChatFixture(buildVersion: "270601")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let first = try WeChatCloneInstaller.create(
            options: try CloneCreateOptions([
                "--app", fixture.sourceAppURL.path,
                "--output-dir", fixture.outputDirURL.path,
                "--patch-mode", "none",
                "--skip-resign"
            ]),
            configs: []
        )
        XCTAssertEqual(first.clone.index, 2)
        XCTAssertEqual(first.clone.displayName, "微信 2")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.outputDirURL.appendingPathComponent("WeChat 2.app").path
        ))

        // Occupy slot 3 on disk with an unrelated directory to ensure slot allocation skips it.
        try FileManager.default.createDirectory(
            at: fixture.outputDirURL.appendingPathComponent("WeChat 3.app"),
            withIntermediateDirectories: true
        )

        let second = try WeChatCloneInstaller.create(
            options: try CloneCreateOptions([
                "--app", fixture.sourceAppURL.path,
                "--output-dir", fixture.outputDirURL.path,
                "--patch-mode", "none",
                "--skip-resign"
            ]),
            configs: []
        )
        XCTAssertEqual(second.clone.index, 4)
    }

    func testCreateRewritesInfoPlistAndLocalizedStringsStripsURLSchemesAndCleansBackups() throws {
        let fixture = try makeWeChatFixture(buildVersion: "270601", includeBackupArtifact: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let report = try WeChatCloneInstaller.create(
            options: try CloneCreateOptions([
                "--app", fixture.sourceAppURL.path,
                "--output-dir", fixture.outputDirURL.path,
                "--patch-mode", "none"
            ]),
            configs: []
        )
        let cloneURL = URL(fileURLWithPath: report.clone.path)

        let plistData = try Data(contentsOf: cloneURL.appendingPathComponent("Contents/Info.plist"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        )
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.tencent.xinWeChat.antirecall.clone2")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "WeChat 2")
        XCTAssertEqual(plist[WeChatCloneMetadata.markerKey] as? Bool, true)
        XCTAssertEqual(plist[WeChatCloneMetadata.cloneIndexKey] as? Int, 2)
        XCTAssertEqual(plist[WeChatCloneMetadata.sourceBundleIdentifierKey] as? String, "com.tencent.xinWeChat")
        XCTAssertNil(plist["CFBundleURLTypes"])
        XCTAssertEqual(plist["SUEnableAutomaticChecks"] as? Bool, false)
        XCTAssertEqual(plist["SUAutomaticallyUpdate"] as? Bool, false)
        XCTAssertEqual(plist["SUAllowsAutomaticUpdates"] as? Bool, false)
        XCTAssertNil(plist["SUEnableInstallerLauncherService"])
        XCTAssertNil(plist["SUFeedURL"])

        let zhStringsURL = cloneURL.appendingPathComponent("Contents/Resources/zh-Hans.lproj/InfoPlist.strings")
        let enStringsURL = cloneURL.appendingPathComponent("Contents/Resources/en.lproj/InfoPlist.strings")
        XCTAssertEqual(try run("/usr/bin/plutil", ["-lint", zhStringsURL.path]), 0)
        XCTAssertEqual(try run("/usr/bin/plutil", ["-lint", enStringsURL.path]), 0)

        let zhDict = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: zhStringsURL), options: [], format: nil) as? [String: Any]
        )
        let enDict = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: enStringsURL), options: [], format: nil) as? [String: Any]
        )
        XCTAssertEqual(zhDict["CFBundleDisplayName"] as? String, "微信 2")
        XCTAssertEqual(zhDict["CFBundleName"] as? String, "微信 2")
        XCTAssertEqual(enDict["CFBundleDisplayName"] as? String, "WeChat 2")

        // Inherited backup files must be stripped from the clone while preserved in the source.
        let cloneBackup = cloneURL.appendingPathComponent(
            "Contents/Resources/wechat.dylib.wechat-antirecall-backup-20260101-000000"
        )
        let sourceBackup = fixture.sourceAppURL.appendingPathComponent(
            "Contents/Resources/wechat.dylib.wechat-antirecall-backup-20260101-000000"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloneBackup.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceBackup.path))

        // Verify signature passes and original sandbox entitlements were stripped.
        XCTAssertEqual(try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", cloneURL.path]), 0)
        XCTAssertTrue(try readEntitlements(at: cloneURL).isEmpty)
    }

    func testPatchModesSwitchAndRevertCleanlyAcrossIndependentTargets() throws {
        let fixture = try makeWeChatFixture(buildVersion: "270601")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let configs = [fixture.syntheticConfig]

        // 1. Create clone 2 with silent patch from pristine source.
        let silentCreate = try WeChatCloneInstaller.create(
            options: try CloneCreateOptions([
                "--app", fixture.sourceAppURL.path,
                "--output-dir", fixture.outputDirURL.path,
                "--index", "2",
                "--patch-mode", "silent"
            ]),
            configs: configs
        )
        XCTAssertEqual(silentCreate.clone.patchState, "silent")

        // 2. Patch the source WeChat itself into `silent`, then create clone 3 with `with-tip`
        //    and clone 4 with `none`. Both must revert the source's `silent` patch site cleanly!
        _ = try MachOPatcher(fileURL: fixture.sourceDylibURL).patch(
            entries: fixture.syntheticConfig.targets[0].entries,
            dryRun: false
        )
        try resign(appURL: fixture.sourceAppURL, nestedBinaries: [fixture.sourceDylibURL], preserveEntitlements: false)

        let tipCreate = try WeChatCloneInstaller.create(
            options: try CloneCreateOptions([
                "--app", fixture.sourceAppURL.path,
                "--output-dir", fixture.outputDirURL.path,
                "--index", "3",
                "--patch-mode", "with-tip"
            ]),
            configs: configs
        )
        XCTAssertEqual(tipCreate.clone.patchState, "withTip")

        let noneCreate = try WeChatCloneInstaller.create(
            options: try CloneCreateOptions([
                "--app", fixture.sourceAppURL.path,
                "--output-dir", fixture.outputDirURL.path,
                "--index", "4",
                "--patch-mode", "none"
            ]),
            configs: configs
        )
        XCTAssertEqual(noneCreate.clone.patchState, "none")

        let listReport = try WeChatCloneScanner.listReport(
            outputDir: fixture.outputDirURL.path,
            configs: configs
        )
        XCTAssertEqual(listReport.clones.map(\.index), [2, 3, 4])
        XCTAssertEqual(listReport.clones.map(\.patchState), ["silent", "withTip", "none"])
        XCTAssertEqual(listReport.nextAvailableIndex, 5)
    }

    func testReplaceAtomicallyWithoutResidualBundlesAndRemoveGuardsNonClones() throws {
        let fixture = try makeWeChatFixture(buildVersion: "270601")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let configs = [fixture.syntheticConfig]

        _ = try WeChatCloneInstaller.create(
            options: try CloneCreateOptions([
                "--app", fixture.sourceAppURL.path,
                "--output-dir", fixture.outputDirURL.path,
                "--index", "2",
                "--patch-mode", "none"
            ]),
            configs: configs
        )

        // Without --replace, creating at an existing index must fail.
        XCTAssertThrowsError(try WeChatCloneInstaller.create(
            options: try CloneCreateOptions([
                "--app", fixture.sourceAppURL.path,
                "--output-dir", fixture.outputDirURL.path,
                "--index", "2",
                "--patch-mode", "silent"
            ]),
            configs: configs
        ))

        // With --replace, it updates cleanly and leaves no hidden/backup residue.
        let replaced = try WeChatCloneInstaller.create(
            options: try CloneCreateOptions([
                "--app", fixture.sourceAppURL.path,
                "--output-dir", fixture.outputDirURL.path,
                "--index", "2",
                "--patch-mode", "silent",
                "--replace"
            ]),
            configs: configs
        )
        XCTAssertTrue(replaced.replaced)
        XCTAssertEqual(replaced.clone.patchState, "silent")

        let allItems = try FileManager.default.contentsOfDirectory(atPath: fixture.outputDirURL.path)
        XCTAssertEqual(allItems, ["WeChat 2.app"])

        // Non-clone bundle at WeChat 5.app must NEVER be overwritten or removed.
        let fakeAppURL = fixture.outputDirURL.appendingPathComponent("WeChat 5.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: fakeAppURL.appendingPathComponent("Contents"),
            withIntermediateDirectories: true
        )
        try writePlist(
            [
                "CFBundleIdentifier": "com.example.unrelated",
                "CFBundleName": "Unrelated",
                "CFBundleVersion": "1"
            ],
            to: fakeAppURL.appendingPathComponent("Contents/Info.plist")
        )

        XCTAssertThrowsError(try WeChatCloneInstaller.create(
            options: try CloneCreateOptions([
                "--app", fixture.sourceAppURL.path,
                "--output-dir", fixture.outputDirURL.path,
                "--index", "5",
                "--replace"
            ]),
            configs: configs
        ))
        XCTAssertThrowsError(try WeChatCloneInstaller.remove(
            options: try CloneRemoveOptions(["--target", fakeAppURL.path])
        ))
        XCTAssertThrowsError(try WeChatCloneInstaller.remove(
            options: try CloneRemoveOptions(["--target", fixture.sourceAppURL.path])
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fakeAppURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.sourceAppURL.path))

        // Removing the legitimate clone succeeds.
        let clone2URL = fixture.outputDirURL.appendingPathComponent("WeChat 2.app")
        let removed = try WeChatCloneInstaller.remove(
            options: try CloneRemoveOptions(["--target", clone2URL.path])
        )
        XCTAssertEqual(removed.index, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: clone2URL.path))
    }

    // MARK: - Fixture Helpers

    private struct WeChatFixture {
        let root: URL
        let sourceAppURL: URL
        let sourceDylibURL: URL
        let outputDirURL: URL
        let syntheticConfig: VersionConfig
    }

    private func makeWeChatFixture(
        buildVersion: String,
        includeBackupArtifact: Bool = false
    ) throws -> WeChatFixture {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(
            "wechat-antirecall-clone-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        let sourceDir = root.appendingPathComponent("source", isDirectory: true)
        let outputDirURL = root.appendingPathComponent("output", isDirectory: true)
        let sourceAppURL = sourceDir.appendingPathComponent("WeChat.app", isDirectory: true)
        let macOSDir = sourceAppURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let resourcesDir = sourceAppURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let zhLprojDir = resourcesDir.appendingPathComponent("zh-Hans.lproj", isDirectory: true)
        let enLprojDir = resourcesDir.appendingPathComponent("en.lproj", isDirectory: true)

        for dir in [macOSDir, zhLprojDir, enLprojDir, outputDirURL] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let execC = root.appendingPathComponent("main.c")
        try "int main(void) { return 0; }\n".write(to: execC, atomically: true, encoding: .utf8)
        let execURL = macOSDir.appendingPathComponent("WeChat")
        XCTAssertEqual(
            try run("/usr/bin/xcrun", ["clang", "-arch", "arm64", execC.path, "-o", execURL.path]),
            0
        )

        // Build a tiny real arm64 dylib with two patchable functions so MachOPatcher + codesign work end-to-end.
        let dylibC = root.appendingPathComponent("wechat_dylib.c")
        try """
        int gate_a(int x) { return x + 11; }
        int gate_b(int x) { return x + 22; }
        """.write(to: dylibC, atomically: true, encoding: .utf8)
        let dylibURL = resourcesDir.appendingPathComponent("wechat.dylib")
        XCTAssertEqual(
            try run("/usr/bin/xcrun", ["clang", "-arch", "arm64", "-dynamiclib", dylibC.path, "-o", dylibURL.path]),
            0
        )

        let (addrA, origA, addrB, origB) = try locateTwoInstructionSites(in: dylibURL)
        let nop = try Data(hexString: "1F2003D5")
        let configJSON = """
        [
          {
            "version": "\(buildVersion)",
            "targets": [
              {
                "identifier": "revoke",
                "binary": "Contents/Resources/wechat.dylib",
                "entries": [
                  {
                    "arch": "arm64",
                    "addr": "\(String(addrA, radix: 16))",
                    "expected": ["\(origA.hexString)", "\(nop.hexString)"],
                    "asm": "\(nop.hexString)"
                  }
                ]
              },
              {
                "identifier": "revoke-tip",
                "binary": "Contents/Resources/wechat.dylib",
                "entries": [
                  {
                    "arch": "arm64",
                    "addr": "\(String(addrB, radix: 16))",
                    "expected": ["\(origB.hexString)", "\(nop.hexString)"],
                    "asm": "\(nop.hexString)"
                  }
                ]
              }
            ]
          }
        ]
        """
        let configs = try JSONDecoder().decode([VersionConfig].self, from: Data(configJSON.utf8))

        if includeBackupArtifact {
            let backupURL = resourcesDir.appendingPathComponent("wechat.dylib.wechat-antirecall-backup-20260101-000000")
            try Data("backup".utf8).write(to: backupURL)
        }

        try writePlist(
            [
                "CFBundleExecutable": "WeChat",
                "CFBundleIdentifier": "com.tencent.xinWeChat",
                "CFBundleName": "WeChat",
                "CFBundleDisplayName": "WeChat",
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "4.2.1",
                "CFBundleVersion": buildVersion,
                "CFBundleURLTypes": [
                    ["CFBundleURLSchemes": ["weixin", "wechat"]]
                ],
                "SUEnableInstallerLauncherService": true,
                "SUFeedURL": "https://example.com/appcast.xml"
            ],
            to: sourceAppURL.appendingPathComponent("Contents/Info.plist")
        )

        // OpenStep .strings in zh-Hans, binary plist .strings in en.
        try "\"CFBundleDisplayName\" = \"微信\";\n\"CFBundleName\" = \"微信\";\n".write(
            to: zhLprojDir.appendingPathComponent("InfoPlist.strings"),
            atomically: true,
            encoding: .utf8
        )
        let enBinaryStrings = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleDisplayName": "WeChat"],
            format: .binary,
            options: 0
        )
        try enBinaryStrings.write(to: enLprojDir.appendingPathComponent("InfoPlist.strings"))

        let entitlementsURL = root.appendingPathComponent("source-entitlements.plist")
        try writePlist(
            [
                "com.apple.security.app-sandbox": true,
                "com.apple.security.network.client": true
            ],
            to: entitlementsURL
        )
        XCTAssertEqual(try run("/usr/bin/codesign", ["--force", "--sign", "-", dylibURL.path]), 0)
        XCTAssertEqual(
            try run(
                "/usr/bin/codesign",
                ["--force", "--sign", "-", "--entitlements", entitlementsURL.path, sourceAppURL.path]
            ),
            0
        )

        return WeChatFixture(
            root: root,
            sourceAppURL: sourceAppURL,
            sourceDylibURL: dylibURL,
            outputDirURL: outputDirURL,
            syntheticConfig: try XCTUnwrap(configs.first)
        )
    }

    private func locateTwoInstructionSites(in dylibURL: URL) throws -> (UInt64, Data, UInt64, Data) {
        let data = try Data(contentsOf: dylibURL)
        let ncmds = Int(data.leUInt32(at: 16))
        var cmdOffset = 32
        for _ in 0..<ncmds {
            let cmd = data.leUInt32(at: cmdOffset)
            let cmdsize = Int(data.leUInt32(at: cmdOffset + 4))
            if cmd == 0x19 { // LC_SEGMENT_64
                let nsects = Int(data.leUInt32(at: cmdOffset + 64))
                var sectOffset = cmdOffset + 72
                for _ in 0..<nsects {
                    let sectNameData = data.subdata(in: sectOffset..<(sectOffset + 16))
                    let sectName = String(bytes: sectNameData.prefix { $0 != 0 }, encoding: .utf8) ?? ""
                    if sectName == "__text" {
                        let addr = data.leUInt64(at: sectOffset + 32)
                        let offset = Int(data.leUInt32(at: sectOffset + 48))
                        let origA = data.subdata(in: offset..<(offset + 4))
                        let origB = data.subdata(in: (offset + 8)..<(offset + 12))
                        return (addr, origA, addr + 8, origB)
                    }
                    sectOffset += 80
                }
            }
            cmdOffset += cmdsize
        }
        throw NSError(domain: "CloneTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "__text section not found"])
    }

    private func writePlist(_ dictionary: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    private func readEntitlements(at appURL: URL) throws -> [String: Any] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "--entitlements", "-", "--xml", appURL.path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard !data.isEmpty else { return [:] }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]) ?? [:]
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
