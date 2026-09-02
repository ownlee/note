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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label(note.category.title, systemImage: note.category.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(note.category.tint)

                Spacer(minLength: 8)

                if note.category == .actionable,
                   note.processingState == .complete {
                    Button(action: onToggleCompletion) {
                        Image(systemName: note.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(note.isCompleted ? .green : note.category.tint)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(note.isCompleted ? "Mark as incomplete" : "Mark as complete")
                }

                Text(note.createdAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(note.rawText)
                .font(.body)
                .foregroundStyle(.primary)
                .strikethrough(note.isCompleted, color: .secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(note.category.tint.opacity(0.115), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(note.category.tint.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: note.category.tint.opacity(0.12), radius: 14, y: 7)
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
