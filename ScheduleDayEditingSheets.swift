import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum DayEditorDestination: Identifiable {
    case add(Date)
    case edit(ScheduleEntry)

    var id: String {
        switch self {
        case let .add(day): "add-\(day.timeIntervalSinceReferenceDate)"
        case let .edit(entry): "edit-\(entry.id.uuidString)"
        }
    }
}


private struct DayScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ScheduleEntry.startDate) private var allEntries: [ScheduleEntry]

    let day: Date
    @State private var editor: DayEditorDestination?

    private var entries: [ScheduleEntry] {
        allEntries.filter {
            Calendar.current.isDate($0.startDate, inSameDayAs: day)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if entries.isEmpty {
                        ContentUnavailableView(
                            "No schedule",
                            systemImage: "calendar",
                            description: Text("Add something for this day or close to keep browsing.")
                        )
                        .padding(.top, 48)
                    } else {
                        ForEach(entries) { entry in
                            Button { editor = .edit(entry) } label: {
                                HStack(alignment: .top, spacing: 13) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(entry.tint)
                                        .frame(width: 5, height: 48)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(entry.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text("\(MonthlyScheduleCalendar.timeText(entry.startDate))–\(MonthlyScheduleCalendar.timeText(entry.endDate))")
                                            .font(.system(.title3, design: .rounded, weight: .bold))
                                            .foregroundStyle(entry.tint)
                                        if let details = entry.details, !details.isEmpty {
                                            Text(details)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(entry.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { editor = .add(day) } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add schedule")
                }
            }
            .sheet(item: $editor) { destination in
                switch destination {
                case let .add(day):
                    ScheduleEditorSheet(entry: nil, initialDay: day)
                case let .edit(entry):
                    ScheduleEditorSheet(entry: entry, initialDay: entry.startDate)
                }
            }
        }
    }
}


private struct BulkCalendarDayFrameKey: PreferenceKey {
    static let defaultValue: [Date: CGRect] = [:]

    static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}


struct BulkScheduleEditSheet: View {
    private enum TaskMode: String, CaseIterable, Identifiable {
        case add
        case organize

        var id: Self { self }
        var title: String { self == .add ? "Add" : "Organize" }
        var icon: String { self == .add ? "plus.circle.fill" : "slider.horizontal.3" }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduleEntry.startDate) private var allEntries: [ScheduleEntry]
    @Query(sort: \ScheduleTimePreset.createdAt) private var presets: [ScheduleTimePreset]

    let month: Date

    @State private var selectedIDs: Set<UUID> = []
    @State private var labelColor = ScheduleLabelColor.indigo
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isDeleteConfirmationPresented = false
    @State private var selectedDays: Set<Date> = []
    @State private var colorFilter: ScheduleLabelColor?
    @State private var weekdayFilter: Int?
    @State private var scheduleSearchText = ""
    @State private var selectedPresetID: UUID?
    @State private var presetEditor: ScheduleTimePreset?
    @State private var isNewPresetEditorPresented = false
    @State private var taskMode = TaskMode.add
    @State private var actionMessage: String?
    @State private var dayFrames: [Date: CGRect] = [:]
    @State private var dragVisitedDays: Set<Date> = []
    @State private var dragSelectsDays = true

    private let calendar = Calendar.current
    private let bulkColumns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private let calendarCoordinateSpace = "bulkScheduleCalendar"

    private var entries: [ScheduleEntry] {
        allEntries.filter {
            Calendar.current.isDate($0.startDate, equalTo: month, toGranularity: .month)
        }
    }

    private var filteredEntries: [ScheduleEntry] {
        entries.filter { entry in
            let matchesDay = selectedDays.isEmpty || selectedDays.contains(calendar.startOfDay(for: entry.startDate))
            let matchesColor = colorFilter == nil || entry.labelColor == colorFilter
            let matchesWeekday = weekdayFilter == nil || calendar.component(.weekday, from: entry.startDate) == weekdayFilter
            let matchesSearch = ScheduleSearch.matches(query: scheduleSearchText, title: entry.title)
            return matchesDay && matchesColor && matchesWeekday && matchesSearch
        }
    }

    private var filteredEntryIDs: Set<UUID> {
        Set(filteredEntries.map(\.id))
    }

    private var allFilteredEntriesAreSelected: Bool {
        !filteredEntries.isEmpty && filteredEntryIDs.isSubset(of: selectedIDs)
    }

    var body: some View {
        withPresentations(navigationContent)
    }

    private var navigationContent: some View {
        NavigationStack {
            scrollContent
                .background(Color(uiColor: .systemGroupedBackground))
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Manage Schedules")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .onChange(of: taskMode) { _, newMode in
                    actionMessage = nil
                    if newMode == .add {
                        selectedIDs.removeAll()
                        scheduleSearchText = ""
                        colorFilter = nil
                        weekdayFilter = nil
                    } else {
                        selectedPresetID = nil
                    }
                }
        }
    }

    private func withPresentations(_ content: some View) -> some View {
        content
            .alert("Couldn’t update schedules", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "Unknown error")
            }
            .confirmationDialog(
                "Delete \(selectedIDs.count) schedules?",
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Delete Schedules", role: .destructive) {
                    Task { await deleteSelected() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can’t be undone.")
            }
            .sheet(isPresented: $isNewPresetEditorPresented) {
                TimePresetEditorSheet(preset: nil)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $presetEditor) { preset in
                TimePresetEditorSheet(preset: preset)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Schedule task", selection: $taskMode) {
                    ForEach(TaskMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Schedule task")

                Label(modeGuidance, systemImage: taskMode.icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                taskModeCard

                if let actionMessage {
                    Label(actionMessage, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }

                if taskMode == .organize {
                    organizeSection
                }
            }
            .padding(20)
            .padding(.bottom, 24)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        if taskMode == .organize && !selectedIDs.isEmpty {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Apply") { Task { await apply() } }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
            }
        }
    }

    @ViewBuilder
    private var taskModeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if taskMode == .add {
                favoriteTimePicker
                Divider()
            }
            bulkMonthPicker
            if taskMode == .add {
                Divider()
                addScheduleButton
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var organizeSection: some View {
        organizeFilters

        HStack {
            Text("\(filteredEntries.count) schedules")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            if !filteredEntries.isEmpty {
                Button(allFilteredEntriesAreSelected ? "Deselect all" : "Select all") {
                    toggleAllFilteredEntries()
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityHint("Applies only to the schedules currently shown")
            }
        }

        if !selectedIDs.isEmpty {
            Text("\(selectedIDs.count) selected")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)
        }

        organizeEntryList

        if !selectedIDs.isEmpty {
            selectedScheduleActions
        }
    }

    @ViewBuilder
    private var organizeEntryList: some View {
        VStack(spacing: 8) {
            if filteredEntries.isEmpty {
                Text("No schedules match these dates and filters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                ForEach(filteredEntries) { entry in
                    Button {
                        toggle(entry.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIDs.contains(entry.id) ? Color.indigo : Color.secondary)
                            Circle().fill(entry.tint).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title).foregroundStyle(.primary)
                                Text(entry.startDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func toggleAllFilteredEntries() {
        selectedIDs = ScheduleSearch.togglingAll(
            currentSelection: selectedIDs,
            visibleIDs: filteredEntryIDs
        )
    }

    private var favoriteTimePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Favorite time")
                    .font(.headline)
                Spacer()
                Button {
                    isNewPresetEditorPresented = true
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if presets.isEmpty {
                Button("Create a favorite time") { isNewPresetEditorPresented = true }
                    .buttonStyle(.bordered)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(presets) { preset in
                            Button { selectedPresetID = preset.id } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preset.name).font(.subheadline.weight(.bold))
                                    Text(preset.timeRangeText).font(.caption2)
                                }
                                .foregroundStyle(selectedPresetID == preset.id ? Color.white : (preset.labelColor?.color ?? preset.kind.tint))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(
                                    selectedPresetID == preset.id ? (preset.labelColor?.color ?? preset.kind.tint) : (preset.labelColor?.color ?? preset.kind.tint).opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture(count: 2).onEnded { presetEditor = preset })
                        }
                    }
                }
            }
        }
    }

    private var selectedPreset: ScheduleTimePreset? {
        presets.first { $0.id == selectedPresetID }
    }

    private var modeGuidance: String {
        switch taskMode {
        case .add:
            "Choose one favorite time, then tap every date that needs it."
        case .organize:
            "Tap dates or use filters, then select the schedules you want to change."
        }
    }

    private var addScheduleButton: some View {
        Button {
            Task { await addFavoriteSchedules() }
        } label: {
            Label(
                selectedPreset == nil
                    ? "Choose a favorite time"
                    : (selectedDays.isEmpty ? "Choose dates" : "Add \(selectedDays.count) schedules"),
                systemImage: "plus"
            )
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.indigo)
        .disabled(selectedPreset == nil || selectedDays.isEmpty || isSaving)
        .accessibilityHint("Adds the selected favorite time to every selected date")
    }

    private var organizeFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find schedules")
                .font(.headline)
                .foregroundStyle(.secondary)

            TextField("Search schedule name", text: $scheduleSearchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        Button("Any weekday") { weekdayFilter = nil }
                        ForEach(1...7, id: \.self) { weekday in
                            Button(calendar.weekdaySymbols[weekday - 1]) { weekdayFilter = weekday }
                        }
                    } label: {
                        filterChip(
                            weekdayFilter.map { calendar.shortWeekdaySymbols[$0 - 1] } ?? "Weekday",
                            systemImage: "calendar"
                        )
                    }

                    Menu {
                        Button("Any color") { colorFilter = nil }
                        ForEach(ScheduleLabelColor.allCases, id: \.self) { color in
                            Button(color.title) { colorFilter = color }
                        }
                    } label: {
                        filterChip(colorFilter?.title ?? "Label", systemImage: "paintpalette")
                    }

                    if weekdayFilter != nil || colorFilter != nil || !scheduleSearchText.isEmpty {
                        Button("Clear filters") {
                            weekdayFilter = nil
                            colorFilter = nil
                            scheduleSearchText = ""
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    private func filterChip(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.07), in: Capsule())
    }

    private var selectedScheduleActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Change \(selectedIDs.count) selected")
                .font(.headline)

            ScheduleLabelColorPicker(selection: $labelColor)

            Divider()

            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
            } label: {
                Label("Delete \(selectedIDs.count) schedules", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(isSaving)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var bulkMonthPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(normalizedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                if !selectedDays.isEmpty {
                    Button("Clear dates") { selectedDays.removeAll() }
                        .font(.caption.weight(.semibold))
                }
            }

            LazyVGrid(columns: bulkColumns, spacing: 6) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(monthCells) { cell in
                    if let day = cell.date {
                        bulkDayCell(day)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
            .coordinateSpace(name: calendarCoordinateSpace)
            .onPreferenceChange(BulkCalendarDayFrameKey.self) { dayFrames = $0 }
            .highPriorityGesture(dayRangeSelectionGesture)

            if taskMode == .add {
                Label("Hold a date, then slide across the calendar to select many.", systemImage: "hand.draw")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bulkDayCell(_ day: Date) -> some View {
        let normalized = calendar.startOfDay(for: day)
        let dayEntries = entries.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
        let isSelected = selectedDays.contains(normalized)
        return Button {
            if isSelected { selectedDays.remove(normalized) } else { selectedDays.insert(normalized) }
        } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.day()))
                    .font(.caption.weight(.bold))
                if let first = dayEntries.first {
                    Text(MonthlyScheduleCalendar.timeText(first.startDate))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    if dayEntries.count > 1 {
                        Text("+\(dayEntries.count - 1)")
                            .font(.system(size: 8, weight: .bold))
                    }
                } else {
                    Color.clear.frame(height: 11)
                }
            }
            .foregroundStyle(isSelected ? Color.white : (dayEntries.isEmpty ? Color.secondary : Color.primary))
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(isSelected ? Color.indigo : Color.primary.opacity(dayEntries.isEmpty ? 0.03 : 0.08), in: RoundedRectangle(cornerRadius: 10))
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: BulkCalendarDayFrameKey.self,
                        value: [normalized: proxy.frame(in: .named(calendarCoordinateSpace))]
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.month(.wide).day()))
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to toggle. Hold, then slide to select several dates.")
    }

    private var dayRangeSelectionGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.25, maximumDistance: 18)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(calendarCoordinateSpace)))
            .onChanged { value in
                guard case let .second(true, drag?) = value else { return }

                if dragVisitedDays.isEmpty, let startDay = day(at: drag.startLocation) {
                    dragSelectsDays = !selectedDays.contains(startDay)
                    applyDragSelection(to: startDay)
                }

                if let currentDay = day(at: drag.location) {
                    applyDragSelection(to: currentDay)
                }
            }
            .onEnded { _ in
                dragVisitedDays.removeAll()
            }
    }

    private func day(at point: CGPoint) -> Date? {
        dayFrames.first(where: { $0.value.contains(point) })?.key
    }

    private func applyDragSelection(to day: Date) {
        guard !dragVisitedDays.contains(day) else { return }
        dragVisitedDays.insert(day)
        if dragSelectsDays {
            selectedDays.insert(day)
        } else {
            selectedDays.remove(day)
        }
    }

    private var normalizedMonth: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
    }

    private var monthCells: [MonthCell] {
        guard let range = calendar.range(of: .day, in: .month, for: normalizedMonth) else { return [] }
        let leading = (calendar.component(.weekday, from: normalizedMonth) + 5) % 7
        var cells = (0..<leading).map { MonthCell(id: $0, date: nil) }
        cells += range.enumerated().compactMap { offset, day in
            calendar.date(bySetting: .day, value: day, of: normalizedMonth).map {
                MonthCell(id: leading + offset, date: $0)
            }
        }
        return cells
    }

    private func selectWeekdaysWithSchedules() {
        selectedDays = Set(entries.filter {
            let weekday = calendar.component(.weekday, from: $0.startDate)
            return weekday != 1 && weekday != 7
        }.map { calendar.startOfDay(for: $0.startDate) })
    }

    private struct MonthCell: Identifiable {
        let id: Int
        let date: Date?
    }

    @MainActor
    private func addFavoriteSchedules() async {
        guard let preset = selectedPreset else { return }
        isSaving = true
        defer { isSaving = false }

        let seriesID = UUID()
        let newEntries = selectedDays.sorted().compactMap { day -> ScheduleEntry? in
            guard let interval = preset.interval(on: day) else { return nil }
            let exists = entries.contains {
                $0.startDate == interval.start && $0.endDate == interval.end
            }
            guard !exists else { return nil }
            return ScheduleEntry(
                title: preset.name,
                startDate: interval.start,
                endDate: interval.end,
                kind: preset.kind,
                seriesID: seriesID,
                labelColor: preset.labelColor ?? preset.kind.defaultLabelColor
            )
        }

        guard !newEntries.isEmpty else {
            saveError = "Those favorite times are already on the selected dates."
            return
        }

        modelContext.insert(
            ScheduleCollection(
                id: seriesID,
                title: preset.name,
                month: normalizedMonth,
                kind: preset.kind
            )
        )
        newEntries.forEach(modelContext.insert)

        do {
            try modelContext.save()
            actionMessage = "Added \(newEntries.count) schedules"
            selectedDays.removeAll()
            selectedPresetID = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    @MainActor
    private func deleteSelected() async {
        isSaving = true
        let selected = entries.filter { selectedIDs.contains($0.id) }

        selected.forEach(modelContext.delete)
        do {
            try modelContext.save()
            selectedIDs.removeAll()
            actionMessage = "Deleted \(selected.count) schedules"
            isSaving = false
        } catch {
            saveError = error.localizedDescription
            isSaving = false
        }
    }

    @MainActor
    private func apply() async {
        isSaving = true
        let selected = entries.filter { selectedIDs.contains($0.id) }
        selected.forEach { $0.labelColor = labelColor }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
            isSaving = false
        }
    }
}


struct ScheduleLabelColorPicker: View {
    @Binding var selection: ScheduleLabelColor

    var body: some View {
        HStack {
            Text("Label color")
            Spacer()
            HStack(spacing: 10) {
                ForEach(ScheduleLabelColor.allCases, id: \.self) { option in
                    Button { selection = option } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 24, height: 24)
                            .overlay {
                                if selection == option {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
        }
    }
}
