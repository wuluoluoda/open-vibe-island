// swift-tools-version: 6.2

import PackageDescription

let commandLineToolsPath = "/Library/Developer/CommandLineTools"
let testingFrameworksPath = "\(commandLineToolsPath)/Library/Developer/Frameworks"
let testingLibrariesPath = "\(commandLineToolsPath)/Library/Developer/usr/lib"
let testingMacrosPath = "\(commandLineToolsPath)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"

let swiftTestingSettings: [SwiftSetting] = [
    .unsafeFlags([
        "-F", testingFrameworksPath,
        "-load-plugin-library", testingMacrosPath,
    ]),
]

let swiftTestingLinkerSettings: [LinkerSetting] = [
    .unsafeFlags([
        "-F", testingFrameworksPath,
        "-Xlinker", "-rpath",
        "-Xlinker", testingFrameworksPath,
        "-Xlinker", "-rpath",
        "-Xlinker", testingLibrariesPath,
    ]),
]

let package = Package(
    name: "OpenIsland",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "OpenIslandCore",
            targets: ["OpenIslandCore"]
        ),
        .executable(
            name: "OpenIslandHooks",
            targets: ["OpenIslandHooks"]
        ),
        .executable(
            name: "OpenIslandSetup",
            targets: ["OpenIslandSetup"]
        ),
        .executable(
            name: "OpenIslandApp",
            targets: ["OpenIslandApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        .target(
            name: "OpenIslandCore"
        ),
        .executableTarget(
            name: "OpenIslandHooks",
            dependencies: ["OpenIslandCore"]
        ),
        .executableTarget(
            name: "OpenIslandSetup",
            dependencies: ["OpenIslandCore"]
        ),
        .executableTarget(
            name: "OpenIslandApp",
            dependencies: [
                "OpenIslandCore",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "OpenIslandCoreTests",
            dependencies: ["OpenIslandCore"],
            swiftSettings: swiftTestingSettings,
            linkerSettings: swiftTestingLinkerSettings
        ),
        .testTarget(
            name: "OpenIslandAppTests",
            dependencies: ["OpenIslandApp", "OpenIslandCore"],
            swiftSettings: swiftTestingSettings,
            linkerSettings: swiftTestingLinkerSettings
        ),
    ]
)
