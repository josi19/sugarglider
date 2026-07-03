// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Sugarglider",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Sugarglider",
            path: "Sources/Sugarglider",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-Osize"], .when(configuration: .release)),
            ]
        ),
        .testTarget(
            name: "SugargliderTests",
            dependencies: ["Sugarglider"],
            path: "Tests/SugargliderTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
