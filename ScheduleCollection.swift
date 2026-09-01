import Foundation
import SwiftData

enum ScheduleSharingMode: String, Codable, CaseIterable, Sendable {
    case personal
    case team

    var title: String {
        switch self {
        case .personal: "Personal"
        case .team: "Team"
        }
    }

    var symbolName: String {
        switch self {
        case .personal: "person.fill"
        case .team: "person.2.fill"
        }
    }
}

enum ScheduleShareState: String, Codable, Sendable {
    case local
    case preparing
    case shared
    case failed
}

@Model
final class ScheduleCollection {
    @Attribute(.unique) var id: UUID
    var title: String
    var month: Date
    var kind: ScheduleKind
    var createdAt: Date
    var sharingMode: ScheduleSharingMode
    var teamID: UUID?
    var shareState: ScheduleShareState
    var cloudKitZoneName: String?
    var cloudKitZoneOwnerName: String?
    var cloudKitRootRecordName: String?
    var cloudKitShareRecordName: String?
    var shareURLString: String?
    var participantCount: Int

    init(
        id: UUID = UUID(),
        title: String,
        month: Date,
        kind: ScheduleKind,
        createdAt: Date = .now,
        sharingMode: ScheduleSharingMode = .personal,
        teamID: UUID? = nil,
        shareState: ScheduleShareState = .local,
        cloudKitZoneName: String? = nil,
        cloudKitZoneOwnerName: String? = nil,
        cloudKitRootRecordName: String? = nil,
        cloudKitShareRecordName: String? = nil,
        shareURLString: String? = nil,
        participantCount: Int = 1
    ) {
        self.id = id
        self.title = title
        self.month = month
        self.kind = kind
        self.createdAt = createdAt
        self.sharingMode = sharingMode
        self.teamID = teamID
        self.shareState = shareState
        self.cloudKitZoneName = cloudKitZoneName
        self.cloudKitZoneOwnerName = cloudKitZoneOwnerName
        self.cloudKitRootRecordName = cloudKitRootRecordName
        self.cloudKitShareRecordName = cloudKitShareRecordName
        self.shareURLString = shareURLString
        self.participantCount = participantCount
    }

    var resolvedSharingMode: ScheduleSharingMode {
        teamID == nil ? .personal : .team
    }

    func assignOwnership(_ mode: ScheduleSharingMode) {
        sharingMode = mode
        teamID = mode == .team ? (teamID ?? id) : nil
    }
}

@Model
final class ScheduleTeamMember {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
