import Foundation
import XCTest
@testable import AntiRecallGUI

final class InstallReportStateTests: XCTestCase {
    private func report(targetStates: [String]) throws -> InstallReport {
        let entries = targetStates.map { state in
            """
            {"arch":"arm64","address":"0x461413c","fileOffset":"0x1234","state":"\(state)"}
            """
        }.joined(separator: ",")
        let json = """
        {
          "schemaVersion": 3,
          "command": "install",
          "dryRun": true,
          "resigned": false,
          "app": {
            "path": "/Applications/WeChat.app",
            "bundleIdentifier": "com.tencent.xinWeChat",
            "marketingVersion": "4.2.0",
            "installedBuild": "270390",
            "executable": "/Applications/WeChat.app/Contents/MacOS/WeChat"
          },
          "mode": ["patch silent"],
          "targets": [
            {
              "identifier": "revoke",
              "binary": "Contents/Resources/wechat.dylib",
              "entries": [\(entries)]
            }
          ]
        }
        """
        guard let report = try? JSONDecoder().decode(InstallReport.self, from: Data(json.utf8)) else {
            XCTFail("无法解析测试用 InstallReport")
            fatalError("测试 fixture 无效")
        }
        return report
    }

    func testEmptyReportIsMismatch() throws {
        XCTAssertEqual(InstallState.classify(try report(targetStates: [])), .mismatch)
    }

    func testAllAlreadyAppliedIsInstalled() throws {
        XCTAssertEqual(InstallState.classify(try report(targetStates: ["alreadyPatched"])), .installed)
    }

    func testWouldPatchIsNotInstalled() throws {
        let decoded = try report(targetStates: ["wouldPatch"])
        XCTAssertEqual(InstallState.classify(decoded), .notInstalled)
        XCTAssertEqual(InstallPreflightDisposition.classify(decoded), .installable)
    }

    func testMixedValidStatesAreNotInstalled() throws {
        // Switching modes can legitimately produce a mix: one byte already matches,
        // the other still needs patching. It is "not installed yet", not corruption.
        let decoded = try report(targetStates: ["alreadyPatched", "wouldPatch"])
        XCTAssertEqual(InstallState.classify(decoded), .notInstalled)
        XCTAssertEqual(InstallPreflightDisposition.classify(decoded), .installable)
    }

    func testMixedWithUnknownStateIsMismatch() throws {
        let decoded = try report(targetStates: ["alreadyPatched", "unknownState"])
        XCTAssertEqual(InstallState.classify(decoded), .mismatch)
    }

    func testUnknownStateIsInvalidPreflight() throws {
        XCTAssertEqual(
            InstallPreflightDisposition.classify(try report(targetStates: ["unknownState"])),
            .invalid)
    }
}
