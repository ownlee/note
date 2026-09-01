import Foundation

struct NoteConnectionSnapshot: Sendable {
    let id: UUID
    let tags: [String]
    let category: String
    let createdAt: Date
}

struct NoteTopic: Equatable, Sendable {
    let name: String
    let noteIDs: [UUID]
    let latestActivity: Date
}

enum NoteConnections {
    static func rankedIDs(
        relatedTo source: NoteConnectionSnapshot,
        among candidates: [NoteConnectionSnapshot],
        limit: Int = 3
    ) -> [UUID] {
        let sourceTags = normalizedTags(source.tags)
        guard !sourceTags.isEmpty, limit > 0 else { return [] }

        return candidates
            .filter { candidate in
                candidate.id != source.id
                    && !sourceTags.isDisjoint(with: normalizedTags(candidate.tags))
            }
            .sorted { lhs, rhs in
                let lhsSharedCount = sourceTags.intersection(normalizedTags(lhs.tags)).count
                let rhsSharedCount = sourceTags.intersection(normalizedTags(rhs.tags)).count

                if lhsSharedCount != rhsSharedCount {
                    return lhsSharedCount > rhsSharedCount
                }
                if (lhs.category == source.category) != (rhs.category == source.category) {
                    return lhs.category == source.category
                }
                return lhs.createdAt > rhs.createdAt
            }
            .prefix(limit)
            .map(\.id)
    }

    static func topics(
        in notes: [NoteConnectionSnapshot],
        minimumNoteCount: Int = 2,
        limit: Int = 8
    ) -> [NoteTopic] {
        guard minimumNoteCount > 0, limit > 0 else { return [] }

        var notesByTag: [String: [NoteConnectionSnapshot]] = [:]
        for note in notes {
            for tag in normalizedTags(note.tags) {
                notesByTag[tag, default: []].append(note)
            }
        }

        return notesByTag
            .compactMap { tag, taggedNotes -> NoteTopic? in
                guard taggedNotes.count >= minimumNoteCount,
                      let latestActivity = taggedNotes.map(\.createdAt).max() else { return nil }
                return NoteTopic(
                    name: tag,
                    noteIDs: taggedNotes.sorted { $0.createdAt > $1.createdAt }.map(\.id),
                    latestActivity: latestActivity
                )
            }
            .sorted { lhs, rhs in
                if lhs.noteIDs.count != rhs.noteIDs.count {
                    return lhs.noteIDs.count > rhs.noteIDs.count
                }
                if lhs.latestActivity != rhs.latestActivity {
                    return lhs.latestActivity > rhs.latestActivity
                }
                return lhs.name < rhs.name
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func normalizedTags(_ tags: [String]) -> Set<String> {
        Set(
            tags.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                    .lowercased()
            }
            .filter { !$0.isEmpty }
        )
    }
}
