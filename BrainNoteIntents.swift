import AppIntents
import Foundation
import SwiftData

extension Notification.Name {
    static let brainNoteComposerRequested = Notification.Name(
        "BrainNoteComposerRequested"
    )
}

enum BrainNoteIntentRouteStore {
    private static let composerRequestKey = "shouldOpenBrainNoteComposer"

    @MainActor
    static func requestComposer() {
        UserDefaults.standard.set(true, forKey: composerRequestKey)
        UserDefaults.standard.synchronize()
        NotificationCenter.default.post(name: .brainNoteComposerRequested, object: nil)
    }

    @MainActor
    static func consumeComposerRequest() -> Bool {
        guard UserDefaults.standard.bool(forKey: composerRequestKey) else {
            return false
        }

        UserDefaults.standard.removeObject(forKey: composerRequestKey)
        UserDefaults.standard.synchronize()
        return true
    }
}

struct CaptureBrainNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture a Thought"
    static let description = IntentDescription(
        "Save a thought to BrainNote and organize it automatically."
    )
    static let openAppWhenRun = false

    @Parameter(
        title: "Note",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await BrainNoteIntentCaptureService.capture(text) {
        case .organized:
            return .result(dialog: "Saved and organized.")
        case .savedWithoutAnalysis:
            return .result(dialog: "Saved. You can retry organization in the app.")
        case .failed:
            return .result(dialog: "I couldn’t save that note. Please try again.")
        }
    }
}

struct OpenBrainNoteComposerIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Quick Capture"
    static let description = IntentDescription(
        "Open BrainNote with the scratchpad ready for typing."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        BrainNoteIntentRouteStore.requestComposer()
        return .result()
    }
}

struct BrainNoteAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureBrainNoteIntent(),
            phrases: [
                "Capture a thought with \(.applicationName)",
                "Save a note in \(.applicationName)",
            ],
            shortTitle: "Capture Thought",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: OpenBrainNoteComposerIntent(),
            phrases: [
                "Open quick capture in \(.applicationName)",
                "Write in \(.applicationName)",
            ],
            shortTitle: "Open Quick Capture",
            systemImageName: "square.and.pencil"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .purple }
}

@MainActor
private enum BrainNoteIntentCaptureService {
    enum Outcome {
        case organized
        case savedWithoutAnalysis
        case failed
    }

    static func capture(_ rawText: String) async -> Outcome {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failed }

        let container: ModelContainer
        do {
            container = try ModelContainer(for: BrainNote.self)
        } catch {
            return .failed
        }

        let context = container.mainContext
        let note = BrainNote(rawText: text, category: .reflective)
        context.insert(note)

        do {
            try context.save()
        } catch {
            context.delete(note)
            return .failed
        }

        do {
            let processor = NoteProcessor(apiKey: AppSecrets.openAIAPIKey)
            try await processor.process(note, in: context)

            let scheduler = NotificationScheduler()
            try await scheduler.scheduleReminder(for: note)
            return .organized
        } catch {
            note.processingState = .failed
            try? context.save()
            return .savedWithoutAnalysis
        }
    }
}
