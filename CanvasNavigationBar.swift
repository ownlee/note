import SwiftUI

struct CanvasNavigationBar: View {
    let isSearchPresented: Bool
    let isSearching: Bool
    let selection: CanvasScope
    let scheduleCount: Int
    let noteCount: Int
    let categoryCounts: [BrainNoteCategory: Int]
    let onToggleSearch: () -> Void
    let onSelect: (CanvasScope) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                searchButton

                CanvasScopeChip(
                    title: "For You",
                    systemImage: "sparkles",
                    isSelected: selection == .home && !isSearching
                ) {
                    onSelect(.home)
                }

                CanvasScopeChip(
                    title: "Schedule",
                    systemImage: "calendar.badge.clock",
                    count: scheduleCount,
                    tint: .orange,
                    isSelected: selection == .schedule && !isSearching
                ) {
                    onSelect(.schedule)
                }

                browseMenu
            }
        }
        .contentMargins(.horizontal, 1, for: .scrollContent)
    }

    private var searchButton: some View {
        Button(action: onToggleSearch) {
            Image(systemName: isSearchPresented ? "xmark" : "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSearchPresented ? .white : .secondary)
                .frame(width: 42, height: 42)
                .background(
                    isSearchPresented ? Color.indigo : Color.primary.opacity(0.055),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSearchPresented ? "Close search" : "Search notes")
    }

    private var browseMenu: some View {
        Menu {
            Button {
                onSelect(.all)
            } label: {
                Label("All Notes (\(noteCount))", systemImage: "square.grid.2x2")
            }

            Divider()

            ForEach(BrainNoteCategory.allCases) { category in
                Button {
                    onSelect(.category(category))
                } label: {
                    Label(
                        "\(category.title) (\(categoryCounts[category, default: 0]))",
                        systemImage: category.symbolName
                    )
                }
            }
        } label: {
            Image(systemName: browseMenuSymbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isBrowseScope ? browseMenuTint : Color.secondary)
                .frame(width: 42, height: 42)
                .background(
                    isBrowseScope ? browseMenuTint.opacity(0.14) : Color.primary.opacity(0.055),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(
                            isBrowseScope ? browseMenuTint.opacity(0.22) : Color.primary.opacity(0.08),
                            lineWidth: 1
                        )
                }
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel("Browse notes")
        .accessibilityValue(browseMenuAccessibilityValue)
    }

    private var isBrowseScope: Bool {
        switch selection {
        case .all, .category: return true
        default: return false
        }
    }

    private var browseMenuSymbol: String {
        switch selection {
        case let .category(category): category.symbolName
        default: "square.grid.2x2"
        }
    }

    private var browseMenuTint: Color {
        switch selection {
        case let .category(category): category.tint
        default: .indigo
        }
    }

    private var browseMenuAccessibilityValue: String {
        switch selection {
        case .all: "All notes selected"
        case let .category(category): "\(category.title) selected"
        default: "Not selected"
        }
    }
}

private struct CanvasScopeChip: View {
    let title: String
    let systemImage: String
    var count: Int?
    var tint = Color.indigo
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)

                if let count {
                    Text(count, format: .number)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            (isSelected ? Color.white : tint).opacity(0.16),
                            in: Capsule()
                        )
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isSelected ? tint : Color.primary.opacity(0.06), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(isSelected ? 0 : 0.15), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\(title), \($0) items" } ?? title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
