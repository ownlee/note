import CloudKit
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

extension Notification.Name {
    static let brainNoteSharedScheduleAccepted = Notification.Name(
        "BrainNoteSharedScheduleAccepted"
    )
}

struct ScheduleCollectionSnapshot: Sendable {
    let id: UUID
    let title: String
    let month: Date
    let kind: ScheduleKind
    let teamID: UUID?
    let teamName: String?

    init(
        id: UUID,
        title: String,
        month: Date,
        kind: ScheduleKind,
        teamID: UUID? = nil,
        teamName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.month = month
        self.kind = kind
        self.teamID = teamID
        self.teamName = teamName
    }
}

struct ScheduleEntrySnapshot: Sendable {
    let id: UUID
    let collectionID: UUID
    let title: String
    let startDate: Date
    let endDate: Date
    let kind: ScheduleKind
    let details: String?
    let labelColor: ScheduleLabelColor?
    let assigneeText: String?

    init(
        id: UUID,
        collectionID: UUID,
        title: String,
        startDate: Date,
        endDate: Date,
        kind: ScheduleKind,
        details: String?,
        labelColor: ScheduleLabelColor? = nil,
        assigneeText: String? = nil
    ) {
        self.id = id
        self.collectionID = collectionID
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.kind = kind
        self.details = details
        self.labelColor = labelColor
        self.assigneeText = assigneeText
    }
}

struct SharedSchedulePayload: Sendable {
    let collection: ScheduleCollectionSnapshot
    let entries: [ScheduleEntrySnapshot]
    let zoneName: String
    let zoneOwnerName: String
    let rootRecordName: String
    let shareRecordName: String?
    let participantCount: Int
}

struct PreparedScheduleShare: Identifiable, @unchecked Sendable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

enum ScheduleSharingError: LocalizedError {
    case iCloudUnavailable
    case missingShare
    case invalidSharedData

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            "Sign in to iCloud to share a team schedule."
        case .missingShare:
            "The team invitation could not be found."
        case .invalidSharedData:
            "The shared schedule contains data BrainNote can’t read."
        }
    }
}

