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
                "BatchScheduleSheet.swift",
                "BrainNoteIntents.swift",
                "BrainNote.swift",
                "CanvasNavigationBar.swift",
                "ContentView.swift",
                "ContentView+Composer.swift",
                "ContentView+Dashboard.swift",
                "ContentView+Notifications.swift",
                "ContentView+NoteLifecycle.swift",
                "ContentView+ScheduleSync.swift",
                "ContentViewModels.swift",
                "NoteCardView.swift",
                "NotificationScheduler.swift",
                "NoteProcessor.swift",
                "QuickEditSheet.swift",
                "RelatedThoughtsSection.swift",
                "ScheduleCollection.swift",
                "ScheduleCore/NoteConnections.swift",
                "ScheduleCore/ScheduleSearch.swift",
                "ScheduleDashboardComponents.swift",
                "ScheduleDayEditingSheets.swift",
                "ScheduleEditorSheet.swift",
                "ScheduleEntry.swift",
                "ScheduleImportSheets.swift",
                "ScheduleTimePreset.swift",
                "SwipeActionCard.swift",
                "ToastViews.swift",
                "WorkScheduleParser.swift"
            ]
        )
    ]
)
