import SwiftUI

struct RelatedThoughtsSection: View {
    let sourceTags: [String]
    let notes: [BrainNote]
    let tint: Color
    let onSelect: (BrainNote) -> Void

    private var normalizedSourceTags: Set<String> {
        Set(sourceTags.map { $0.lowercased() })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(tint)
                Text("Connections")
                    .font(.headline)
                Spacer()
                Text("From AI tags")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(notes.prefix(3).enumerated()), id: \.element.id) { index, note in
                    Button {
                        onSelect(note)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(note.rawText)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 6) {
                                ForEach(sharedTags(with: note).prefix(3), id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(tint)
                                }
                                Spacer(minLength: 0)
                                Text(note.createdAt, format: .relative(presentation: .named))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open related thought: \(note.rawText)")

                    if index < min(notes.count, 3) - 1 {
                        Divider()
                            .padding(.leading, 14)
                    }
                }
            }
            .background(
                tint.opacity(0.065),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private func sharedTags(with note: BrainNote) -> [String] {
        note.tags.filter { normalizedSourceTags.contains($0.lowercased()) }
    }
}
