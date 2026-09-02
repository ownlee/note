import Foundation

public enum ScheduleSearch {
    public static func matches(
        query: String,
        title: String
    ) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return true }

        return title.localizedCaseInsensitiveContains(normalizedQuery)
    }

    public static func togglingAll(
        currentSelection: Set<UUID>,
        visibleIDs: Set<UUID>
    ) -> Set<UUID> {
        guard !visibleIDs.isEmpty else { return currentSelection }

        var selection = currentSelection
        if visibleIDs.isSubset(of: selection) {
            selection.subtract(visibleIDs)
        } else {
            selection.formUnion(visibleIDs)
        }
        return selection
    }
}
