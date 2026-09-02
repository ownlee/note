import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension ContentView {
    var contextualNavigationMenu: some View {
        Menu {
            Button {
                selectScope(.archive)
            } label: {
                Label("Archive (\(archivedNotes.count))", systemImage: "archivebox")
            }
            Button {
                selectScope(.trash)
            } label: {
                Label("Recently Deleted (\(trashedNotes.count))", systemImage: "trash")
            }
        } label: {
            Image(systemName: "archivebox")
        }
        .accessibilityLabel("Archive and recently deleted")
    }
    var compactSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find notes, tags, or categories", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
    var emptyCanvas: some View {
        ContentUnavailableView(
            "Your canvas is waiting",
            systemImage: "sparkles",
            description: Text("Capture a thought below. It will appear here as a card.")
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
    }
    var isSearching: Bool {
        !normalizedSearchText.isEmpty
    }
    var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    var matchingNotes: [BrainNote] {
        guard isSearching else { return [] }

        return notes.filter { note in
            note.lifecycleState != .trashed
                && (note.rawText.localizedCaseInsensitiveContains(normalizedSearchText)
                    || note.category.title.localizedCaseInsensitiveContains(normalizedSearchText)
                    || note.tags.contains { $0.localizedCaseInsensitiveContains(normalizedSearchText) })
        }
    }
    func relatedNotes(to source: BrainNote) -> [BrainNote] {
        let candidates = activeNotes.filter { $0.processingState == .complete }
        let relatedIDs = NoteConnections.rankedIDs(
            relatedTo: connectionSnapshot(for: source),
            among: candidates.map(connectionSnapshot),
            limit: 3
        )
        let notesByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        return relatedIDs.compactMap { notesByID[$0] }
    }
    func connectionSnapshot(for note: BrainNote) -> NoteConnectionSnapshot {
        NoteConnectionSnapshot(
            id: note.id,
            tags: note.tags,
            category: note.category.rawValue,
            createdAt: note.createdAt
        )
    }
    var upcomingNotes: [BrainNote] {
        activeNotes
            .filter {
                $0.category == .actionable
                    && !$0.isCompleted
                    && $0.processingState == .complete
                    && $0.eventDate != nil
                    && ($0.eventDate ?? .distantPast) >= Date()
            }
            .sorted { ($0.eventDate ?? .distantFuture) < ($1.eventDate ?? .distantFuture) }
            .prefix(3)
            .map { $0 }
    }
    var resurfacedNotes: [BrainNote] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()

        return activeNotes
            .filter {
                $0.category != .actionable
                    && $0.processingState == .complete
                    && $0.createdAt < cutoff
            }
            .prefix(3)
            .map { $0 }
    }
    var recentNotes: [BrainNote] {
        let featuredIDs = Set((upcomingNotes + resurfacedNotes).map(\.id))
        return activeNotes
            .filter { !featuredIDs.contains($0.id) }
            .prefix(6)
            .map { $0 }
    }
    var incompleteActionableNotes: [BrainNote] {
        activeNotes.filter {
            $0.category == .actionable
                && !$0.isCompleted
                && $0.processingState == .complete
        }
    }
    var overdueNotes: [BrainNote] {
        incompleteActionableNotes
            .filter { ($0.eventDate ?? .distantFuture) < Date() }
            .sorted { ($0.eventDate ?? .distantPast) < ($1.eventDate ?? .distantPast) }
    }
    var todayNotes: [BrainNote] {
        let calendar = Calendar.current
        let now = Date()

        return incompleteActionableNotes
            .filter { note in
                guard let eventDate = note.eventDate else { return false }
                return eventDate >= now && calendar.isDateInToday(eventDate)
            }
            .sorted { ($0.eventDate ?? .distantFuture) < ($1.eventDate ?? .distantFuture) }
    }
    var laterNotes: [BrainNote] {
        let startOfTomorrow = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        )

        return incompleteActionableNotes
            .filter { ($0.eventDate ?? .distantPast) >= startOfTomorrow }
            .sorted { ($0.eventDate ?? .distantFuture) < ($1.eventDate ?? .distantFuture) }
    }
    var unscheduledNotes: [BrainNote] {
        incompleteActionableNotes
            .filter { $0.eventDate == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }
    var scopePicker: some View {
        CanvasNavigationBar(
            isSearchPresented: isSearchPresented,
            isSearching: isSearching,
            selection: canvasScope,
            scheduleCount: scheduleEntries.count,
            noteCount: activeNotes.count,
            categoryCounts: categoryNoteCounts,
            onToggleSearch: toggleSearch,
            onSelect: selectScope
        )
    }
    var canvasHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            scopePicker

            if shouldShowCardGestureHint {
                cardGestureHint
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    var categoryNoteCounts: [BrainNoteCategory: Int] {
        Dictionary(grouping: activeNotes, by: \.category)
            .mapValues(\.count)
    }
    var shouldShowCardGestureHint: Bool {
        guard !didLearnCardGestures, !activeNotes.isEmpty, !isSearching else { return false }

        switch canvasScope {
        case .home, .all, .category:
            return true
        default:
            return false
        }
    }
    var cardGestureHint: some View {
        Text("Tap to edit · Swipe either way to organize")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.045), in: Capsule())
            .accessibilityLabel("Tip: Tap a note to edit. Swipe either way to organize it.")
    }
    @ViewBuilder
    var dashboard: some View {
        if !upcomingNotes.isEmpty {
            DashboardSectionHeader(
                title: "Up Next",
                subtitle: "What needs your attention soon",
                systemImage: "bolt.fill",
                tint: .orange
            )
            noteGrid(upcomingNotes)
        }

        if !recentNotes.isEmpty {
            DashboardSectionHeader(
                title: "Recent",
                subtitle: "Only the latest, not the whole archive",
                systemImage: "clock.fill",
                tint: .teal
            )
            noteGrid(recentNotes)
        }

        if !resurfacedNotes.isEmpty {
            DashboardSectionHeader(
                title: "Rediscover",
                subtitle: "Ideas worth bringing back",
                systemImage: "arrow.clockwise",
                tint: .indigo
            )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(resurfacedNotes) { note in
                        ResurfacedNoteCard(note: note)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                presentedSheet = .edit(note)
                            }
                            .accessibilityAction(named: "Edit note") {
                                presentedSheet = .edit(note)
                            }
                    }
                }
            }
            .contentMargins(.horizontal, 1, for: .scrollContent)
        }

        Button {
            selectScope(.all)
        } label: {
            Label("Browse all \(activeNotes.count) notes", systemImage: "square.grid.2x2")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
    @ViewBuilder
    var scheduleDashboard: some View {
        MonthlyScheduleCalendar(
            month: $displayedScheduleMonth,
            selectedDay: $selectedScheduleDay,
            entries: visibleScheduleEntries,
            onAdd: {
                presentedSheet = .addSchedule(selectedScheduleDay ?? displayedScheduleMonth)
            },
            onBulkEdit: {
                presentedSheet = .bulkEditSchedule(displayedScheduleMonth)
            },
            onImportImage: {
                isSchedulePhotoPickerPresented = true
            }
        )

        if visibleScheduleEntries.isEmpty {
            ContentUnavailableView(
                "Your schedule is clear",
                systemImage: "calendar.badge.checkmark",
                description: Text("Paste a monthly roster and it will organize itself here.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
        } else {
            SelectedDayAgenda(
                day: selectedScheduleDay ?? firstVisibleScheduleDay,
                entries: visibleScheduleEntries,
                onEdit: { entry in
                    presentedSheet = .editSchedule(entry)
                },
                onDelete: { entry in
                    deleteSchedule(entry)
                }
            )
        }
    }
    @ViewBuilder
    func scheduleSection(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        notes: [BrainNote]
    ) -> some View {
        if !notes.isEmpty {
            DashboardSectionHeader(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                tint: tint
            )
            noteGrid(notes)
        }
    }
    @ViewBuilder
    var searchResults: some View {
        if matchingNotes.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
        } else {
            noteCollection(
                title: "\(matchingNotes.count) Result\(matchingNotes.count == 1 ? "" : "s")",
                notes: matchingNotes
            )
        }
    }
    @ViewBuilder
    func noteCollection(
        title: String,
        notes: [BrainNote],
        subtitle: String? = nil,
        emptyTitle: String = "Nothing here yet",
        emptyDescription: String = "New notes in this category will appear here automatically.",
        systemImage: String = "square.grid.2x2.fill",
        tint: Color = .accentColor
    ) -> some View {
        if notes.isEmpty {
            ContentUnavailableView(
                emptyTitle,
                systemImage: "tray",
                description: Text(emptyDescription)
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
        } else {
            DashboardSectionHeader(
                title: title,
                subtitle: subtitle ?? "\(notes.count) note\(notes.count == 1 ? "" : "s")",
                systemImage: systemImage,
                tint: tint
            )
            noteGrid(notes)
        }
    }
    func noteGrid(_ notes: [BrainNote]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(notes) { note in
                SwipeActionCard(
                    leadingAction: destructiveSwipeAction(for: note),
                    trailingAction: secondarySwipeAction(for: note)
                ) {
                    noteCard(note)
                }
            }
        }
    }
    func destructiveSwipeAction(for note: BrainNote) -> CardSwipeAction {
        CardSwipeAction(
            title: note.lifecycleState == .trashed ? "Delete Forever" : "Delete",
            systemImage: note.lifecycleState == .trashed ? "trash.slash.fill" : "trash.fill",
            tint: .red
        ) {
            didLearnCardGestures = true
            if note.lifecycleState == .trashed {
                notePendingPermanentDeletion = note
            } else {
                moveToTrash(note)
            }
        }
    }
    func secondarySwipeAction(for note: BrainNote) -> CardSwipeAction {
        switch note.lifecycleState {
        case .active:
            CardSwipeAction(
                title: "Archive",
                systemImage: "archivebox.fill",
                tint: .indigo
            ) {
                didLearnCardGestures = true
                archive(note)
            }

        case .archived:
            CardSwipeAction(
                title: "Restore",
                systemImage: "arrow.uturn.backward.circle.fill",
                tint: .green
            ) {
                didLearnCardGestures = true
                unarchive(note)
            }

        case .trashed:
            CardSwipeAction(
                title: "Restore",
                systemImage: "arrow.uturn.backward.circle.fill",
                tint: .green
            ) {
                didLearnCardGestures = true
                restoreFromTrash(note)
            }
        }
    }
    func noteCard(_ note: BrainNote) -> some View {
        NoteCardView(
            note: note,
            onToggleCompletion: {
                toggleCompletion(of: note)
            },
            onRetryProcessing: {
                startProcessing(note)
            },
            onResolveIntent: { intent in
                resolveIntent(of: note, as: intent)
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            presentedSheet = .edit(note)
        }
        .accessibilityAction(named: "Edit note") {
            presentedSheet = .edit(note)
        }
    }
    func selectScope(_ scope: CanvasScope) {
        withAnimation(.snappy) {
            searchText = ""
            isSearchPresented = false
            isSearchFieldFocused = false
            canvasScope = scope
            if scope == .schedule {
                prepareScheduleMonth()
            }
        }
    }
    func toggleSearch() {
        if isSearchPresented {
            withAnimation(.snappy) {
                searchText = ""
                isSearchPresented = false
                isSearchFieldFocused = false
            }
        } else {
            withAnimation(.snappy) {
                isSearchPresented = true
            }

            Task { @MainActor in
                isSearchFieldFocused = true
            }
        }
    }
    var canvasBackground: some View {
        LinearGradient(
            colors: [
                Color.purple.opacity(0.055),
                Color.blue.opacity(0.025),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    func openRelatedNote(_ note: BrainNote) {
        presentedSheet = nil

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard notes.contains(where: { $0.id == note.id && $0.lifecycleState != .trashed }) else {
                return
            }
            presentedSheet = .edit(note)
        }
    }
    func focusEmptyCanvasIfNeeded() {
        guard activeNotes.isEmpty,
              canvasScope == .home,
              presentedSheet == nil else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard activeNotes.isEmpty,
                  canvasScope == .home,
                  presentedSheet == nil else { return }
            isComposerFocused = true
        }
    }
}

private struct DashboardSectionHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ResurfacedNoteCard: View {
    let note: BrainNote

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(note.category.title, systemImage: note.category.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(note.category.tint)

            Text(note.rawText)
                .font(.subheadline)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Text(note.createdAt, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 250, height: 150, alignment: .leading)
        .background(
            note.category.tint.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(note.category.tint.opacity(0.17), lineWidth: 1)
        }
    }
}
