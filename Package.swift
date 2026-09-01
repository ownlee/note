// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScratchpadFeature",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ScratchpadFeature",
            targets: ["ScratchpadFeature"]
        )
    ],
    targets: [
        .target(
            name: "ScratchpadFeature",
            path: ".",
            exclude: [
                "BrainNote.xcodeproj",
                "BrainNoteApp",
                "BrainNoteWidget.swift",
                "BrainNoteWidgetExtension",
                "ScratchpadApp.swift",
                "WIDGET_SHORTCUT_SETUP.md",
                "ScheduleCore/Package.swift",
                "ScheduleCore/Tests",
                "Tests"
            ],
            sources: [
                "AppSecrets.swift",
                "BrainNoteIntents.swift",
                "BrainNote.swift",
                "CanvasNavigationBar.swift",
                "ContentView.swift",
                "NotificationScheduler.swift",
                "NoteProcessor.swift",
                "RelatedThoughtsSection.swift",
                "ScheduleCollection.swift",
                "ScheduleCore/NoteConnections.swift",
                "ScheduleCore/ScheduleSearch.swift",
                "ScheduleDashboardComponents.swift",
                "ScheduleEntry.swift",
                "ScheduleTimePreset.swift",
                "ScheduleSharingService.swift",
                "SwipeActionCard.swift",
                "WorkScheduleParser.swift"
            ]
        )
    ]
)
