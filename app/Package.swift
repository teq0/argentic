// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ArgenticCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ArgenticCore", targets: ["ArgenticCore"]),
    ],
    targets: [
        .target(name: "ArgenticCPU", publicHeadersPath: "include"),
        .target(name: "ArgenticCore", dependencies: ["ArgenticCPU"]),
        .testTarget(
            name: "ArgenticCoreTests",
            dependencies: ["ArgenticCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