actor ScheduleSharingService {
    static let shared = ScheduleSharingService()

    nonisolated let container: CKContainer

    init(container: CKContainer = .default()) {
        self.container = container
    }

    func prepareShare(
        collection: ScheduleCollectionSnapshot,
        entries: [ScheduleEntrySnapshot]
    ) async throws -> PreparedScheduleShare {
        try await requireAvailableAccount()

        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(
            zoneName: "BrainNoteTeam-\(collection.id.uuidString)",
            ownerName: CKCurrentUserDefaultName
        )
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])

        let rootID = CKRecord.ID(
            recordName: "collection-\(collection.id.uuidString)",
            zoneID: zoneID
        )
        let root = CKRecord(recordType: RecordType.collection, recordID: rootID)
        root[Field.id] = collection.id.uuidString as CKRecordValue
        root[Field.title] = collection.title as CKRecordValue
        root[Field.month] = collection.month as CKRecordValue
        root[Field.kind] = collection.kind.rawValue as CKRecordValue
        root[Field.teamID] = collection.teamID?.uuidString as CKRecordValue?
        root[Field.teamName] = collection.teamName as CKRecordValue?

        let entryRecords = entries.map { entry in
            let recordID = CKRecord.ID(
                recordName: "entry-\(entry.id.uuidString)",
                zoneID: zoneID
            )
            let record = CKRecord(recordType: RecordType.entry, recordID: recordID)
            record.parent = CKRecord.Reference(recordID: rootID, action: .deleteSelf)
            record[Field.id] = entry.id.uuidString as CKRecordValue
            record[Field.collectionID] = entry.collectionID.uuidString as CKRecordValue
            record[Field.title] = entry.title as CKRecordValue
            record[Field.startDate] = entry.startDate as CKRecordValue
            record[Field.endDate] = entry.endDate as CKRecordValue
            record[Field.kind] = entry.kind.rawValue as CKRecordValue
            if let details = entry.details, !details.isEmpty {
                record[Field.details] = details as CKRecordValue
            }
            record[Field.labelColor] = entry.labelColor?.rawValue as CKRecordValue?
            record[Field.assigneeText] = entry.assigneeText as CKRecordValue?
            return record
        }

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = collection.title as CKRecordValue
        share.publicPermission = .none

        let results = try await database.modifyRecords(
            saving: [root] + entryRecords + [share],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )

        if case let .failure(error) = results.saveResults[share.recordID] {
            throw error
        }

        let savedShare: CKShare
        if case let .success(record) = results.saveResults[share.recordID],
           let result = record as? CKShare {
            savedShare = result
        } else {
            savedShare = share
        }

        return PreparedScheduleShare(share: savedShare, container: container)
    }

    func existingShare(zoneName: String, shareRecordName: String) async throws -> PreparedScheduleShare {
        try await requireAvailableAccount()

        let zoneID = CKRecordZone.ID(
            zoneName: zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let recordID = CKRecord.ID(recordName: shareRecordName, zoneID: zoneID)
        let results = try await container.privateCloudDatabase.records(for: [recordID])

        guard case let .success(record) = results[recordID],
              let share = record as? CKShare else {
            throw ScheduleSharingError.missingShare
        }

        return PreparedScheduleShare(share: share, container: container)
    }

    func accept(_ metadata: CKShare.Metadata) async throws {
        try await requireAvailableAccount()
        let results = try await container.accept([metadata])
        if case let .failure(error) = results[metadata] {
            throw error
        }
    }

    func fetchSharedSchedules() async throws -> [SharedSchedulePayload] {
        try await requireAvailableAccount()
        let database = container.sharedCloudDatabase
        let zones = try await database.allRecordZones()
        var payloads: [SharedSchedulePayload] = []

        for zone in zones where zone.zoneID.zoneName != CKRecordZone.default().zoneID.zoneName {
            let roots = try await records(
                matching: CKQuery(recordType: RecordType.collection, predicate: NSPredicate(value: true)),
                in: zone.zoneID,
                database: database
            )

            let entryRecords = try await records(
                matching: CKQuery(recordType: RecordType.entry, predicate: NSPredicate(value: true)),
                in: zone.zoneID,
                database: database
            )

            for root in roots {
                guard let collection = collectionSnapshot(from: root) else { continue }
                let entries = entryRecords.compactMap(entrySnapshot(from:))
                    .filter { $0.collectionID == collection.id }
                let shareRecord = try? await zoneShare(in: zone.zoneID, database: database)

                payloads.append(
                    SharedSchedulePayload(
                        collection: collection,
                        entries: entries,
                        zoneName: zone.zoneID.zoneName,
                        zoneOwnerName: zone.zoneID.ownerName,
                        rootRecordName: root.recordID.recordName,
                        shareRecordName: shareRecord?.recordID.recordName,
                        participantCount: max(shareRecord?.participants.count ?? 1, 1)
                    )
                )
            }
        }

        return payloads
    }

    func updateEntry(
        _ entry: ScheduleEntrySnapshot,
        zoneName: String,
        zoneOwnerName: String
    ) async throws {
        try await requireAvailableAccount()
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwnerName)
        let recordID = CKRecord.ID(recordName: "entry-\(entry.id.uuidString)", zoneID: zoneID)
        let database = zoneOwnerName == CKCurrentUserDefaultName
            ? container.privateCloudDatabase
            : container.sharedCloudDatabase
        let result = try await database.records(for: [recordID])
        guard case let .success(record) = result[recordID] else {
            throw ScheduleSharingError.invalidSharedData
        }

        record[Field.title] = entry.title as CKRecordValue
        record[Field.startDate] = entry.startDate as CKRecordValue
        record[Field.endDate] = entry.endDate as CKRecordValue
        record[Field.kind] = entry.kind.rawValue as CKRecordValue
        record[Field.details] = entry.details as CKRecordValue?
        record[Field.labelColor] = entry.labelColor?.rawValue as CKRecordValue?
        record[Field.assigneeText] = entry.assigneeText as CKRecordValue?
        _ = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )
    }

    func participantNames(
        zoneName: String,
        zoneOwnerName: String,
        shareRecordName: String
    ) async throws -> [String] {
        try await requireAvailableAccount()
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwnerName)
        let recordID = CKRecord.ID(recordName: shareRecordName, zoneID: zoneID)
        let database = zoneOwnerName == CKCurrentUserDefaultName
            ? container.privateCloudDatabase
            : container.sharedCloudDatabase
        let results = try await database.records(for: [recordID])
        guard case let .success(record) = results[recordID],
              let share = record as? CKShare else {
            throw ScheduleSharingError.missingShare
        }

        return share.participants.compactMap { participant in
            guard let components = participant.userIdentity.nameComponents else { return nil }
            let name = PersonNameComponentsFormatter.localizedString(
                from: components,
                style: .default,
                options: []
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
    }

    func deleteEntry(
        id: UUID,
        zoneName: String,
        zoneOwnerName: String
    ) async throws {
        try await requireAvailableAccount()
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwnerName)
        let recordID = CKRecord.ID(recordName: "entry-\(id.uuidString)", zoneID: zoneID)
        let database = zoneOwnerName == CKCurrentUserDefaultName
            ? container.privateCloudDatabase
            : container.sharedCloudDatabase
        _ = try await database.modifyRecords(
            saving: [],
            deleting: [recordID],
            savePolicy: .changedKeys,
            atomically: true
        )
    }

    private func requireAvailableAccount() async throws {
        let status: CKAccountStatus = try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
        guard status == .available else { throw ScheduleSharingError.iCloudUnavailable }
    }

    private func records(
        matching query: CKQuery,
        in zoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws -> [CKRecord] {
        var output: [CKRecord] = []
        var page = try await database.records(matching: query, inZoneWith: zoneID)
        output += page.matchResults.compactMap { try? $0.1.get() }

        while let cursor = page.queryCursor {
            page = try await database.records(continuingMatchFrom: cursor)
            output += page.matchResults.compactMap { try? $0.1.get() }
        }
        return output
    }

    private func zoneShare(in zoneID: CKRecordZone.ID, database: CKDatabase) async throws -> CKShare? {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        let result = try await database.records(for: [shareID])
        guard case let .success(record) = result[shareID] else { return nil }
        return record as? CKShare
    }

    private func collectionSnapshot(from record: CKRecord) -> ScheduleCollectionSnapshot? {
        guard let idText = record[Field.id] as? String,
              let id = UUID(uuidString: idText),
              let title = record[Field.title] as? String,
              let month = record[Field.month] as? Date,
              let kindText = record[Field.kind] as? String,
              let kind = ScheduleKind(rawValue: kindText) else { return nil }
        return ScheduleCollectionSnapshot(
            id: id,
            title: title,
            month: month,
            kind: kind,
            teamID: (record[Field.teamID] as? String).flatMap(UUID.init(uuidString:)),
            teamName: record[Field.teamName] as? String
        )
    }

    private func entrySnapshot(from record: CKRecord) -> ScheduleEntrySnapshot? {
        guard let idText = record[Field.id] as? String,
              let id = UUID(uuidString: idText),
              let collectionText = record[Field.collectionID] as? String,
              let collectionID = UUID(uuidString: collectionText),
              let title = record[Field.title] as? String,
              let startDate = record[Field.startDate] as? Date,
              let endDate = record[Field.endDate] as? Date,
              let kindText = record[Field.kind] as? String,
              let kind = ScheduleKind(rawValue: kindText) else { return nil }

        return ScheduleEntrySnapshot(
            id: id,
            collectionID: collectionID,
            title: title,
            startDate: startDate,
            endDate: endDate,
            kind: kind,
            details: record[Field.details] as? String,
            labelColor: (record[Field.labelColor] as? String).flatMap(ScheduleLabelColor.init(rawValue:)),
            assigneeText: record[Field.assigneeText] as? String
        )
    }

    private enum RecordType {
        static let collection = "ScheduleCollection"
        static let entry = "ScheduleEntry"
    }

    private enum Field {
        static let id = "id"
        static let collectionID = "collectionID"
        static let title = "title"
        static let month = "month"
        static let kind = "kind"
        static let teamID = "teamID"
        static let teamName = "teamName"
        static let startDate = "startDate"
        static let endDate = "endDate"
        static let details = "details"
        static let labelColor = "labelColor"
        static let assigneeText = "assigneeText"
    }
}

#if canImport(UIKit)
@MainActor
final class BrainNoteAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task {
            do {
                try await ScheduleSharingService.shared.accept(cloudKitShareMetadata)
                NotificationCenter.default.post(name: .brainNoteSharedScheduleAccepted, object: nil)
            } catch {
                NotificationCenter.default.post(
                    name: .brainNoteSharedScheduleAccepted,
                    object: error
                )
            }
        }
    }
}

struct CloudSharingController: UIViewControllerRepresentable {
    let preparedShare: PreparedScheduleShare
    let title: String
    var onError: (Error) -> Void = { _ in }
    var onStoppedSharing: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(title: title, onError: onError, onStoppedSharing: onStoppedSharing)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(
            share: preparedShare.share,
            container: preparedShare.container
        )
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let title: String
        let onError: (Error) -> Void
        let onStoppedSharing: () -> Void

        init(
            title: String,
            onError: @escaping (Error) -> Void,
            onStoppedSharing: @escaping () -> Void
        ) {
            self.title = title
            self.onError = onError
            self.onStoppedSharing = onStoppedSharing
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            onError(error)
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onStoppedSharing()
        }
    }
}
#endif
