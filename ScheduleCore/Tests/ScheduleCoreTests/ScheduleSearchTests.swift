import Foundation
import Testing
@testable import ScheduleCore

@Suite("Schedule search and bulk selection")
struct ScheduleSearchTests {
    @Test("A schedule title matches")
    func titleSearch() {
        #expect(ScheduleSearch.matches(query: "open", title: "Weekday Open"))
    }

    @Test("A non-matching query returns false")
    func nonMatchingSearch() {
        #expect(!ScheduleSearch.matches(query: "close", title: "Weekday Open"))
    }

    @Test("An empty query matches everything")
    func emptyQueryMatchesAll() {
        #expect(ScheduleSearch.matches(query: "", title: "Anything"))
    }

    @Test("Select all affects only visible filtered schedules")
    func selectAllVisibleOnly() {
        let hidden = UUID()
        let visible = Set([UUID(), UUID()])
        let selected = ScheduleSearch.togglingAll(
            currentSelection: [hidden],
            visibleIDs: visible
        )

        #expect(selected == visible.union([hidden]))
        #expect(
            ScheduleSearch.togglingAll(
                currentSelection: selected,
                visibleIDs: visible
            ) == [hidden]
        )
    }
}
