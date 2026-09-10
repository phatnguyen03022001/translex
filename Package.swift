// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Translex",
    platforms: [.macOS("26.4")],
    products: [
        .library(name: "TranslexCore", targets: ["TranslexCore"]),
        .executable(name: "TranslexApp", targets: ["TranslexApp"]),
        .executable(name: "translex", targets: ["TranslexCLI"])
    ],
    targets: [
        .target(name: "TranslexCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(
            name: "TranslexApp",
            dependencies: ["TranslexCore"],
            linkerSettings: [
                .linkedFramework("AppKit"), .linkedFramework("ApplicationServices"),
                .linkedFramework("AVFoundation"), .linkedFramework("Carbon"),
                .linkedFramework("Translation")
            ]
        ),
        .executableTarget(name: "TranslexCLI", dependencies: ["TranslexCore"]),
        .testTarget(name: "TranslexCoreTests", dependencies: ["TranslexCore"]),
        .testTarget(name: "TranslexAppTests", dependencies: ["TranslexApp"])
    ]
)
