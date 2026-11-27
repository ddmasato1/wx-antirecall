// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "wx-antirecall",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "wx-antirecall", targets: ["AntiRecallCLI"]),
        .executable(name: "AntiRecallGUI", targets: ["AntiRecallGUI"])
    ],
    targets: [
        .executableTarget(name: "AntiRecallCLI"),
        // SwiftUI GUI shell. It shells out to the prebuilt `wx-antirecall` CLI (bundled
        // in the .app's Resources), so it has NO dependency on the CLI target. Packaged into
        // a proper .app bundle by Scripts/make-app.sh.
        .executableTarget(name: "AntiRecallGUI"),
        .testTarget(
            name: "AntiRecallTests",
            dependencies: [
                "AntiRecallCLI",
                "AntiRecallGUI"
            ]
        )
    ]
)
