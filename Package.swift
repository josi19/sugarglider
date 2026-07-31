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
                // Swift 7 semantics the sources already satisfy, opted into now
                // so drift is caught by the build rather than by a future
                // toolchain bump: `any` is required at existential use sites, and
                // a member's module must be imported to use it.
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("MemberImportVisibility"),
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
