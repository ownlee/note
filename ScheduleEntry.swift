import Foundation
import SwiftData
import SwiftUI

enum ScheduleKind: String, Codable, CaseIterable, Sendable {
    case work
    case exercise
    case appointment
    case personal
    case travel
    case other

    var title: String {
        switch self {
        case .work: "근무"
        case .exercise: "운동"
        case .appointment: "약속"
        case .personal: "개인 일정"
        case .travel: "이동"
        case .other: "일정"
        }
    }

    var symbolName: String {
        switch self {
        case .work: "briefcase.fill"
        case .exercise: "figure.run"
        case .appointment: "person.2.fill"
        case .personal: "calendar"
        case .travel: "location.fill"
        case .other: "clock.fill"
        }
    }

    var tint: Color {
        switch self {
        case .work: .indigo
        case .exercise: .green
        case .appointment: .pink
        case .personal: .orange
        case .travel: .cyan
        case .other: .secondary
        }
    }

    var defaultLabelColor: ScheduleLabelColor {
        switch self {
        case .work: .indigo
        case .exercise: .green
        case .appointment: .pink
        case .personal: .orange
        case .travel: .teal
        case .other: .gray
        }
    }
}

enum ScheduleLabelColor: String, Codable, CaseIterable, Sendable {
    case indigo, blue, teal, green, orange, pink, red, gray

    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .indigo: .indigo
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .red: .red
        case .gray: .gray
        }
    }
}

@Model
final class ScheduleEntry {
    @Attribute(.unique) var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var kind: ScheduleKind
    var details: String?
    var createdAt: Date
    var seriesID: UUID?
    // Optional so existing stores migrate without rewriting old schedules.
    var labelColor: ScheduleLabelColor?

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        kind: ScheduleKind = .other,
        details: String? = nil,
        createdAt: Date = .now,
        seriesID: UUID? = nil,
        labelColor: ScheduleLabelColor? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.kind = kind
        self.details = details
        self.createdAt = createdAt
        self.seriesID = seriesID
        self.labelColor = labelColor
    }

    var tint: Color { labelColor?.color ?? kind.tint }
}
