import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct BrainNoteEdits {
    var rawText: String
    var category: BrainNoteCategory
    var eventDate: Date?
    var tags: [String]
    var isCompleted: Bool

    init(note: BrainNote) {
        rawText = note.rawText
        category = note.category
        eventDate = note.eventDate
        tags = note.tags
        isCompleted = note.isCompleted
    }

    func normalizedRawText(fallback: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    var normalizedTags: [String] {
        var seen = Set<String>()

        return tags.compactMap { tag in
            let normalized = tag
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard !normalized.isEmpty else { return nil }

            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return normalized
        }
        .prefix(8)
        .map { $0 }
    }

    func apply(to note: BrainNote) {
        note.rawText = rawText
        note.category = category
        note.eventDate = eventDate
        note.tags = tags
        note.isCompleted = isCompleted
    }
}

struct LifecycleSnapshot {
    let state: BrainNoteLifecycleState
    let archivedAt: Date?
    let trashedAt: Date?

    init(note: BrainNote) {
        state = note.lifecycleState
        archivedAt = note.archivedAt
        trashedAt = note.trashedAt
    }

    func apply(to note: BrainNote) {
        note.lifecycleState = state
        note.archivedAt = archivedAt
        note.trashedAt = trashedAt
    }
}

struct PendingLifecycleUndo: Identifiable {
    let id = UUID()
    let noteID: UUID
    let previous: LifecycleSnapshot
    let message: String
}


extension ContentView {
    @discardableResult
    func applyProcessedIntent(
        _ result: NoteProcessingResult,
        to note: BrainNote
    ) -> Bool {
        let needsClarification = result.confidence < 0.8
            && (result.intent == .task || result.intent == .event)

        if needsClarification {
            note.category = .reflective
            note.suggestedIntent = result.intent
            note.intentConfidence = result.confidence
            note.suggestedTitle = result.title
            note.suggestedEndDate = result.endDate
            note.suggestedScheduleKind = result.scheduleKind
            try? modelContext.save()
            return true
        }

        clearIntentSuggestion(on: note)

        switch result.intent {
        case .task:
            note.category = .actionable
            try? modelContext.save()
            return true

        case .event:
            guard let startDate = result.eventDate else {
                note.suggestedIntent = .event
                note.intentConfidence = result.confidence
                note.suggestedTitle = result.title
                note.suggestedScheduleKind = result.scheduleKind
                try? modelContext.save()
                return true
            }
            return !moveNoteToSchedule(
                note,
                title: result.title,
                startDate: startDate,
                endDate: result.endDate,
                kind: result.scheduleKind
            )

        case .scheduleSeries:
            // Repeated schedules are normally routed before note creation by the local parser.
            // Keep parser misses safely as reference notes instead of guessing multiple dates.
            note.category = .reference
            note.eventDate = nil
            try? modelContext.save()
            return true

        case .note:
            note.eventDate = result.category == .actionable ? result.eventDate : nil
            try? modelContext.save()
            return true
        }
    }
    func resolveIntent(of note: BrainNote, as intent: BrainNoteIntent) {
        switch intent {
        case .task:
            note.category = .actionable
            clearIntentSuggestion(on: note)
            do {
                try modelContext.save()
                refreshReminder(for: note)
            } catch {
                processingError = "The task could not be saved: \(error.localizedDescription)"
            }

        case .event:
            guard let startDate = note.eventDate else { return }
            _ = moveNoteToSchedule(
                note,
                title: note.suggestedTitle ?? note.rawText,
                startDate: startDate,
                endDate: note.suggestedEndDate,
                kind: note.suggestedScheduleKind ?? .other
            )

        case .note:
            note.category = .reflective
            note.eventDate = nil
            clearIntentSuggestion(on: note)
            try? modelContext.save()

        case .scheduleSeries:
            break
        }
    }
    @discardableResult
    func moveNoteToSchedule(
        _ note: BrainNote,
        title: String,
        startDate: Date,
        endDate: Date?,
        kind: ScheduleKind
    ) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEnd = max(
            endDate ?? startDate.addingTimeInterval(60 * 60),
            startDate.addingTimeInterval(60)
        )
        let entry = ScheduleEntry(
            title: cleanTitle.isEmpty ? note.rawText : cleanTitle,
            startDate: startDate,
            endDate: resolvedEnd,
            kind: kind,
            details: cleanTitle == note.rawText ? nil : note.rawText,
            labelColor: kind.defaultLabelColor
        )

        modelContext.insert(entry)
        modelContext.delete(note)

        do {
            try modelContext.save()
            refreshScheduleWidget()
            presentScheduleImportConfirmation("Added to Schedule · \(entry.title)")
            return true
        } catch {
            modelContext.rollback()
            processingError = "The schedule could not be created: \(error.localizedDescription)"
            return false
        }
    }
    func clearIntentSuggestion(on note: BrainNote) {
        note.suggestedIntent = nil
        note.intentConfidence = nil
        note.suggestedTitle = nil
        note.suggestedEndDate = nil
        note.suggestedScheduleKind = nil
    }
    func toggleCompletion(of note: BrainNote) {
        let previousValue = note.isCompleted

        withAnimation(.snappy) {
            note.isCompleted.toggle()
        }

        do {
            try modelContext.save()
        } catch {
            note.isCompleted = previousValue
            processingError = "The completion status could not be saved: \(error.localizedDescription)"
            return
        }

        if note.isCompleted {
            notificationScheduler.cancelReminder(for: note)
        } else {
            Task { @MainActor in
                do {
                    try await notificationScheduler.scheduleReminder(for: note)
                } catch {
                    processingError = "The reminder could not be scheduled: \(error.localizedDescription)"
                }
            }
        }
    }
    func saveEdits(_ edits: BrainNoteEdits, to note: BrainNote) {
        let previous = BrainNoteEdits(note: note)

        note.rawText = edits.normalizedRawText(fallback: previous.rawText)
        note.category = edits.category
        note.eventDate = edits.category == .actionable ? edits.eventDate : nil
        note.tags = edits.normalizedTags
        note.isCompleted = edits.category == .actionable ? edits.isCompleted : false

        do {
            try modelContext.save()
        } catch {
            previous.apply(to: note)
            processingError = "The note changes could not be saved: \(error.localizedDescription)"
            return
        }

        refreshReminder(for: note)
    }
    func archive(_ note: BrainNote) {
        applyLifecycleChange(to: note, message: "Moved to Archive") {
            note.lifecycleState = .archived
            note.archivedAt = Date()
            note.trashedAt = nil
        }
    }
    func unarchive(_ note: BrainNote) {
        applyLifecycleChange(to: note, message: "Returned to your canvas") {
            note.lifecycleState = .active
            note.archivedAt = nil
            note.trashedAt = nil
        }
    }
    func moveToTrash(_ note: BrainNote) {
        applyLifecycleChange(to: note, message: "Moved to Recently Deleted") {
            note.lifecycleState = .trashed
            note.trashedAt = Date()
        }
    }
    func restoreFromTrash(_ note: BrainNote) {
        let restoreState: BrainNoteLifecycleState = note.archivedAt == nil ? .active : .archived

        applyLifecycleChange(to: note, message: "Note restored") {
            note.lifecycleState = restoreState
            note.trashedAt = nil
        }
    }
    func applyLifecycleChange(
        to note: BrainNote,
        message: String,
        update: () -> Void
    ) {
        let previous = LifecycleSnapshot(note: note)

        withAnimation(.snappy) {
            update()
        }

        do {
            try modelContext.save()
        } catch {
            previous.apply(to: note)
            processingError = "The note could not be moved: \(error.localizedDescription)"
            return
        }

        refreshReminder(for: note)
        presentUndo(for: note, previous: previous, message: message)
    }
    func presentUndo(
        for note: BrainNote,
        previous: LifecycleSnapshot,
        message: String
    ) {
        undoDismissTask?.cancel()

        withAnimation(.snappy) {
            pendingUndo = PendingLifecycleUndo(
                noteID: note.id,
                previous: previous,
                message: message
            )
        }

        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }

            withAnimation(.snappy) {
                pendingUndo = nil
            }
        }
    }
    func undoLifecycleChange() {
        guard let pendingUndo,
              let note = notes.first(where: { $0.id == pendingUndo.noteID }) else {
            self.pendingUndo = nil
            return
        }

        undoDismissTask?.cancel()
        let current = LifecycleSnapshot(note: note)

        withAnimation(.snappy) {
            pendingUndo.previous.apply(to: note)
            self.pendingUndo = nil
        }

        do {
            try modelContext.save()
        } catch {
            current.apply(to: note)
            processingError = "The move could not be undone: \(error.localizedDescription)"
            return
        }

        refreshReminder(for: note)
    }
    func refreshReminder(for note: BrainNote) {
        guard note.lifecycleState == .active else {
            notificationScheduler.cancelReminder(for: note)
            return
        }

        Task { @MainActor in
            do {
                try await notificationScheduler.scheduleReminder(for: note)
            } catch {
                processingError = "The reminder could not be updated: \(error.localizedDescription)"
            }
        }
    }
    func permanentlyDelete(_ note: BrainNote) {
        notificationScheduler.cancelReminder(for: note)
        modelContext.delete(note)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            processingError = "The note could not be permanently deleted: \(error.localizedDescription)"
        }
    }
    func purgeExpiredTrash() {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else {
            return
        }

        let expiredNotes = trashedNotes.filter { note in
            guard let trashedAt = note.trashedAt else { return false }
            return trashedAt <= cutoff
        }

        guard !expiredNotes.isEmpty else { return }

        for note in expiredNotes {
            notificationScheduler.cancelReminder(for: note)
            modelContext.delete(note)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            processingError = "Expired deleted notes could not be cleared: \(error.localizedDescription)"
        }
    }
}
