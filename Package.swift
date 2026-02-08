// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PressTalkASR",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PressTalkASR", targets: ["PressTalkASR"])
    ],
    targets: [
        .executableTarget(
            name: "PressTalkASR",
            path: "Sources/PressTalkASR",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/PressTalkASR/Info.plist"
                ], .when(platforms: [.macOS]))
            ]
        )
    ]
)
