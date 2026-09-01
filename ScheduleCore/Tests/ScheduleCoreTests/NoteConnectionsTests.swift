import Foundation
import Testing
@testable import ScheduleCore

@Suite("Note connections and topics")
struct NoteConnectionsTests {
    @Test("More shared tags rank before category and recency")
    func sharedTagRanking() {
        let source = snapshot(tags: ["design", "app"], category: "creative")
        let oneShared = snapshot(tags: ["design"], category: "creative", age: 0)
        let twoShared = snapshot(tags: ["app", "design"], category: "reference", age: 100)

        #expect(
            NoteConnections.rankedIDs(
                relatedTo: source,
                among: [oneShared, twoShared]
            ) == [twoShared.id, oneShared.id]
        )
    }

    @Test("Tags are normalized before matching")
    func normalizedTags() {
        let source = snapshot(tags: ["#Design"], category: "creative")
        let related = snapshot(tags: [" design "], category: "reference")

        #expect(
            NoteConnections.rankedIDs(relatedTo: source, among: [related]) == [related.id]
        )
    }

    @Test("Topics require repeated tags and prioritize larger clusters")
    func topicClusters() {
        let first = snapshot(tags: ["design", "app"], category: "creative")
        let second = snapshot(tags: ["design", "app"], category: "creative")
        let third = snapshot(tags: ["design"], category: "reference")
        let topics = NoteConnections.topics(in: [first, second, third])

        #expect(topics.map(\.name) == ["design", "app"])
        #expect(topics[0].noteIDs.count == 3)
        #expect(topics[1].noteIDs.count == 2)
    }

    private func snapshot(
        tags: [String],
        category: String,
        age: TimeInterval = 0
    ) -> NoteConnectionSnapshot {
        NoteConnectionSnapshot(
            id: UUID(),
            tags: tags,
            category: category,
            createdAt: Date().addingTimeInterval(-age)
        )
    }
}
