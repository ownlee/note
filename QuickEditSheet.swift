import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct QuickEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let note: BrainNote
    let relatedNotes: [BrainNote]
    let onSave: (BrainNoteEdits) -> Void
    let onOpenRelated: (BrainNote) -> Void

    @State private var edits: BrainNoteEdits
    @State private var tagsText: String
    @State private var didCommit = false
    @State private var isShowingShareSheet = false
    @FocusState private var focusedField: Field?

    private let categoryColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private enum Field: Hashable {
        case rawText
        case tags
    }

    init(
        note: BrainNote,
        relatedNotes: [BrainNote],
        onSave: @escaping (BrainNoteEdits) -> Void,
        onOpenRelated: @escaping (BrainNote) -> Void
    ) {
        self.note = note
        self.relatedNotes = relatedNotes
        self.onSave = onSave
        self.onOpenRelated = onOpenRelated
        _edits = State(initialValue: BrainNoteEdits(note: note))
        _tagsText = State(initialValue: note.tags.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    autosaveNotice

                    QuickEditSection(
                        title: "Thought",
                        systemImage: "text.alignleft",
                        tint: edits.category.tint
                    ) {
                        TextEditor(text: $edits.rawText)
                            .font(.body)
                            .focused($focusedField, equals: .rawText)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 120)
                            .padding(12)
                            .background(
                                edits.category.tint.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                    }

                    QuickEditSection(
                        title: "Category",
                        systemImage: "square.grid.2x2",
                        tint: edits.category.tint
                    ) {
                        LazyVGrid(columns: categoryColumns, spacing: 10) {
                            ForEach(BrainNoteCategory.allCases) { category in
                                categoryButton(category)
                            }
                        }
                    }

                    if edits.category == .actionable {
                        QuickEditSection(
                            title: "Schedule",
                            systemImage: "calendar.badge.clock",
                            tint: .orange
                        ) {
                            VStack(spacing: 14) {
                                Toggle(isOn: hasEventDateBinding) {
                                    Label("Add date & time", systemImage: "calendar")
                                }
                                .tint(.orange)

                                if edits.eventDate != nil {
                                    Divider()

                                    DatePicker(
                                        "When",
                                        selection: eventDateBinding,
                                        displayedComponents: [.date, .hourAndMinute]
                                    )
                                    .datePickerStyle(.compact)
                                }

                                Divider()

                                Toggle(isOn: $edits.isCompleted) {
                                    Label("Completed", systemImage: "checkmark.circle")
                                }
                                .tint(.green)
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    QuickEditSection(
                        title: "Tags",
                        systemImage: "tag",
                        tint: edits.category.tint
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("work, proposal, reading", text: $tagsText)
                                .textFieldStyle(.plain)
                                .focused($focusedField, equals: .tags)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    Color.primary.opacity(0.055),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )

                            if !parsedTags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 7) {
                                        ForEach(parsedTags, id: \.self) { tag in
                                            Text("#\(tag)")
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(edits.category.tint)
                                                .padding(.horizontal, 9)
                                                .padding(.vertical, 5)
                                                .background(
                                                    edits.category.tint.opacity(0.1),
                                                    in: Capsule()
                                                )
                                        }
                                    }
                                }
                            }

                            Text("Separate tags with commas. Up to 8 are saved.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !relatedNotes.isEmpty {
                        RelatedThoughtsSection(
                            sourceTags: parsedTags,
                            notes: relatedNotes,
                            tint: edits.category.tint
                        ) { relatedNote in
                            commitIfNeeded()
                            onOpenRelated(relatedNote)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(
                LinearGradient(
                    colors: [
                        edits.category.tint.opacity(0.055),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Quick Edit")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commitIfNeeded()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .animation(.snappy, value: edits.category)
            .onDisappear {
                commitIfNeeded()
            }
            #if canImport(UIKit)
            .sheet(isPresented: $isShowingShareSheet) {
                ActivityView(activityItems: [shareText])
                    .presentationDetents([.medium, .large])
            }
            #endif
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        #if canImport(UIKit)
        Button {
            focusedField = nil
            isShowingShareSheet = true
        } label: {
            shareIcon
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share note")
        #else
        ShareLink(
            item: shareText,
            subject: Text("BrainNote")
        ) {
            shareIcon
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share note")
        #endif
    }

    private var shareIcon: some View {
        Image(systemName: "square.and.arrow.up")
            .foregroundStyle(.primary)
            .frame(width: 38, height: 38)
            .background(Color.indigo.opacity(0.14), in: Circle())
    }

    private var autosaveNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Make a quick correction")
                    .font(.subheadline.weight(.semibold))
                Text("Changes save automatically when you close.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            shareButton
                .layoutPriority(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func categoryButton(_ category: BrainNoteCategory) -> some View {
        let isSelected = edits.category == category

        return Button {
            edits.category = category
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.symbolName)
                Text(category.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : category.tint)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                isSelected ? category.tint : category.tint.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(category.tint.opacity(isSelected ? 0 : 0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var hasEventDateBinding: Binding<Bool> {
        Binding(
            get: { edits.eventDate != nil },
            set: { shouldHaveDate in
                edits.eventDate = shouldHaveDate
                    ? edits.eventDate ?? defaultEventDate
                    : nil
            }
        )
    }

    private var eventDateBinding: Binding<Date> {
        Binding(
            get: { edits.eventDate ?? defaultEventDate },
            set: { edits.eventDate = $0 }
        )
    }

    private var defaultEventDate: Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return Calendar.current.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: tomorrow
        ) ?? tomorrow
    }

    private var parsedTags: [String] {
        tagsText
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map(String.init)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            }
            .filter { !$0.isEmpty }
            .prefix(8)
            .map { $0 }
    }

    private var shareText: String {
        var sections = [edits.rawText.trimmingCharacters(in: .whitespacesAndNewlines)]

        if edits.category == .actionable {
            if edits.isCompleted {
                sections.append("✓ Completed")
            }

            if let eventDate = edits.eventDate {
                sections.append(
                    eventDate.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
            }
        }

        if !parsedTags.isEmpty {
            sections.append(parsedTags.map { "#\($0)" }.joined(separator: " "))
        }

        return sections
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private func commitIfNeeded() {
        guard !didCommit else { return }
        edits.tags = parsedTags
        didCommit = true
        onSave(edits)
    }
}


private struct QuickEditSection<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)

            content
        }
        .padding(16)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.075), lineWidth: 1)
        }
    }
}

