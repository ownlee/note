// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScheduleCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ScheduleCore", targets: ["ScheduleCore"])
    ],
    targets: [
        .target(
            name: "ScheduleCore",
            path: ".",
            exclude: ["Package.swift", "Tests"],
            sources: ["NoteConnections.swift", "ScheduleSearch.swift"]
        ),
        .testTarget(
            name: "ScheduleCoreTests",
            dependencies: ["ScheduleCore"],
            path: "Tests/ScheduleCoreTests"
        )
    ]
)
