import Foundation
import XCTest
@testable import WeChatAntiRecall

/// This fork ships a deliberately small build matrix and one patch target. Guard that
/// invariant so a future regeneration of patches.json cannot silently reintroduce
/// other builds/features.
final class SilentOnlyPatchConfigTests: XCTestCase {
    private var catalogURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/WeChatAntiRecallTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("patches.json")
    }

    func testCatalogHasOnlySupportedBuilds() throws {
        let configs = try JSONDecoder().decode([VersionConfig].self, from: Data(contentsOf: catalogURL))
        XCTAssertEqual(configs.map(\.version), ["270390", "270416", "270601"])
    }

    /// The GUI's「支持的版本」page renders "微信 x.x.x - build" from the `wechatVersion`
    /// annotation; the CLI ignores the extra key, so this only guards the UI data.
    func testEachBuildAnnotatesWeChatVersion() throws {
        let data = try Data(contentsOf: catalogURL)
        let array = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let expected: [String: String] = ["270390": "4.2.0", "270416": "4.2.0", "270601": "4.2.1"]
        XCTAssertEqual(array.count, expected.count)
        for entry in array {
            let build = try XCTUnwrap(entry["version"] as? String)
            XCTAssertEqual(entry["wechatVersion"] as? String, expected[build],
                           "build \(build) 缺少或拥有错误的 wechatVersion 标注")
        }
    }

    func testEachBuildContainsOnlyRevokeEntry() throws {
        let configs = try JSONDecoder().decode([VersionConfig].self, from: Data(contentsOf: catalogURL))
        let expected: [String: UInt64] = ["270390": 0x461413c, "270416": 0x4666e98, "270601": 0x413be8c]
        let expectedOriginal: [String: [String]] = [
            "270390": ["40100034"], "270416": ["40100034"], "270601": ["00180034", "1F2003D5"]]
        let expectedPatch: [String: String] =
            ["270390": "82000014", "270416": "82000014", "270601": "1F2003D5"]

        for config in configs {
            XCTAssertNotNil(expected[config.version])
            let identifiers = config.targets.map(\.identifier)
            XCTAssertTrue(identifiers.contains("revoke"))
            // The native recall notice needs a second, version-specific field write.
            XCTAssertEqual(identifiers.contains("revoke-tip"), ["270390", "270601"].contains(config.version))

            let target = try XCTUnwrap(config.targets.first(where: { $0.identifier == "revoke" }))
            XCTAssertEqual(target.binaryPath, "Contents/Resources/wechat.dylib")
            XCTAssertEqual(target.entries.count, 1)

            let entry = try XCTUnwrap(target.entries.first)
            XCTAssertEqual(entry.arch, .arm64)
            XCTAssertEqual(entry.address, expected[config.version])
            XCTAssertEqual(entry.expectedBytes.map(\.hexString), expectedOriginal[config.version])
            XCTAssertEqual(entry.patchBytes.hexString, expectedPatch[config.version])
        }
    }
}

/// The channel check must never reject the ad-hoc signature that this tool itself
/// produces. Regression test for the "检测失败" loop seen after a successful install:
/// the old check treated Signature=adhoc (and a missing Developer ID Authority) as an
/// App Store build, so every post-install dry-run failed even though the patch was live.
final class AppSignaturePolicyTests: XCTestCase {
    private let pristineOfficialDMG = """
        Executable=/Applications/WeChat.app/Contents/MacOS/WeChat
        Identifier=com.tencent.xinWeChat
        CodeDirectory v=20500 size=886 flags=0x10000(runtime) hashes=17+7 location=embedded
        Authority=Developer ID Application: Tencent Technology (Shenzhen) Company Limited (5A4RE8SF68)
        Authority=Developer ID Certification Authority
        Authority=Apple Root CA
        TeamIdentifier=5A4RE8SF68
        """

    private let installedAdHoc = """
        Executable=/Applications/WeChat.app/Contents/MacOS/WeChat
        Identifier=com.tencent.xinWeChat
        CodeDirectory v=20500 size=886 flags=0x10002(adhoc,runtime) hashes=17+7 location=embedded
        Signature=adhoc
        Info.plist entries=43
        TeamIdentifier=not set
        """

