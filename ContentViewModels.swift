import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Notification.Name {
    static let brainNoteScheduleImported = Notification.Name(
        "BrainNoteScheduleImported"
    )
}

struct ScheduleImportOutcome {
    let month: Date
    let firstDate: Date?
    let count: Int
}

enum CanvasScope: Equatable {
    case home
    case all
    case schedule
    case category(BrainNoteCategory)
    case archive
    case trash
}


enum SheetDestination: Identifiable {
    case clipboard(String)
    case edit(BrainNote)
    case addSchedule(Date)
    case editSchedule(ScheduleEntry)
    case importSchedule(ScheduleImportDraft)
    case batchSchedule(Date)
    case bulkEditSchedule(Date)

    var id: String {
        switch self {
        case let .clipboard(text):
            "clipboard-\(text.hashValue)"
        case let .edit(note):
            "edit-\(note.id.uuidString)"
        case let .addSchedule(day):
            "add-schedule-\(Calendar.current.startOfDay(for: day).timeIntervalSinceReferenceDate)"
        case let .editSchedule(entry):
            "edit-schedule-\(entry.id.uuidString)"
        case let .importSchedule(draft):
            "import-schedule-\(draft.id.uuidString)"
        case let .batchSchedule(month):
            "batch-schedule-\(month.timeIntervalSinceReferenceDate)"
        case let .bulkEditSchedule(month):
            "bulk-edit-schedule-\(month.timeIntervalSinceReferenceDate)"
        }
    }
}
