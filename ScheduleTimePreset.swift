import Foundation
import SwiftData

@Model
final class ScheduleTimePreset {
    @Attribute(.unique) var id: UUID
    var name: String
    var startMinutes: Int
    var endMinutes: Int
    var kind: ScheduleKind
    var createdAt: Date
    var labelColor: ScheduleLabelColor?

    init(
        id: UUID = UUID(),
        name: String,
        startMinutes: Int,
        endMinutes: Int,
        kind: ScheduleKind = .work,
        createdAt: Date = .now,
        labelColor: ScheduleLabelColor? = nil
    ) {
        self.id = id
        self.name = name
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.kind = kind
        self.createdAt = createdAt
        self.labelColor = labelColor
    }

    func interval(on day: Date, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        let normalizedDay = calendar.startOfDay(for: day)
        guard let start = calendar.date(byAdding: .minute, value: startMinutes, to: normalizedDay),
              var end = calendar.date(byAdding: .minute, value: endMinutes, to: normalizedDay) else {
            return nil
        }
        if endMinutes <= startMinutes {
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        }
        return (start, end)
    }

    var timeRangeText: String {
        "\(Self.timeText(startMinutes))–\(Self.timeText(endMinutes))"
    }

    private static func timeText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
