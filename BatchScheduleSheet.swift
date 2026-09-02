import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct BatchScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduleTimePreset.createdAt) private var presets: [ScheduleTimePreset]
    @Query(sort: \ScheduleEntry.startDate) private var existingEntries: [ScheduleEntry]

    let month: Date

    @State private var selectedPresetID: UUID?
    @State private var selectedDays: Set<Date> = []
    @State private var presetEditor: ScheduleTimePreset?
    @State private var isNewPresetEditorPresented = false
    @State private var isSaving = false
    @State private var saveError: String?

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private let weekdaySymbols = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        withPresentations(navigationContent)
    }

    private var navigationContent: some View {
        NavigationStack {
            scrollContent
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("Add Favorite Times")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { cancelToolbar }
                .safeAreaInset(edge: .bottom) { saveButton }
        }
    }

    private func withPresentations(_ content: some View) -> some View {
        content
            .sheet(isPresented: $isNewPresetEditorPresented) {
                TimePresetEditorSheet(preset: nil)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $presetEditor) { preset in
                TimePresetEditorSheet(preset: preset)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert(
                "Schedules could not be added",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "Unknown error")
            }
            .onAppear {
                selectedPresetID = selectedPresetID ?? presets.first?.id
            }
            .onChange(of: presets.map(\.id)) { _, ids in
                if selectedPresetID == nil { selectedPresetID = ids.first }
            }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                destinationHeader
                presetPicker
                datePicker
            }
            .padding(20)
            .padding(.bottom, 82)
        }
    }

    @ToolbarContentBuilder
    private var cancelToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .disabled(isSaving)
        }
    }

    private var destinationHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.fill")
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
                .background(Color.blue.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Personal calendar")
                    .font(.subheadline.weight(.semibold))
                Text("Pick one time, then tap every date you need.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                Button {
                    isNewPresetEditorPresented = true
                } label: {
                    Label("Create Open, Middle, or Close", systemImage: "star")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(presets) { preset in
                            Button {
                                selectedPresetID = preset.id
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preset.name).font(.subheadline.weight(.bold))
                                    Text(preset.timeRangeText).font(.caption2)
                                }
                                .foregroundStyle(selectedPresetID == preset.id ? Color.white : (preset.labelColor?.color ?? preset.kind.tint))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    selectedPresetID == preset.id ? (preset.labelColor?.color ?? preset.kind.tint) : (preset.labelColor?.color ?? preset.kind.tint).opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    presetEditor = preset
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(normalizedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button("Weekdays") { selectWeekdays() }
                    .font(.caption.weight(.semibold))
                if !selectedDays.isEmpty {
                    Button("Clear") { selectedDays.removeAll() }
                        .font(.caption.weight(.semibold))
                }
            }

            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(index >= 5 ? Color.indigo : Color.secondary)
                }

                ForEach(monthCells) { cell in
                    if let day = cell.date {
                        let normalized = calendar.startOfDay(for: day)
                        Button {
                            if selectedDays.contains(normalized) {
                                selectedDays.remove(normalized)
                            } else {
                                selectedDays.insert(normalized)
                            }
                        } label: {
                            Text(day.formatted(.dateTime.day()))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selectedDays.contains(normalized) ? Color.white : Color.primary)
                                .frame(maxWidth: .infinity, minHeight: 42)
                                .background(
                                    selectedDays.contains(normalized) ? Color.indigo : Color.primary.opacity(0.055),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack {
                if isSaving { ProgressView().tint(.white) }
                Text(isSaving ? "Adding…" : "Add \(selectedDays.count) schedules")
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Color.indigo, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
        .disabled(selectedPreset == nil || selectedDays.isEmpty || isSaving)
        .opacity(selectedPreset == nil || selectedDays.isEmpty ? 0.45 : 1)
    }

    private var selectedPreset: ScheduleTimePreset? {
        presets.first { $0.id == selectedPresetID }
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

    private struct MonthCell: Identifiable {
        let id: Int
        let date: Date?
    }

    private func selectWeekdays() {
        selectedDays = Set(monthCells.compactMap(\.date).filter {
            let weekday = calendar.component(.weekday, from: $0)
            return weekday != 1 && weekday != 7
        }.map { calendar.startOfDay(for: $0) })
    }

    @MainActor
    private func save() async {
        guard let preset = selectedPreset else { return }
        isSaving = true
        let seriesID = UUID()
        let candidates = selectedDays.sorted().compactMap { day -> ScheduleEntry? in
            guard let interval = preset.interval(on: day) else { return nil }
            let duplicate = existingEntries.contains {
                $0.startDate == interval.start && $0.endDate == interval.end
            }
            guard !duplicate else { return nil }
            return ScheduleEntry(
                title: preset.name,
                startDate: interval.start,
                endDate: interval.end,
                kind: preset.kind,
                seriesID: seriesID,
                labelColor: preset.labelColor ?? preset.kind.defaultLabelColor
            )
        }
        guard !candidates.isEmpty else {
            saveError = "Those dates already have this favorite time."
            isSaving = false
            return
        }

        let collection = ScheduleCollection(
            id: seriesID,
            title: preset.name,
            month: normalizedMonth,
            kind: preset.kind
        )
        modelContext.insert(collection)
        candidates.forEach(modelContext.insert)

        do {
            try modelContext.save()
            NotificationCenter.default.post(
                name: .brainNoteScheduleImported,
                object: ScheduleImportOutcome(
                    month: normalizedMonth,
                    firstDate: candidates.first?.startDate,
                    count: candidates.count
                )
            )
            dismiss()
        } catch {
            modelContext.rollback()
            isSaving = false
            saveError = error.localizedDescription
        }
    }
}


struct TimePresetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let preset: ScheduleTimePreset?
    @State private var name: String
    @State private var kind: ScheduleKind
    @State private var labelColor: ScheduleLabelColor
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var deleteConfirmationPresented = false
    @FocusState private var isNameFocused: Bool

    init(preset: ScheduleTimePreset?) {
        self.preset = preset
        let calendar = Calendar.current
        let startMinutes = preset?.startMinutes ?? 9 * 60
        let endMinutes = preset?.endMinutes ?? 18 * 60
        _name = State(initialValue: preset?.name ?? "")
        _kind = State(initialValue: preset?.kind ?? .work)
        _labelColor = State(initialValue: preset?.labelColor ?? preset?.kind.defaultLabelColor ?? .indigo)
        _startTime = State(initialValue: calendar.date(byAdding: .minute, value: startMinutes, to: calendar.startOfDay(for: .now)) ?? .now)
        _endTime = State(initialValue: calendar.date(byAdding: .minute, value: endMinutes, to: calendar.startOfDay(for: .now)) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Open, Middle, Close…", text: $name)
                        .focused($isNameFocused)
                    Picker("Type", selection: $kind) {
                        ForEach(ScheduleKind.allCases, id: \.self) { option in
                            Label(option.title, systemImage: option.symbolName).tag(option)
                        }
                    }
                    ScheduleLabelColorPicker(selection: $labelColor)
                }
                Section("Time") {
                    DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: $endTime, displayedComponents: .hourAndMinute)
                    Text("If the end is earlier than the start, it will end the next day.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(preset == nil ? "New Favorite Time" : "Edit Favorite Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if preset != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Delete Favorite", role: .destructive) {
                            deleteConfirmationPresented = true
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete this favorite time?",
                isPresented: $deleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("Existing schedules stay unchanged.")
            }
            .onAppear { isNameFocused = true }
        }
    }

    private func save() {
        let start = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        let end = Calendar.current.dateComponents([.hour, .minute], from: endTime)
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let preset {
            preset.name = finalName
            preset.startMinutes = (start.hour ?? 0) * 60 + (start.minute ?? 0)
            preset.endMinutes = (end.hour ?? 0) * 60 + (end.minute ?? 0)
            preset.kind = kind
            preset.labelColor = labelColor
        } else {
            modelContext.insert(
                ScheduleTimePreset(
                    name: finalName,
                    startMinutes: (start.hour ?? 0) * 60 + (start.minute ?? 0),
                    endMinutes: (end.hour ?? 0) * 60 + (end.minute ?? 0),
                    kind: kind,
                    labelColor: labelColor
                )
            )
        }
        try? modelContext.save()
        dismiss()
    }

    private func delete() {
        guard let preset else { return }
        modelContext.delete(preset)
        try? modelContext.save()
        dismiss()
    }
}
