import Foundation
import WidgetKit

struct BrainNoteWidgetScheduleItem: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let eventDate: Date
    let endDate: Date?
    let kind: String?
    let details: String?

    init(
        id: UUID,
        title: String,
        eventDate: Date,
        endDate: Date? = nil,
        kind: String? = nil,
        details: String? = nil
    ) {
        self.id = id
        self.title = title
        self.eventDate = eventDate
        self.endDate = endDate
        self.kind = kind
        self.details = details
    }
}

enum BrainNoteWidgetScheduleStore {
    static let appGroupIdentifier = "group.com.won.BrainNote"
    static let scheduleWidgetKind = "BrainNoteScheduleWidget"
    static let scheduleDetailWidgetKind = "BrainNoteScheduleDetailWidget"

    private static let itemsKey = "brainNoteScheduleItems"

    static func load() -> [BrainNoteWidgetScheduleItem] {
        guard let data = sharedDefaults.data(forKey: itemsKey),
              let items = try? JSONDecoder().decode(
                  [BrainNoteWidgetScheduleItem].self,
                  from: data
              ) else {
            return []
        }

        return items
    }

    static func save(_ items: [BrainNoteWidgetScheduleItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        sharedDefaults.set(data, forKey: itemsKey)
        WidgetCenter.shared.reloadTimelines(ofKind: scheduleWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: scheduleDetailWidgetKind)
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}
