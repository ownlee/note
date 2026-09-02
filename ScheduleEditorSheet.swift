import SwiftUI
import SwiftData

struct ScheduleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let entry: ScheduleEntry?

    @State private var title: String
    @State private var kind: ScheduleKind
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var details: String
    @State private var labelColor: ScheduleLabelColor
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var isDeleteConfirmationPresented = false
    @FocusState private var isTitleFocused: Bool

    init(entry: ScheduleEntry?, initialDay: Date) {
        self.entry = entry

        let calendar = Calendar.current
        let defaultStart = calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: initialDay
        ) ?? initialDay
        let start = entry?.startDate ?? defaultStart

        _title = State(initialValue: entry?.title ?? "")
        _kind = State(initialValue: entry?.kind ?? .personal)
        _startDate = State(initialValue: start)
        _endDate = State(
            initialValue: entry?.endDate ?? calendar.date(byAdding: .hour, value: 1, to: start) ?? start
        )
        _details = State(initialValue: entry?.details ?? "")
        _labelColor = State(initialValue: entry?.labelColor ?? (entry?.kind ?? .personal).defaultLabelColor)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Schedule") {
                    TextField("Title, e.g. Work or Gym", text: $title)
                        .focused($isTitleFocused)

                    Picker("Type", selection: $kind) {
                        ForEach(ScheduleKind.allCases, id: \.self) { kind in
                            Label(kind.title, systemImage: kind.symbolName)
                                .tag(kind)
                        }
                    }
                }

                Section("Time") {
                    DatePicker(
                        "Starts",
                        selection: $startDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    DatePicker(
                        "Ends",
                        selection: $endDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Details") {
                    TextField("Optional notes", text: $details, axis: .vertical)
                        .lineLimit(2...4)
                    ScheduleLabelColorPicker(selection: $labelColor)
                }

                if entry != nil {
                    Section {
                        Button("Delete Schedule", role: .destructive) {
                            isDeleteConfirmationPresented = true
                        }
                    } footer: {
                        Text("This removes the schedule from this calendar.")
                    }
                }
            }
            .navigationTitle(entry == nil ? "Add Schedule" : "Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                        .fontWeight(.semibold)
                        .disabled(endDate <= startDate || isSaving)
                }
            }
            .alert(
                "Schedule could not be saved",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "Unknown error")
            }
            .confirmationDialog(
                "Delete this schedule?",
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Delete Schedule", role: .destructive) {
                    Task { await deleteSchedule() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can’t be undone.")
            }
            .onAppear {
                if entry == nil { isTitleFocused = true }
            }
            .onChange(of: startDate) { oldValue, newValue in
                guard endDate <= newValue else { return }
                let duration = max(endDate.timeIntervalSince(oldValue), 60 * 60)
                endDate = newValue.addingTimeInterval(duration)
            }
        }
    }

    private var finalTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? kind.title : trimmedTitle
    }

    @MainActor
    private func deleteSchedule() async {
        guard let entry else { return }
        isSaving = true
        defer { isSaving = false }

        modelContext.delete(entry)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        let finalDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)

        if let entry {
            entry.title = finalTitle
            entry.kind = kind
            entry.startDate = startDate
            entry.endDate = endDate
            entry.details = finalDetails.isEmpty ? nil : finalDetails
            entry.labelColor = labelColor
        } else {
            let newEntry = ScheduleEntry(
                title: finalTitle,
                startDate: startDate,
                endDate: endDate,
                kind: kind,
                details: finalDetails.isEmpty ? nil : finalDetails,
                labelColor: labelColor
            )
            modelContext.insert(newEntry)
        }

        do {
            try modelContext.save()
            isSaving = false
            dismiss()
        } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
            isSaving = false
        }
    }
}