    private let appStore = """
        Authority=Software Signing
        Authority=Apple Code Signing Certification Authority
        Authority=Apple Root CA
        TeamIdentifier=5A4RE8SF68
        """

    func testPristineOfficialDMGIsPatchable() {
        XCTAssertEqual(
            AppSignaturePolicy.classify(hasMASReceipt: false, codesignInfo: pristineOfficialDMG),
            .patchable
        )
    }

    func testOwnAdHocResignIsPatchable() {
        XCTAssertEqual(
            AppSignaturePolicy.classify(hasMASReceipt: false, codesignInfo: installedAdHoc),
            .patchable
        )
    }

    func testMASReceiptIsRejectedEvenWhenAdHoc() {
        // An App Store build re-signed by an older tool loses its Authority but keeps
        // its receipt; the receipt must still block it.
        guard case .appStoreChannel = AppSignaturePolicy.classify(
            hasMASReceipt: true, codesignInfo: installedAdHoc
        ) else {
            return XCTFail("expected appStoreChannel")
        }
    }

    func testSoftwareSigningIsRejected() {
        guard case .appStoreChannel = AppSignaturePolicy.classify(
            hasMASReceipt: false, codesignInfo: appStore
        ) else {
            return XCTFail("expected appStoreChannel")
        }
    }

    func testAppleChainWithoutDeveloperIDIsRejected() {
        let info = "Authority=Apple Code Signing Certification Authority\nAuthority=Apple Root CA\n"
        guard case .appStoreChannel = AppSignaturePolicy.classify(
            hasMASReceipt: false, codesignInfo: info
        ) else {
            return XCTFail("expected appStoreChannel")
        }
    }

    func testSoftwareSigningCannotBeMaskedByDeveloperIDLine() {
        let mixed = appStore + "\nAuthority=Developer ID Application: Tencent ...\n"
        XCTAssertEqual(
            AppSignaturePolicy.classify(hasMASReceipt: false, codesignInfo: mixed),
            .appStoreChannel(reason: "当前签名是 Apple Software Signing（App Store 版本），不是官网 Developer ID 版")
        )
    }
}

/// The two modes are mutually exclusive: both touch the parser entry, so installing
/// both would be order-dependent. Guard the upstream-verified 270390 tip bytes too.
final class RevokeTipConfigTests: XCTestCase {
    private var catalogURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("patches.json")
    }

    func testTipTargetBytesMatchUpstream270390Record() throws {
        let configs = try JSONDecoder().decode([VersionConfig].self, from: Data(contentsOf: catalogURL))
        let build = try XCTUnwrap(configs.first(where: { $0.version == "270390" }))
        let tip = try XCTUnwrap(build.targets.first(where: { $0.identifier == "revoke-tip" }))
        XCTAssertEqual(tip.binaryPath, "Contents/Resources/wechat.dylib")
        XCTAssertEqual(tip.entries.count, 2)

        let restore = try XCTUnwrap(tip.entries.first)
        XCTAssertEqual(restore.address, 0x461413c)
        XCTAssertEqual(restore.expectedBytes.map(\.hexString), ["40100034", "82000014"])
        XCTAssertEqual(restore.patchBytes.hexString, "40100034")

        let field = try XCTUnwrap(tip.entries.last)
        XCTAssertEqual(field.address, 0x4614904)
        XCTAssertEqual(field.expectedBytes.map(\.hexString), ["60E600F9", "7FE600F9"])
        XCTAssertEqual(field.patchBytes.hexString, "7FE600F9")
    }

    func testTipAndSilentModesAreMutuallyExclusive() throws {
        let configs = try JSONDecoder().decode([VersionConfig].self, from: Data(contentsOf: catalogURL))
        let build = try XCTUnwrap(configs.first(where: { $0.version == "270390" }))
        let silent = try XCTUnwrap(build.targets.first(where: { $0.identifier == "revoke" }))
        let tip = try XCTUnwrap(build.targets.first(where: { $0.identifier == "revoke-tip" }))
        XCTAssertEqual(silent.entries.map(\.address), [0x461413c])
        XCTAssertEqual(tip.entries.map(\.address), [0x461413c, 0x4614904])
        XCTAssertNotEqual(silent.entries[0].patchBytes, tip.entries[0].patchBytes)
    }
}
