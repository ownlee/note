import Foundation
import Testing
@testable import ScheduleCore

@Suite("Schedule search and bulk selection")
struct ScheduleSearchTests {
    @Test("A schedule title matches without team mode")
    func titleSearch() {
        #expect(
            ScheduleSearch.matches(
                query: "open",
                title: "Weekday Open",
                assigneeNames: [],
                includesAssignees: false
            )
        )
    }

    @Test("A team member name matches the same search field")
    func teamMemberSearch() {
        #expect(
            ScheduleSearch.matches(
                query: "지원",
                title: "마감",
                assigneeNames: ["민교", "지원"],
                includesAssignees: true
            )
        )
    }

    @Test("Personal mode does not expose assignee matching")
    func personalSearchPrivacy() {
        #expect(
            !ScheduleSearch.matches(
                query: "지원",
                title: "개인 운동",
                assigneeNames: ["지원"],
                includesAssignees: false
            )
        )
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
