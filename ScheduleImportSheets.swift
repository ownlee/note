import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ScheduleImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduleEntry.startDate) private var existingEntries: [ScheduleEntry]

    let draft: ScheduleImportDraft
    let noteProcessor: NoteProcessor

    @State private var title: String
    @State private var kind: ScheduleKind
    @State private var confidence: Double?
    @State private var isAnalyzing = true
    @State private var hasAnalyzed = false
    @State private var userConfirmedKind = false
    @State private var includeOverlaps = true
    @State private var isSaving = false
    @State private var saveError: String?

    init(draft: ScheduleImportDraft, noteProcessor: NoteProcessor) {
        self.draft = draft
        self.noteProcessor = noteProcessor
        _title = State(initialValue: draft.schedule.title)
        _kind = State(initialValue: draft.schedule.kind)
        _confidence = State(
            initialValue: draft.suggestedConfidence
                ?? (draft.schedule.kind == .other ? nil : 0.86)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    importSummary
                    classificationCard
                    monthPreview
                    conflictControls
                    scheduleSamples
                }
                .padding(20)
                .padding(.bottom, 84)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Import Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                importButton
            }
            .alert(
                "Couldn’t import schedule",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "Unknown error")
            }
            .task {
                await analyzeScheduleContext()
            }
        }
    }

    private var importSummary: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar.badge.sparkles")
                .font(.title2)
                .foregroundStyle(.indigo)
                .frame(width: 48, height: 48)
                .background(Color.indigo.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(draft.schedule.month.formatted(.dateTime.month(.wide).year()))
                    .font(.title3.weight(.bold))
                Text("Found \(draft.schedule.shifts.count) schedules · Review before saving")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var classificationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                if isAnalyzing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: classificationIcon)
                        .foregroundStyle(needsKindConfirmation ? .orange : kind.tint)
                }

                Text(classificationMessage)
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 0)

                if !needsKindConfirmation, !isAnalyzing {
                    kindMenu
                }
            }

            if needsKindConfirmation, !isAnalyzing {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ScheduleKind.allCases, id: \.self) { option in
                            kindChip(option)
                        }
                    }
                }
            }

            TextField("Schedule name", text: $title)
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
                .padding(12)
                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke((needsKindConfirmation ? Color.orange : kind.tint).opacity(0.18))
        }
    }

    private var monthPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monthly Preview")
                .font(.headline)

            ScheduleImportMonthPreview(
                month: draft.schedule.month,
                shifts: draft.schedule.shifts,
                kind: kind,
                overlapIDs: overlapIDs,
                excludedIDs: excludedIDs
            )
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var conflictControls: some View {
        if !duplicateIDs.isEmpty || !overlapIDs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if !duplicateIDs.isEmpty {
                    Label(
                        "\(duplicateIDs.count) already saved and will be skipped",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                }

                if !overlapIDs.isEmpty {
                    Toggle(isOn: $includeOverlaps) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(
                                "Include \(overlapIDs.count) overlapping schedules",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.orange)
                            Text("Turn this off to exclude them all at once.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.orange)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(16)
            .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var scheduleSamples: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Schedule Details").font(.headline)
                Spacer()
                Text("\(selectedShifts.count) selected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(draft.schedule.shifts.prefix(5)) { shift in
                HStack(spacing: 12) {
                    Image(systemName: excludedIDs.contains(shift.id)
                        ? "minus.circle.fill"
                        : "checkmark.circle.fill")
                        .foregroundStyle(excludedIDs.contains(shift.id) ? .secondary : kind.tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(shift.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.subheadline.weight(.semibold))
                        if let details = shift.details, !details.isEmpty {
                            Text(details).font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text(timeRange(shift))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(overlapIDs.contains(shift.id) ? .orange : kind.tint)
                }
            }

            if draft.schedule.shifts.count > 5 {
                Text("+ \(draft.schedule.shifts.count - 5) more in the calendar above")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var importButton: some View {
        Button {
            Task { await saveSchedule() }
        } label: {
            HStack {
                if isSaving { ProgressView().tint(.white) }
                Label(importButtonTitle, systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.indigo)
        .disabled(selectedShifts.isEmpty || isSaving || needsKindConfirmation)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var importButtonTitle: String {
        if selectedShifts.isEmpty { return "Nothing new to import" }
        if isSaving { return "Saving…" }
        return "Add \(selectedShifts.count) schedules"
    }

    private var classificationMessage: String {
        if isAnalyzing { return "AI is identifying this schedule…" }
        if needsKindConfirmation { return "What kind of schedule is this?" }
        if userConfirmedKind { return "Saved as \(kind.title)" }
        if let confidence, confidence < 0.82 { return "This looks like \(kind.title)" }
        return "AI organized this as \(kind.title)"
    }

    private var classificationIcon: String {
        needsKindConfirmation ? "questionmark.circle.fill" : "sparkles"
    }

    private var needsKindConfirmation: Bool {
        guard !userConfirmedKind else { return false }
        return kind == .other || (confidence ?? 0) < 0.68
    }

    private var kindMenu: some View {
        Menu {
            ForEach(ScheduleKind.allCases, id: \.self) { option in
                Button {
                    chooseKind(option)
                } label: {
                    Label(option.title, systemImage: option.symbolName)
                }
            }
        } label: {
            Text("Change")
                .font(.caption.weight(.bold))
        }
    }

    private func kindChip(_ option: ScheduleKind) -> some View {
        Button {
            chooseKind(option)
        } label: {
            Label(option.title, systemImage: option.symbolName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .foregroundStyle(kind == option ? Color.white : option.tint)
                .background(kind == option ? option.tint : option.tint.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var duplicateIDs: Set<UUID> {
        Set(draft.schedule.shifts.compactMap { shift in
            existingEntries.contains {
                $0.startDate == shift.startDate && $0.endDate == shift.endDate
            } ? shift.id : nil
        })
    }

    private var overlapIDs: Set<UUID> {
        Set(draft.schedule.shifts.compactMap { shift in
            guard !duplicateIDs.contains(shift.id) else { return nil }
            return existingEntries.contains {
                shift.startDate < $0.endDate && shift.endDate > $0.startDate
            } ? shift.id : nil
        })
    }

    private var excludedIDs: Set<UUID> {
        includeOverlaps ? duplicateIDs : duplicateIDs.union(overlapIDs)
    }

    private var selectedShifts: [ParsedWorkShift] {
        draft.schedule.shifts.filter { !excludedIDs.contains($0.id) }
    }

    private func chooseKind(_ option: ScheduleKind) {
        kind = option
        title = option.title
        userConfirmedKind = true
    }

    @MainActor
    private func analyzeScheduleContext() async {
        guard !hasAnalyzed else { return }
        hasAnalyzed = true

        if draft.suggestedConfidence != nil {
            isAnalyzing = false
            return
        }

        do {
            let result = try await noteProcessor.analyzeScheduleContext(rawText: draft.rawText)
            guard !Task.isCancelled else { return }
            kind = result.kind
            title = result.title
            confidence = result.confidence
        } catch is CancellationError {
            return
        } catch {
            if draft.schedule.kind == .other {
                confidence = 0
            }
        }

        isAnalyzing = false
    }

    @MainActor
    private func saveSchedule() async {
        guard !selectedShifts.isEmpty, !needsKindConfirmation else { return }
        isSaving = true

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? kind.title : cleanTitle
        let seriesID = UUID()
        let collection = ScheduleCollection(
            id: seriesID,
            title: finalTitle,
            month: draft.schedule.month,
            kind: kind
        )
        let entries = selectedShifts.map { shift in
            ScheduleEntry(
                id: shift.id,
                title: finalTitle,
                startDate: shift.startDate,
                endDate: shift.endDate,
                kind: kind,
                details: shift.details,
                seriesID: seriesID
            )
        }

        modelContext.insert(collection)
        entries.forEach(modelContext.insert)

        do {
            try modelContext.save()
            NotificationCenter.default.post(
                name: .brainNoteScheduleImported,
                object: ScheduleImportOutcome(
                    month: draft.schedule.month,
                    firstDate: entries.first?.startDate,
                    count: entries.count
                )
            )
            dismiss()
        } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
            isSaving = false
        }
    }

    private func timeRange(_ shift: ParsedWorkShift) -> String {
        "\(MonthlyScheduleCalendar.timeText(shift.startDate))–\(MonthlyScheduleCalendar.timeText(shift.endDate))"
    }
}


private struct ScheduleImportMonthPreview: View {
    let month: Date
    let shifts: [ParsedWorkShift]
    let kind: ScheduleKind
    let overlapIDs: Set<UUID>
    let excludedIDs: Set<UUID>

    private let calendar = Calendar.current
    private let weekdaySymbols = ["M", "T", "W", "T", "F", "S", "S"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(index >= 5 ? Color.indigo : Color.secondary)
                    .frame(maxWidth: .infinity)
            }

            ForEach(monthCells) { cell in
                if let date = cell.date {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 42)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let dayShifts = shifts.filter { calendar.isDate($0.startDate, inSameDayAs: date) }
        let first = dayShifts.first
        let isOverlap = dayShifts.contains { overlapIDs.contains($0.id) }
        let isExcluded = !dayShifts.isEmpty && dayShifts.allSatisfy { excludedIDs.contains($0.id) }
        let tint: Color = isOverlap ? .orange : kind.tint

        return VStack(spacing: 2) {
            Text(date.formatted(.dateTime.day()))
                .font(.caption2.weight(.semibold))

            if let first {
                Text(MonthlyScheduleCalendar.timeText(first.startDate))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(isExcluded ? Color.secondary : tint)
                    .lineLimit(1)
                if dayShifts.count > 1 {
                    Text("+\(dayShifts.count - 1)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            } else {
                Color.clear.frame(height: 11)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .top)
        .padding(.vertical, 3)
        .background(
            first == nil ? Color.clear : tint.opacity(isExcluded ? 0.04 : 0.12),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .opacity(isExcluded ? 0.5 : 1)
    }

    private var monthCells: [MonthCell] {
        let normalized = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        guard let range = calendar.range(of: .day, in: .month, for: normalized) else { return [] }
        let leading = (calendar.component(.weekday, from: normalized) + 5) % 7
        var cells = (0..<leading).map { MonthCell(id: $0, date: nil) }
        cells += range.enumerated().compactMap { offset, day in
            calendar.date(bySetting: .day, value: day, of: normalized).map {
                MonthCell(id: leading + offset, date: $0)
            }
        }
        return cells
    }

    private struct MonthCell: Identifiable {
        let id: Int
        let date: Date?
    }
}
