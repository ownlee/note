import Foundation
import SwiftData

@Model
final class ScheduleCollection {
    @Attribute(.unique) var id: UUID
    var title: String
    var month: Date
    var kind: ScheduleKind
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        month: Date,
        kind: ScheduleKind,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.month = month
        self.kind = kind
        self.createdAt = createdAt
    }
}
