import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension ContentView {
    var scheduleWidgetSignature: [String] {
        let noteSignature = notes.map { note in
            [
                note.id.uuidString,
                note.rawText,
                note.category.rawValue,
                note.eventDate?.timeIntervalSinceReferenceDate.description ?? "nil",
                note.isCompleted.description,
                note.lifecycleState.rawValue,
                note.processingState.rawValue,
            ].joined(separator: "|")
        }
        let entrySignature = scheduleEntries.map { entry in
            [
                entry.id.uuidString,
                entry.title,
                entry.startDate.timeIntervalSinceReferenceDate.description,
                entry.endDate.timeIntervalSinceReferenceDate.description,
                entry.kind.rawValue,
            ].joined(separator: "|")
        }
        return noteSignature + entrySignature
    }
    var firstVisibleScheduleDay: Date {
        visibleScheduleEntries.first(where: {
            Calendar.current.isDate(
                $0.startDate,
                equalTo: displayedScheduleMonth,
                toGranularity: .month
            )
        })?.startDate ?? displayedScheduleMonth
    }
    var visibleScheduleEntries: [ScheduleEntry] {
        scheduleEntries
    }
    func prepareScheduleMonth() {
        let calendar = Calendar.current
        let now = Date.now
        let currentMonthEntries = scheduleEntries.filter {
            calendar.isDate($0.startDate, equalTo: now, toGranularity: .month)
        }
        let preferredEntry = currentMonthEntries.first
            ?? scheduleEntries.first(where: { $0.endDate >= now })
            ?? scheduleEntries.last

        guard let preferredEntry else {
            displayedScheduleMonth = now
            selectedScheduleDay = now
            return
        }

        displayedScheduleMonth = preferredEntry.startDate
        selectedScheduleDay = preferredEntry.startDate
    }
    func migrateLegacyScheduleNotesIfNeeded() {
        let legacyNotes = notes.filter { note in
            note.category == .actionable
                && note.eventDate != nil
                && note.tags.contains { $0 == "스케줄" }
        }
        guard !legacyNotes.isEmpty else { return }

        for note in legacyNotes {
            guard let startDate = note.eventDate else { continue }
            let endDate = legacyEndDate(from: note.rawText, startDate: startDate)
            let details = note.rawText
                .components(separatedBy: "·")
                .dropFirst()
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            modelContext.insert(
                ScheduleEntry(
                    title: "근무",
                    startDate: startDate,
                    endDate: endDate,
                    kind: .work,
                    details: details
                )
            )
            notificationScheduler.cancelReminder(for: note)
            modelContext.delete(note)
        }

        try? modelContext.save()
    }
    func legacyEndDate(from text: String, startDate: Date) -> Date {
        let pattern = #"[-–—~]\s*(\d{1,2}):(\d{2})"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..., in: text)
              ),
              let hourRange = Range(match.range(at: 1), in: text),
              let minuteRange = Range(match.range(at: 2), in: text),
              let hour = Int(text[hourRange]),
              let minute = Int(text[minuteRange]) else {
            return startDate.addingTimeInterval(60 * 60)
        }

        var components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: startDate
        )
        components.hour = hour
        components.minute = minute
        guard var endDate = Calendar.current.date(from: components) else {
            return startDate.addingTimeInterval(60 * 60)
        }
        if endDate <= startDate {
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }
        return endDate
    }
    func refreshScheduleWidget() {
        let items = scheduleEntries
            .map { entry in
                BrainNoteWidgetScheduleItem(
                    id: entry.id,
                    title: entry.title,
                    eventDate: entry.startDate,
                    endDate: entry.endDate,
                    kind: entry.kind.rawValue,
                    details: entry.details
                )
            }
            .sorted { $0.eventDate < $1.eventDate }
            .prefix(60)

        BrainNoteWidgetScheduleStore.save(Array(items))
    }
    func deleteSchedule(_ entry: ScheduleEntry) {
        Task { await deleteScheduleEntry(entry) }
    }
    @MainActor
    func deleteScheduleEntry(_ entry: ScheduleEntry) async {
        if case let .editSchedule(presentedEntry) = presentedSheet,
           presentedEntry.id == entry.id {
            // A deleted SwiftData model must not remain captured by a sheet.
            // Dismiss first so the sheet cannot read invalidated properties.
            presentedSheet = nil
            await Task.yield()
        }

        modelContext.delete(entry)
        do {
            try modelContext.save()
            refreshScheduleWidget()
            presentScheduleImportConfirmation("Schedule deleted")
        } catch {
            processingError = "The schedule could not be deleted: \(error.localizedDescription)"
        }
    }
}
