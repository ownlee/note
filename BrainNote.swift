import Foundation
import SwiftData

enum BrainNoteCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case actionable
    case reflective
    case creative
    case reference

    var id: Self { self }
}

enum BrainNoteProcessingState: String, Codable, Sendable {
    case pending
    case complete
    case failed
}

enum BrainNoteLifecycleState: String, Codable, Sendable {
    case active
    case archived
    case trashed
}

enum BrainNoteIntent: String, Codable, Sendable {
    case note
    case task
    case event
    case scheduleSeries
}

@Model
final class BrainNote {
    @Attribute(.unique) var id: UUID
    var rawText: String
    var createdAt: Date
    var category: BrainNoteCategory
    var eventDate: Date?
    var tags: [String]
    var isCompleted: Bool
    var processingState: BrainNoteProcessingState = BrainNoteProcessingState.pending
    var lifecycleState: BrainNoteLifecycleState = BrainNoteLifecycleState.active
    var archivedAt: Date?
    var trashedAt: Date?
    var suggestedIntentRaw: String?
    var intentConfidence: Double?
    var suggestedTitle: String?
    var suggestedEndDate: Date?
    var suggestedScheduleKindRaw: String?

    init(
        id: UUID = UUID(),
        rawText: String,
        createdAt: Date = Date(),
        category: BrainNoteCategory,
        eventDate: Date? = nil,
        tags: [String] = [],
        isCompleted: Bool = false,
        processingState: BrainNoteProcessingState = .pending,
        lifecycleState: BrainNoteLifecycleState = .active,
        archivedAt: Date? = nil,
        trashedAt: Date? = nil,
        suggestedIntentRaw: String? = nil,
        intentConfidence: Double? = nil,
        suggestedTitle: String? = nil,
        suggestedEndDate: Date? = nil,
        suggestedScheduleKindRaw: String? = nil
    ) {
        self.id = id
        self.rawText = rawText
        self.createdAt = createdAt
        self.category = category
        self.eventDate = eventDate
        self.tags = tags
        self.isCompleted = isCompleted
        self.processingState = processingState
        self.lifecycleState = lifecycleState
        self.archivedAt = archivedAt
        self.trashedAt = trashedAt
        self.suggestedIntentRaw = suggestedIntentRaw
        self.intentConfidence = intentConfidence
        self.suggestedTitle = suggestedTitle
        self.suggestedEndDate = suggestedEndDate
        self.suggestedScheduleKindRaw = suggestedScheduleKindRaw
    }

    var suggestedIntent: BrainNoteIntent? {
        get { suggestedIntentRaw.flatMap(BrainNoteIntent.init(rawValue:)) }
        set { suggestedIntentRaw = newValue?.rawValue }
    }

    var suggestedScheduleKind: ScheduleKind? {
        get { suggestedScheduleKindRaw.flatMap(ScheduleKind.init(rawValue:)) }
        set { suggestedScheduleKindRaw = newValue?.rawValue }
    }
}
