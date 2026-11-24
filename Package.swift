// swift-tools-version: 6.2
import PackageDescription
import Foundation

// A instalação das Command Line Tools guarda as macros do Swift Testing num
// diretório de plugins separado. Com o Xcode, isso é resolvido sozinho.
let commandLineToolsTestingPlugin = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testingSwiftSettings: [SwiftSetting] = FileManager.default.fileExists(
    atPath: commandLineToolsTestingPlugin + "/libTestingMacros.dylib"
) ? [.unsafeFlags(["-plugin-path", commandLineToolsTestingPlugin])] : []

let package = Package(
    name: "GitArbor",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "GitArbor", targets: ["GitArbor"]),
        .library(name: "GitArborCore", targets: ["GitArborCore"])
    ],
    targets: [
        // Núcleo sem interface: API do GitHub, Git local, glossário.
        .target(
            name: "GitArborCore",
            path: "Sources/GitArborCore"
        ),
        // App SwiftUI/AppKit.
        .executableTarget(
            name: "GitArbor",
            dependencies: ["GitArborCore"],
            path: "Sources/GitArbor",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "GitArborCoreTests",
            dependencies: ["GitArborCore"],
            path: "Tests/GitArborCoreTests",
            swiftSettings: testingSwiftSettings
        )
    ]
)
