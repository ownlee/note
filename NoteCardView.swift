import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
#endif

struct ClipboardSaveSheet: View {
    @Environment(\.dismiss) private var dismiss

    let text: String
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.title2)
                    .foregroundStyle(.indigo)
                    .frame(width: 44, height: 44)
                    .background(Color.indigo.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Copied something useful?")
                        .font(.headline)
                    Text("Would you like to save this copied text?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .frame(maxHeight: 150)
            .background(
                LinearGradient(
                    colors: [Color.indigo.opacity(0.09), Color.purple.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.indigo.opacity(0.14), lineWidth: 1)
            }

            HStack(spacing: 12) {
                Button("Not now", role: .cancel) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button {
                    onSave()
                    dismiss()
                } label: {
                    Label("Save", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.indigo)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .frame(maxWidth: 540)
    }
}


struct NoteCardView: View {
    let note: BrainNote
    let onToggleCompletion: () -> Void
    let onRetryProcessing: () -> Void
    let onResolveIntent: (BrainNoteIntent) -> Void

    @State private var isExpanded = false

    /// Notes shorter than this read as a single glance and get the post-it,
    /// single-line row treatment instead of the full note-style card. Tags don't
    /// disqualify a short note — the AI tags almost everything, short or not.
    private var isShortNote: Bool {
        note.rawText.count <= 24 && !note.rawText.contains("\n")
            && note.eventDate == nil
            && note.suggestedIntent == nil && note.processingState != .failed
    }

    /// The AI's paragraph-reorganized rewrite when available, split on blank lines.
    /// Falls back to single line breaks (e.g. pasted bullet-style text with no blank
    /// lines between them), then to the raw text as one block.
    private var paragraphs: [String] {
        let source = (note.formattedText?.isEmpty == false) ? note.formattedText! : note.rawText
        let byBlankLine = nonEmptyLines(source, separatedBy: "\n\n")
        if byBlankLine.count > 1 { return byBlankLine }
        let bySingleLine = nonEmptyLines(source, separatedBy: "\n")
        if bySingleLine.count > 1 { return bySingleLine }
        return byBlankLine.isEmpty ? [note.rawText] : byBlankLine
    }

    private func nonEmptyLines(_ text: String, separatedBy separator: String) -> [String] {
        text
            .components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var needsExpansion: Bool { paragraphs.count >= 3 }

    private var displayedParagraphs: [String] {
        (isExpanded || !needsExpansion) ? paragraphs : Array(paragraphs.prefix(2))
    }

    var body: some View {
        if isShortNote {
            postItRow
        } else {
            noteCard
        }
    }

    private var postItRow: some View {
        HStack(spacing: 10) {
            if note.category == .actionable, note.processingState == .complete {
                Button(action: onToggleCompletion) {
                    Image(systemName: note.isCompleted ? "checkmark.square.fill" : "square")
                        .foregroundStyle(note.isCompleted ? .green : Color.brown.opacity(0.6))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(note.isCompleted ? "Mark as incomplete" : "Mark as complete")
            } else {
                Image(systemName: note.category.symbolName)
                    .font(.subheadline)
                    .foregroundStyle(Color.brown.opacity(0.6))
            }

            Text(note.rawText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .strikethrough(note.isCompleted, color: .secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(note.createdAt, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.yellow.opacity(0.45))
                .frame(width: 36, height: 12)
                .rotationEffect(.degrees(-4))
                .offset(y: -6)
        }
        .opacity(note.isCompleted ? 0.6 : 1)
        .accessibilityElement(children: .contain)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: note.category.symbolName)
                    .font(.caption)
                    .foregroundStyle(note.category.tint)
                Text(note.category.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if note.category == .actionable,
                   note.processingState == .complete {
                    Button(action: onToggleCompletion) {
                        Image(systemName: note.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(note.isCompleted ? .green : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(note.isCompleted ? "Mark as incomplete" : "Mark as complete")
                }

                Text(note.createdAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(displayedParagraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(.body, design: .serif))
                        .lineSpacing(3)
                        .foregroundStyle(.primary)
                        .strikethrough(note.isCompleted, color: .secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if needsExpansion {
                    Button {
                        withAnimation(.snappy) { isExpanded.toggle() }
                    } label: {
                        Text(isExpanded ? "접기" : "계속 읽기")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(note.category.tint)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let eventDate = note.eventDate {
                Divider()

                Label {
                    Text(
                        eventDate,
                        format: .dateTime
                            .weekday(.abbreviated)
                            .month(.abbreviated)
                            .day()
                            .hour()
                            .minute()
                    )
                    .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                }
                .foregroundStyle(note.category.tint)
            }

            if !note.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(note.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.055), in: Capsule())
                    }
                }
            }

            intentClarification

            processingStatus
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .opacity(note.isCompleted ? 0.68 : 1)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var intentClarification: some View {
        if let suggestedIntent = note.suggestedIntent,
           suggestedIntent == .task || suggestedIntent == .event {
            Divider()

            VStack(alignment: .leading, spacing: 9) {
                Text("Task or schedule?")
                    .font(.caption.weight(.semibold))
                Text("AI isn’t certain. Choose once, or keep it as a note.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 7) {
                    Button("Task") { onResolveIntent(.task) }
                    Button("Schedule") { onResolveIntent(.event) }
                        .disabled(note.eventDate == nil)
                    Button("Keep note") { onResolveIntent(.note) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var processingStatus: some View {
        switch note.processingState {
        case .pending:
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text("Organizing your thought…")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)

        case .failed:
            Button(action: onRetryProcessing) {
                Label("Retry analysis", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)

        case .complete:
            EmptyView()
        }
    }
}


extension BrainNoteCategory {
    var title: String {
        switch self {
        case .actionable: "Actionable"
        case .reflective: "Reflective"
        case .creative: "Creative"
        case .reference: "Reference"
        }
    }

    var symbolName: String {
        switch self {
        case .actionable: "checkmark.circle.fill"
        case .reflective: "moon.stars.fill"
        case .creative: "paintbrush.pointed.fill"
        case .reference: "bookmark.fill"
        }
    }

    var tint: Color {
        switch self {
        case .actionable: .orange
        case .reflective: .indigo
        case .creative: .pink
        case .reference: .teal
        }
    }
}
