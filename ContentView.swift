import SwiftData
import SwiftUI
import PhotosUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Notification.Name {
    static let brainNoteScheduleImported = Notification.Name(
        "BrainNoteScheduleImported"
    )
}

struct ScheduleImportOutcome {
    let month: Date
    let firstDate: Date?
    let count: Int
    let sharingMode: ScheduleSharingMode
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \BrainNote.createdAt, order: .reverse) private var notes: [BrainNote]
    @Query(sort: \ScheduleEntry.startDate) private var scheduleEntries: [ScheduleEntry]
    @Query(sort: \ScheduleCollection.createdAt, order: .reverse)
    private var scheduleCollections: [ScheduleCollection]
    @Query(sort: \ScheduleTeamMember.name) private var teamMembers: [ScheduleTeamMember]

    @State private var draft = ""
    @State private var processingError: String?
    @State private var presentedSheet: SheetDestination?
    @State private var lastSeenClipboardText: String?
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var canvasScope = CanvasScope.home
    @State private var pendingUndo: PendingLifecycleUndo?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var composerFocusTask: Task<Void, Never>?
    @State private var notePendingPermanentDeletion: BrainNote?
    @State private var displayedScheduleMonth = Date.now
    @State private var selectedScheduleDay: Date?
    @State private var scheduleWorkspace = ScheduleSharingMode.personal
    @AppStorage("brainnote.teamCalendarEnabled") private var isTeamCalendarEnabled = false
    @AppStorage("brainnote.didLearnCardGestures") private var didLearnCardGestures = false
    @State private var scheduleImportMessage: String?
    @State private var scheduleImportDismissTask: Task<Void, Never>?
    @State private var isSchedulePhotoPickerPresented = false
    @State private var selectedSchedulePhotoItem: PhotosPickerItem?
    @State private var isReadingScheduleImage = false
    @State private var isSyncingSharedSchedules = false
    @FocusState private var isComposerFocused: Bool
    @FocusState private var isSearchFieldFocused: Bool

    private let noteProcessor = NoteProcessor(apiKey: AppSecrets.openAIAPIKey)
    private let notificationScheduler = NotificationScheduler()

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if isSearchPresented {
                        compactSearchField
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    canvasHeader

                    if isSearching {
                        searchResults
                    } else {
                        switch canvasScope {
                        case .home:
                            if activeNotes.isEmpty {
                                emptyCanvas
                            } else {
                                dashboard
                            }
                        case .all:
                            noteCollection(title: "All Notes", notes: activeNotes)
                        case .schedule:
                            scheduleDashboard
                        case let .category(category):
                            noteCollection(
                                title: category.title,
                                notes: activeNotes.filter { $0.category == category }
                            )
                        case .archive:
                            noteCollection(
                                title: "Archive",
                                notes: archivedNotes,
                                subtitle: "Swipe left to return a note to your canvas",
                                emptyTitle: "Archive is empty",
                                emptyDescription: "Swipe a card left to quietly move it out of your daily canvas.",
                                systemImage: "archivebox.fill",
                                tint: .indigo
                            )
                        case .trash:
                            noteCollection(
                                title: "Recently Deleted",
                                notes: trashedNotes,
                                subtitle: "Swipe left to restore · Deleted after 30 days",
                                emptyTitle: "Recently Deleted is empty",
                                emptyDescription: "Deleted notes stay recoverable here for 30 days.",
                                systemImage: "trash.fill",
                                tint: .red
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .frame(maxWidth: 1_200)
                .frame(maxWidth: .infinity)
            }
            .background(canvasBackground)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }
            .overlay(alignment: .bottom) {
                if isReadingScheduleImage {
                    StatusToast(
                        message: "Reading schedule image…",
                        systemImage: "photo.badge.magnifyingglass",
                        tint: .indigo
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 94)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let pendingUndo {
                    UndoToast(message: pendingUndo.message) {
                        undoLifecycleChange()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 94)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let scheduleImportMessage {
                    StatusToast(
                        message: scheduleImportMessage,
                        systemImage: "calendar.badge.checkmark",
                        tint: .green
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 94)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: pendingUndo?.id)
            .animation(.snappy, value: scheduleImportMessage)
            .animation(.snappy, value: isReadingScheduleImage)
            .animation(.snappy, value: isSearchPresented)
            .animation(.snappy, value: didLearnCardGestures)
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    contextualNavigationMenu
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    contextualNavigationMenu
                }
                #endif
            }
            .alert(
                "Something went wrong",
                isPresented: processingErrorBinding
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(processingError ?? "Unknown error")
            }
            .sheet(item: $presentedSheet) { destination in
                switch destination {
                case let .clipboard(text):
                    ClipboardSaveSheet(text: text) {
                        saveClipboardText(text)
                    }
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)

                case let .edit(note):
                    QuickEditSheet(
                        note: note,
                        relatedNotes: relatedNotes(to: note),
                        onSave: { edits in
                            saveEdits(edits, to: note)
                        },
                        onOpenRelated: openRelatedNote
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)

                case let .addSchedule(day, sharingMode):
                    ScheduleEditorSheet(
                        entry: nil,
                        initialDay: day,
                        initialSharingMode: sharingMode
                    )
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)

                case let .editSchedule(entry):
                    ScheduleEditorSheet(
                        entry: entry,
                        initialDay: entry.startDate,
                        initialSharingMode: entry.resolvedSharingMode
                    )
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)

                case let .importSchedule(draft, sharingMode):
                    ScheduleImportPreviewSheet(
                        draft: draft,
                        noteProcessor: noteProcessor,
                        sharingMode: sharingMode
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)

                #if canImport(UIKit)
                case let .manageTeamShare(prepared):
                    CloudSharingController(
                        preparedShare: prepared,
                        title: "Team Calendar",
                        onError: { processingError = $0.localizedDescription }
                    )
                #endif

                case let .batchSchedule(month, sharingMode):
                    BatchScheduleSheet(month: month, sharingMode: sharingMode)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)

                case let .bulkEditSchedule(month, sharingMode):
                    BulkScheduleEditSheet(month: month, sharingMode: sharingMode)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
            }
            .photosPicker(
                isPresented: $isSchedulePhotoPickerPresented,
                selection: $selectedSchedulePhotoItem,
                matching: .images
            )
            .confirmationDialog(
                "Delete this note permanently?",
                isPresented: Binding(
                    get: { notePendingPermanentDeletion != nil },
                    set: { if !$0 { notePendingPermanentDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Permanently", role: .destructive) {
                    if let note = notePendingPermanentDeletion {
                        permanentlyDelete(note)
                    }
                    notePendingPermanentDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    notePendingPermanentDeletion = nil
                }
            } message: {
                Text("This cannot be undone.")
            }
            .onChange(of: scenePhase, initial: true) { _, newPhase in
                guard newPhase == .active else { return }
                purgeExpiredTrash()
                migrateLegacyScheduleNotesIfNeeded()
                migrateScheduleOwnershipIfNeeded()
                if !openPendingNotificationNote(),
                   !openComposerIfRequested() {
                    inspectClipboard()
                    focusEmptyCanvasIfNeeded()
                }
            }
            .onChange(of: notes.map(\.id), initial: true) { _, _ in
                openPendingNotificationNote()
            }
            .onChange(of: scheduleWidgetSignature, initial: true) { _, _ in
                refreshScheduleWidget()
            }
            .onChange(of: selectedSchedulePhotoItem) { _, item in
                guard let item else { return }
                Task { await readScheduleImage(item) }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .brainNoteReminderOpened)
            ) { notification in
                guard let noteID = notification.object as? UUID else { return }
                openNotificationNote(noteID)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .brainNoteComposerRequested)
            ) { _ in
                _ = BrainNoteIntentRouteStore.consumeComposerRequest()
                openComposer()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .brainNoteScheduleImported)
            ) { notification in
                guard let outcome = notification.object as? ScheduleImportOutcome else { return }
                displayedScheduleMonth = outcome.month
                selectedScheduleDay = outcome.firstDate
                scheduleWorkspace = outcome.sharingMode
                canvasScope = .schedule
                presentScheduleImportConfirmation(
                    "\(outcome.count) schedules added · \(outcome.month.formatted(.dateTime.month(.wide).year()))"
                )
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .brainNoteSharedScheduleAccepted)
            ) { notification in
                if let error = notification.object as? Error {
                    processingError = error.localizedDescription
                } else {
                    Task { await syncSharedSchedules(silently: false) }
                }
            }
            .task {
                await syncSharedSchedules(silently: true)
            }
            .onOpenURL(perform: handleOpenURL)
            .onDisappear {
                undoDismissTask?.cancel()
                composerFocusTask?.cancel()
                scheduleImportDismissTask?.cancel()
            }
        }
    }

    private func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "brainnote" else { return }

        switch url.host?.lowercased() {
        case "capture":
            openComposer()
        case "schedule":
            openSchedule()
            if url.pathComponents.contains("team") {
                scheduleWorkspace = .team
            }
            if url.pathComponents.contains("favorites") {
                presentedSheet = .batchSchedule(displayedScheduleMonth, scheduleWorkspace)
            } else if url.pathComponents.contains("add") {
                presentedSheet = .addSchedule(Date.now, scheduleWorkspace)
            }
        default:
            break
        }
    }

    @MainActor
    private func syncSharedSchedules(silently: Bool) async {
        guard !isSyncingSharedSchedules else { return }
        isSyncingSharedSchedules = true
        defer { isSyncingSharedSchedules = false }

        do {
            let payloads = try await ScheduleSharingService.shared.fetchSharedSchedules()
            var insertedCount = 0

            for payload in payloads {
                let collection: ScheduleCollection
                if let existing = scheduleCollections.first(where: { $0.id == payload.collection.id }) {
                    collection = existing
                    collection.title = payload.collection.title
                    collection.month = payload.collection.month
                    collection.kind = payload.collection.kind
                } else {
                    collection = ScheduleCollection(
                        id: payload.collection.id,
                        title: payload.collection.title,
                        month: payload.collection.month,
                        kind: payload.collection.kind,
                        sharingMode: .team,
                        teamID: payload.collection.id,
                        shareState: .shared
                    )
                    modelContext.insert(collection)
                }

                collection.assignOwnership(.team)
                collection.shareState = .shared
                collection.cloudKitZoneName = payload.zoneName
                collection.cloudKitZoneOwnerName = payload.zoneOwnerName
                collection.cloudKitRootRecordName = payload.rootRecordName
                collection.cloudKitShareRecordName = payload.shareRecordName
                collection.participantCount = payload.participantCount

                for snapshot in payload.entries {
                    if let existing = scheduleEntries.first(where: { $0.id == snapshot.id }) {
                        existing.title = snapshot.title
                        existing.startDate = snapshot.startDate
                        existing.endDate = snapshot.endDate
                        existing.kind = snapshot.kind
                        existing.details = snapshot.details
                        existing.labelColor = snapshot.labelColor
                        existing.assigneeText = snapshot.assigneeText
                        existing.seriesID = snapshot.collectionID
                        existing.assignOwnership(.team, teamID: collection.teamID ?? collection.id)
                    } else {
                        modelContext.insert(
                            ScheduleEntry(
                                id: snapshot.id,
                                title: snapshot.title,
                                startDate: snapshot.startDate,
                                endDate: snapshot.endDate,
                                kind: snapshot.kind,
                                details: snapshot.details,
                                seriesID: snapshot.collectionID,
                                teamID: collection.teamID ?? collection.id,
                                sharingMode: .team,
                                cloudKitRecordName: "entry-\(snapshot.id.uuidString)",
                                labelColor: snapshot.labelColor,
                                assigneeText: snapshot.assigneeText
                            )
                        )
                        insertedCount += 1
                    }
                }
            }

            if modelContext.hasChanges { try modelContext.save() }
            await refreshTeamMemberRoster()
            if !silently, insertedCount > 0 {
                presentScheduleImportConfirmation("\(insertedCount) shared schedules added")
                canvasScope = .schedule
            }
        } catch {
            if !silently { processingError = error.localizedDescription }
        }
    }

    private var activeNotes: [BrainNote] {
        notes.filter { $0.lifecycleState == .active }
    }

    private var archiveNavigationMenu: some View {
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

    @ViewBuilder
    private var contextualNavigationMenu: some View {
        if canvasScope == .schedule, isTeamCalendarEnabled, scheduleWorkspace == .team {
            Menu {
                Button {
                    Task { await manageTeamCalendar() }
                } label: {
                    Label("Invite or manage people", systemImage: "person.badge.plus")
                }

                Button {
                    Task { await syncSharedSchedules(silently: false) }
                } label: {
                    Label("Sync team calendar", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isSyncingSharedSchedules)
            } label: {
                Image(systemName: "person.2.circle")
            }
            .accessibilityLabel("Manage team calendar")
        } else {
            Menu {
                if canvasScope == .schedule {
                    Toggle("Use Team Calendar", isOn: $isTeamCalendarEnabled)
                }
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
                Image(systemName: canvasScope == .schedule ? "gearshape" : "archivebox")
            }
            .accessibilityLabel(canvasScope == .schedule ? "Schedule settings" : "Archive and recently deleted")
        }
    }

    @MainActor
    private func manageTeamCalendar() async {
        guard let collection = scheduleCollections.first(where: {
            $0.resolvedSharingMode == .team && $0.shareState == .shared
        }), let zoneName = collection.cloudKitZoneName,
           let shareRecordName = collection.cloudKitShareRecordName else {
            processingError = "Add or import the first team schedule, then you can invite and manage members here."
            return
        }

        do {
            let prepared = try await ScheduleSharingService.shared.existingShare(
                zoneName: zoneName,
                shareRecordName: shareRecordName
            )
            #if canImport(UIKit)
            presentedSheet = .manageTeamShare(prepared)
            #endif
        } catch {
            processingError = error.localizedDescription
        }
    }

    private var compactSearchField: some View {
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

    private var archivedNotes: [BrainNote] {
        notes.filter { $0.lifecycleState == .archived }
    }

    private var trashedNotes: [BrainNote] {
        notes.filter { $0.lifecycleState == .trashed }
    }

    private var emptyCanvas: some View {
        ContentUnavailableView(
            "Your canvas is waiting",
            systemImage: "sparkles",
            description: Text("Capture a thought below. It will appear here as a card.")
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
    }

    private var isSearching: Bool {
        !normalizedSearchText.isEmpty
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var matchingNotes: [BrainNote] {
        guard isSearching else { return [] }

        return notes.filter { note in
            note.lifecycleState != .trashed
                && (note.rawText.localizedCaseInsensitiveContains(normalizedSearchText)
                    || note.category.title.localizedCaseInsensitiveContains(normalizedSearchText)
                    || note.tags.contains { $0.localizedCaseInsensitiveContains(normalizedSearchText) })
        }
    }

    private func relatedNotes(to source: BrainNote) -> [BrainNote] {
        let candidates = activeNotes.filter { $0.processingState == .complete }
        let relatedIDs = NoteConnections.rankedIDs(
            relatedTo: connectionSnapshot(for: source),
            among: candidates.map(connectionSnapshot),
            limit: 3
        )
        let notesByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        return relatedIDs.compactMap { notesByID[$0] }
    }

    private func connectionSnapshot(for note: BrainNote) -> NoteConnectionSnapshot {
        NoteConnectionSnapshot(
            id: note.id,
            tags: note.tags,
            category: note.category.rawValue,
            createdAt: note.createdAt
        )
    }

    private var upcomingNotes: [BrainNote] {
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

    private var resurfacedNotes: [BrainNote] {
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

    private var recentNotes: [BrainNote] {
        let featuredIDs = Set((upcomingNotes + resurfacedNotes).map(\.id))
        return activeNotes
            .filter { !featuredIDs.contains($0.id) }
            .prefix(6)
            .map { $0 }
    }

    private var incompleteActionableNotes: [BrainNote] {
        activeNotes.filter {
            $0.category == .actionable
                && !$0.isCompleted
                && $0.processingState == .complete
        }
    }

    private var scheduleWidgetSignature: [String] {
        let noteSignature = notes.map { note in
            [
                note.id.uuidString,
                note.rawText,
                note.category.rawValue,
                note.eventDate?.timeIntervalSinceReferenceDate.description ?? "nil",
                note.isCompleted.description,
                note.lifecycleState.rawValue,
                note.processingState.rawValue,
            ].joined(separator: "|")
        }
        let entrySignature = scheduleEntries.map { entry in
            [
                entry.id.uuidString,
                entry.title,
                entry.startDate.timeIntervalSinceReferenceDate.description,
                entry.endDate.timeIntervalSinceReferenceDate.description,
                entry.kind.rawValue,
                entry.teamID?.uuidString ?? "personal",
            ].joined(separator: "|")
        }
        return noteSignature + entrySignature
    }

    private var firstVisibleScheduleDay: Date {
        visibleScheduleEntries.first(where: {
            Calendar.current.isDate(
                $0.startDate,
                equalTo: displayedScheduleMonth,
                toGranularity: .month
            )
        })?.startDate ?? displayedScheduleMonth
    }

    private var visibleScheduleEntries: [ScheduleEntry] {
        switch scheduleWorkspace {
        case .personal:
            return scheduleEntries.filter { $0.resolvedSharingMode == .personal }
        case .team:
            return scheduleEntries.filter { $0.resolvedSharingMode == .team }
        }
    }

    private var activeScheduleImportMode: ScheduleSharingMode {
        canvasScope == .schedule ? scheduleWorkspace : .personal
    }

    private var overdueNotes: [BrainNote] {
        incompleteActionableNotes
            .filter { ($0.eventDate ?? .distantFuture) < Date() }
            .sorted { ($0.eventDate ?? .distantPast) < ($1.eventDate ?? .distantPast) }
    }

    private var todayNotes: [BrainNote] {
        let calendar = Calendar.current
        let now = Date()

        return incompleteActionableNotes
            .filter { note in
                guard let eventDate = note.eventDate else { return false }
                return eventDate >= now && calendar.isDateInToday(eventDate)
            }
            .sorted { ($0.eventDate ?? .distantFuture) < ($1.eventDate ?? .distantFuture) }
    }

    private var laterNotes: [BrainNote] {
        let startOfTomorrow = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        )

        return incompleteActionableNotes
            .filter { ($0.eventDate ?? .distantPast) >= startOfTomorrow }
            .sorted { ($0.eventDate ?? .distantFuture) < ($1.eventDate ?? .distantFuture) }
    }

    private var unscheduledNotes: [BrainNote] {
        incompleteActionableNotes
            .filter { $0.eventDate == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var scopePicker: some View {
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

    private var canvasHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            scopePicker

            if shouldShowCardGestureHint {
                cardGestureHint
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var processingErrorBinding: Binding<Bool> {
        Binding(
            get: { processingError != nil },
            set: { isPresented in
                if !isPresented { processingError = nil }
            }
        )
    }

    private var categoryNoteCounts: [BrainNoteCategory: Int] {
        Dictionary(grouping: activeNotes, by: \.category)
            .mapValues(\.count)
    }

    private var shouldShowCardGestureHint: Bool {
        guard !didLearnCardGestures, !activeNotes.isEmpty, !isSearching else { return false }

        switch canvasScope {
        case .home, .all, .category:
            return true
        default:
            return false
        }
    }

    private var cardGestureHint: some View {
        Text("Tap to edit · Swipe either way to organize")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.045), in: Capsule())
            .accessibilityLabel("Tip: Tap a note to edit. Swipe either way to organize it.")
    }

    @ViewBuilder
    private var dashboard: some View {
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
    private var scheduleDashboard: some View {
        ScheduleWorkspacePicker(
            selection: $scheduleWorkspace,
            personalCount: scheduleEntries.filter { $0.resolvedSharingMode == .personal }.count,
            teamCount: scheduleEntries.filter { $0.resolvedSharingMode == .team }.count,
            showsTeamCalendar: isTeamCalendarEnabled
        )
        .onChange(of: scheduleWorkspace) { _, newValue in
            let entries = visibleScheduleEntries
            selectedScheduleDay = entries.first(where: {
                Calendar.current.isDate(
                    $0.startDate,
                    equalTo: displayedScheduleMonth,
                    toGranularity: .month
                )
            })?.startDate
        }
        .onChange(of: isTeamCalendarEnabled) { _, isEnabled in
            if !isEnabled { scheduleWorkspace = .personal }
        }

        MonthlyScheduleCalendar(
            month: $displayedScheduleMonth,
            selectedDay: $selectedScheduleDay,
            entries: visibleScheduleEntries,
            sharingMode: scheduleWorkspace,
            onAdd: {
                presentedSheet = .addSchedule(
                    selectedScheduleDay ?? displayedScheduleMonth,
                    scheduleWorkspace
                )
            },
            onBulkEdit: {
                presentedSheet = .bulkEditSchedule(displayedScheduleMonth, scheduleWorkspace)
            },
            onImportImage: {
                isSchedulePhotoPickerPresented = true
            }
        )

        if visibleScheduleEntries.isEmpty {
            ContentUnavailableView(
                scheduleWorkspace == .team ? "No team schedule yet" : "Your schedule is clear",
                systemImage: scheduleWorkspace == .team ? "person.2" : "calendar.badge.checkmark",
                description: Text(
                    scheduleWorkspace == .team
                        ? "Add or import once, then invite your team."
                        : "Paste a monthly roster and it will organize itself here."
                )
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
    private func scheduleSection(
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
    private var searchResults: some View {
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
    private func noteCollection(
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

    private func noteGrid(_ notes: [BrainNote]) -> some View {
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

    private func destructiveSwipeAction(for note: BrainNote) -> CardSwipeAction {
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

    private func secondarySwipeAction(for note: BrainNote) -> CardSwipeAction {
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

    private func noteCard(_ note: BrainNote) -> some View {
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

    private func selectScope(_ scope: CanvasScope) {
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

    private func toggleSearch() {
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

    private var canvasBackground: some View {
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

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.purple)
                .padding(.bottom, 7)

            TextField("What’s on your mind?", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isComposerFocused)
                .submitLabel(.send)
                .onSubmit(saveNote)

            Button(action: saveNote) {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(trimmedDraft.isEmpty)
            .opacity(trimmedDraft.isEmpty ? 0.4 : 1)
            .accessibilityLabel("Save note")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 6)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveNote() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }

        let didSave = presentScheduleImport(from: text) || createNote(from: text)
        guard didSave else { return }

        withAnimation(.snappy) {
            draft = ""
        }
        isComposerFocused = true
    }

    private func saveClipboardText(_ text: String) {
        if let draft = makeScheduleImportDraft(from: text) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                presentedSheet = .importSchedule(draft, activeScheduleImportMode)
            }
        } else {
            _ = createNote(from: text)
        }
    }

    @discardableResult
    private func presentScheduleImport(from rawText: String) -> Bool {
        guard let draft = makeScheduleImportDraft(from: rawText) else { return false }
        presentedSheet = .importSchedule(draft, activeScheduleImportMode)
        return true
    }

    private func makeScheduleImportDraft(from rawText: String) -> ScheduleImportDraft? {
        WorkScheduleParser.parse(rawText).map {
            ScheduleImportDraft(rawText: rawText, schedule: $0)
        }
    }

    @MainActor
    private func readScheduleImage(_ item: PhotosPickerItem) async {
        isReadingScheduleImage = true
        defer {
            isReadingScheduleImage = false
            selectedSchedulePhotoItem = nil
        }

        do {
            guard let originalData = try await item.loadTransferable(type: Data.self) else {
                throw NoteProcessorError.noScheduleInImage
            }
            let image = optimizedScheduleImage(originalData)
            let draft = try await noteProcessor.extractSchedule(
                from: image.data,
                mimeType: image.mimeType
            )
            try Task.checkCancellation()
            presentedSheet = .importSchedule(draft, scheduleWorkspace)
        } catch is CancellationError {
            return
        } catch {
            processingError = error.localizedDescription
        }
    }

    private func optimizedScheduleImage(_ data: Data) -> (data: Data, mimeType: String) {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return (data, "image/jpeg") }
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, 2_048 / max(longestSide, 1))
        let targetSize = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return (resized.jpegData(compressionQuality: 0.84) ?? data, "image/jpeg")
        #else
        return (data, "image/jpeg")
        #endif
    }

    private func presentScheduleImportConfirmation(_ message: String) {
        scheduleImportDismissTask?.cancel()
        withAnimation(.snappy) {
            scheduleImportMessage = message
        }

        scheduleImportDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) {
                scheduleImportMessage = nil
            }
        }
    }

    @discardableResult
    private func createNote(from rawText: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        let note = BrainNote(rawText: text, category: .reflective)

        do {
            modelContext.insert(note)
            try modelContext.save()
        } catch {
            modelContext.delete(note)
            processingError = "The note could not be saved: \(error.localizedDescription)"
            return false
        }

        startProcessing(note)

        return true
    }

    private func startProcessing(_ note: BrainNote) {
        note.processingState = .pending

        do {
            try modelContext.save()
        } catch {
            processingError = "The note’s processing state could not be saved: \(error.localizedDescription)"
            return
        }

        Task { @MainActor in
            do {
                let result = try await noteProcessor.process(note, in: modelContext)
                guard applyProcessedIntent(result, to: note) else { return }
            } catch is CancellationError {
                // A cancelled analysis leaves the initial Reflective note intact.
            } catch {
                note.processingState = .failed
                try? modelContext.save()
                return
            }

            do {
                try await notificationScheduler.scheduleReminder(for: note)
            } catch {
                processingError = "The note was categorized, but its reminder could not be scheduled: \(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    private func applyProcessedIntent(
        _ result: NoteProcessingResult,
        to note: BrainNote
    ) -> Bool {
        let needsClarification = result.confidence < 0.8
            && (result.intent == .task || result.intent == .event)

        if needsClarification {
            note.category = .reflective
            note.suggestedIntent = result.intent
            note.intentConfidence = result.confidence
            note.suggestedTitle = result.title
            note.suggestedEndDate = result.endDate
            note.suggestedScheduleKind = result.scheduleKind
            try? modelContext.save()
            return true
        }

        clearIntentSuggestion(on: note)

        switch result.intent {
        case .task:
            note.category = .actionable
            try? modelContext.save()
            return true

        case .event:
            guard let startDate = result.eventDate else {
                note.suggestedIntent = .event
                note.intentConfidence = result.confidence
                note.suggestedTitle = result.title
                note.suggestedScheduleKind = result.scheduleKind
                try? modelContext.save()
                return true
            }
            return !moveNoteToSchedule(
                note,
                title: result.title,
                startDate: startDate,
                endDate: result.endDate,
                kind: result.scheduleKind
            )

        case .scheduleSeries:
            // Repeated schedules are normally routed before note creation by the local parser.
            // Keep parser misses safely as reference notes instead of guessing multiple dates.
            note.category = .reference
            note.eventDate = nil
            try? modelContext.save()
            return true

        case .note:
            note.eventDate = result.category == .actionable ? result.eventDate : nil
            try? modelContext.save()
            return true
        }
    }

    private func resolveIntent(of note: BrainNote, as intent: BrainNoteIntent) {
        switch intent {
        case .task:
            note.category = .actionable
            clearIntentSuggestion(on: note)
            do {
                try modelContext.save()
                refreshReminder(for: note)
            } catch {
                processingError = "The task could not be saved: \(error.localizedDescription)"
            }

        case .event:
            guard let startDate = note.eventDate else { return }
            _ = moveNoteToSchedule(
                note,
                title: note.suggestedTitle ?? note.rawText,
                startDate: startDate,
                endDate: note.suggestedEndDate,
                kind: note.suggestedScheduleKind ?? .other
            )

        case .note:
            note.category = .reflective
            note.eventDate = nil
            clearIntentSuggestion(on: note)
            try? modelContext.save()

        case .scheduleSeries:
            break
        }
    }

    @discardableResult
    private func moveNoteToSchedule(
        _ note: BrainNote,
        title: String,
        startDate: Date,
        endDate: Date?,
        kind: ScheduleKind
    ) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEnd = max(
            endDate ?? startDate.addingTimeInterval(60 * 60),
            startDate.addingTimeInterval(60)
        )
        let entry = ScheduleEntry(
            title: cleanTitle.isEmpty ? note.rawText : cleanTitle,
            startDate: startDate,
            endDate: resolvedEnd,
            kind: kind,
            details: cleanTitle == note.rawText ? nil : note.rawText,
            sharingMode: .personal,
            labelColor: kind.defaultLabelColor
        )

        modelContext.insert(entry)
        modelContext.delete(note)

        do {
            try modelContext.save()
            refreshScheduleWidget()
            presentScheduleImportConfirmation("Added to Schedule · \(entry.title)")
            return true
        } catch {
            modelContext.rollback()
            processingError = "The schedule could not be created: \(error.localizedDescription)"
            return false
        }
    }

    private func clearIntentSuggestion(on note: BrainNote) {
        note.suggestedIntent = nil
        note.intentConfidence = nil
        note.suggestedTitle = nil
        note.suggestedEndDate = nil
        note.suggestedScheduleKind = nil
    }

    private func toggleCompletion(of note: BrainNote) {
        let previousValue = note.isCompleted

        withAnimation(.snappy) {
            note.isCompleted.toggle()
        }

        do {
            try modelContext.save()
        } catch {
            note.isCompleted = previousValue
            processingError = "The completion status could not be saved: \(error.localizedDescription)"
            return
        }

        if note.isCompleted {
            notificationScheduler.cancelReminder(for: note)
        } else {
            Task { @MainActor in
                do {
                    try await notificationScheduler.scheduleReminder(for: note)
                } catch {
                    processingError = "The reminder could not be scheduled: \(error.localizedDescription)"
                }
            }
        }
    }

    private func saveEdits(_ edits: BrainNoteEdits, to note: BrainNote) {
        let previous = BrainNoteEdits(note: note)

        note.rawText = edits.normalizedRawText(fallback: previous.rawText)
        note.category = edits.category
        note.eventDate = edits.category == .actionable ? edits.eventDate : nil
        note.tags = edits.normalizedTags
        note.isCompleted = edits.category == .actionable ? edits.isCompleted : false

        do {
            try modelContext.save()
        } catch {
            previous.apply(to: note)
            processingError = "The note changes could not be saved: \(error.localizedDescription)"
            return
        }

        refreshReminder(for: note)
    }

    private func openRelatedNote(_ note: BrainNote) {
        presentedSheet = nil

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard notes.contains(where: { $0.id == note.id && $0.lifecycleState != .trashed }) else {
                return
            }
            presentedSheet = .edit(note)
        }
    }

    private func focusEmptyCanvasIfNeeded() {
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

    private func archive(_ note: BrainNote) {
        applyLifecycleChange(to: note, message: "Moved to Archive") {
            note.lifecycleState = .archived
            note.archivedAt = Date()
            note.trashedAt = nil
        }
    }

    private func unarchive(_ note: BrainNote) {
        applyLifecycleChange(to: note, message: "Returned to your canvas") {
            note.lifecycleState = .active
            note.archivedAt = nil
            note.trashedAt = nil
        }
    }

    private func moveToTrash(_ note: BrainNote) {
        applyLifecycleChange(to: note, message: "Moved to Recently Deleted") {
            note.lifecycleState = .trashed
            note.trashedAt = Date()
        }
    }

    private func restoreFromTrash(_ note: BrainNote) {
        let restoreState: BrainNoteLifecycleState = note.archivedAt == nil ? .active : .archived

        applyLifecycleChange(to: note, message: "Note restored") {
            note.lifecycleState = restoreState
            note.trashedAt = nil
        }
    }

    private func applyLifecycleChange(
        to note: BrainNote,
        message: String,
        update: () -> Void
    ) {
        let previous = LifecycleSnapshot(note: note)

        withAnimation(.snappy) {
            update()
        }

        do {
            try modelContext.save()
        } catch {
            previous.apply(to: note)
            processingError = "The note could not be moved: \(error.localizedDescription)"
            return
        }

        refreshReminder(for: note)
        presentUndo(for: note, previous: previous, message: message)
    }

    private func presentUndo(
        for note: BrainNote,
        previous: LifecycleSnapshot,
        message: String
    ) {
        undoDismissTask?.cancel()

        withAnimation(.snappy) {
            pendingUndo = PendingLifecycleUndo(
                noteID: note.id,
                previous: previous,
                message: message
            )
        }

        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }

            withAnimation(.snappy) {
                pendingUndo = nil
            }
        }
    }

    private func undoLifecycleChange() {
        guard let pendingUndo,
              let note = notes.first(where: { $0.id == pendingUndo.noteID }) else {
            self.pendingUndo = nil
            return
        }

        undoDismissTask?.cancel()
        let current = LifecycleSnapshot(note: note)

        withAnimation(.snappy) {
            pendingUndo.previous.apply(to: note)
            self.pendingUndo = nil
        }

        do {
            try modelContext.save()
        } catch {
            current.apply(to: note)
            processingError = "The move could not be undone: \(error.localizedDescription)"
            return
        }

        refreshReminder(for: note)
    }

    private func refreshReminder(for note: BrainNote) {
        guard note.lifecycleState == .active else {
            notificationScheduler.cancelReminder(for: note)
            return
        }

        Task { @MainActor in
            do {
                try await notificationScheduler.scheduleReminder(for: note)
            } catch {
                processingError = "The reminder could not be updated: \(error.localizedDescription)"
            }
        }
    }

    private func permanentlyDelete(_ note: BrainNote) {
        notificationScheduler.cancelReminder(for: note)
        modelContext.delete(note)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            processingError = "The note could not be permanently deleted: \(error.localizedDescription)"
        }
    }

    private func purgeExpiredTrash() {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else {
            return
        }

        let expiredNotes = trashedNotes.filter { note in
            guard let trashedAt = note.trashedAt else { return false }
            return trashedAt <= cutoff
        }

        guard !expiredNotes.isEmpty else { return }

        for note in expiredNotes {
            notificationScheduler.cancelReminder(for: note)
            modelContext.delete(note)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            processingError = "Expired deleted notes could not be cleared: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func openPendingNotificationNote() -> Bool {
        guard let noteID = BrainNoteNotificationRouter.shared.pendingNoteID() else {
            return false
        }

        openNotificationNote(noteID)
        return true
    }

    private func openNotificationNote(_ noteID: UUID) {
        guard let note = notes.first(where: { $0.id == noteID }) else {
            return
        }

        BrainNoteNotificationRouter.shared.clearPendingNoteID(noteID)

        searchText = ""
        isSearchPresented = false
        canvasScope = switch note.lifecycleState {
        case .active: .home
        case .archived: .archive
        case .trashed: .trash
        }

        lastSeenClipboardText = SystemClipboard.string?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        presentedSheet = .edit(note)
    }

    @discardableResult
    private func openComposerIfRequested() -> Bool {
        guard BrainNoteIntentRouteStore.consumeComposerRequest() else {
            return false
        }

        openComposer()
        return true
    }

    private func openComposer() {
        searchText = ""
        isSearchPresented = false
        canvasScope = .home
        notePendingPermanentDeletion = nil
        presentedSheet = nil
        lastSeenClipboardText = SystemClipboard.string?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        composerFocusTask?.cancel()
        isComposerFocused = false
        composerFocusTask = Task { @MainActor in
            // A widget can activate the app before the first scene is fully ready.
            // Retry briefly so cold launches and warm launches both show the keyboard.
            for delay in [0, 150_000_000, 350_000_000] {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay))
                } else {
                    await Task.yield()
                }

                guard !Task.isCancelled, presentedSheet == nil else { return }
                isComposerFocused = true
            }
        }
    }

    private func openSchedule() {
        composerFocusTask?.cancel()
        isComposerFocused = false
        searchText = ""
        isSearchPresented = false
        presentedSheet = nil
        notePendingPermanentDeletion = nil
        canvasScope = .schedule
        prepareScheduleMonth()
    }

    private func prepareScheduleMonth() {
        let calendar = Calendar.current
        let now = Date.now
        let currentMonthEntries = scheduleEntries.filter {
            calendar.isDate($0.startDate, equalTo: now, toGranularity: .month)
        }
        let preferredEntry = currentMonthEntries.first
            ?? scheduleEntries.first(where: { $0.endDate >= now })
            ?? scheduleEntries.last

        guard let preferredEntry else {
            displayedScheduleMonth = now
            selectedScheduleDay = now
            return
        }

        displayedScheduleMonth = preferredEntry.startDate
        selectedScheduleDay = preferredEntry.startDate
    }

    private func migrateLegacyScheduleNotesIfNeeded() {
        let legacyNotes = notes.filter { note in
            note.category == .actionable
                && note.eventDate != nil
                && note.tags.contains { $0 == "스케줄" }
        }
        guard !legacyNotes.isEmpty else { return }

        for note in legacyNotes {
            guard let startDate = note.eventDate else { continue }
            let endDate = legacyEndDate(from: note.rawText, startDate: startDate)
            let details = note.rawText
                .components(separatedBy: "·")
                .dropFirst()
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            modelContext.insert(
                ScheduleEntry(
                    title: "근무",
                    startDate: startDate,
                    endDate: endDate,
                    kind: .work,
                    details: details
                )
            )
            notificationScheduler.cancelReminder(for: note)
            modelContext.delete(note)
        }

        try? modelContext.save()
    }

    private func legacyEndDate(from text: String, startDate: Date) -> Date {
        let pattern = #"[-–—~]\s*(\d{1,2}):(\d{2})"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..., in: text)
              ),
              let hourRange = Range(match.range(at: 1), in: text),
              let minuteRange = Range(match.range(at: 2), in: text),
              let hour = Int(text[hourRange]),
              let minute = Int(text[minuteRange]) else {
            return startDate.addingTimeInterval(60 * 60)
        }

        var components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: startDate
        )
        components.hour = hour
        components.minute = minute
        guard var endDate = Calendar.current.date(from: components) else {
            return startDate.addingTimeInterval(60 * 60)
        }
        if endDate <= startDate {
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }
        return endDate
    }

    private func refreshScheduleWidget() {
        let items = scheduleEntries
            // The default widget is a private surface. Team schedules require a
            // separately configured team widget before they may appear there.
            .filter { $0.resolvedSharingMode == .personal }
            .map { entry in
                BrainNoteWidgetScheduleItem(
                    id: entry.id,
                    title: entry.title,
                    eventDate: entry.startDate,
                    endDate: entry.endDate,
                    kind: entry.kind.rawValue,
                    details: entry.details
                )
            }
            .sorted { $0.eventDate < $1.eventDate }
            .prefix(60)

        BrainNoteWidgetScheduleStore.save(Array(items))
    }

    private func deleteSchedule(_ entry: ScheduleEntry) {
        Task { await deleteScheduleEntry(entry) }
    }

    @MainActor
    private func deleteScheduleEntry(_ entry: ScheduleEntry) async {
        if case let .editSchedule(presentedEntry) = presentedSheet,
           presentedEntry.id == entry.id {
            // A deleted SwiftData model must not remain captured by a sheet.
            // Dismiss first so the sheet cannot read invalidated properties.
            presentedSheet = nil
            await Task.yield()
        }

        if let collection = scheduleCollections.first(where: { $0.id == entry.seriesID }),
           collection.resolvedSharingMode == .team,
           let zoneName = collection.cloudKitZoneName,
           let ownerName = collection.cloudKitZoneOwnerName {
            do {
                try await ScheduleSharingService.shared.deleteEntry(
                    id: entry.id,
                    zoneName: zoneName,
                    zoneOwnerName: ownerName
                )
            } catch {
                processingError = "The shared schedule could not be deleted: \(error.localizedDescription)"
                return
            }
        }

        modelContext.delete(entry)
        do {
            try modelContext.save()
            refreshScheduleWidget()
            presentScheduleImportConfirmation("Schedule deleted")
        } catch {
            processingError = "The schedule could not be deleted: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func refreshTeamMemberRoster() async {
        let sharedCollections = scheduleCollections.filter {
            $0.resolvedSharingMode == .team &&
            $0.cloudKitZoneName != nil &&
            $0.cloudKitZoneOwnerName != nil &&
            $0.cloudKitShareRecordName != nil
        }

        for collection in sharedCollections {
            guard let zoneName = collection.cloudKitZoneName,
                  let ownerName = collection.cloudKitZoneOwnerName,
                  let shareRecordName = collection.cloudKitShareRecordName else { continue }
            guard let names = try? await ScheduleSharingService.shared.participantNames(
                zoneName: zoneName,
                zoneOwnerName: ownerName,
                shareRecordName: shareRecordName
            ) else { continue }

            for name in names where !teamMembers.contains(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }) {
                modelContext.insert(ScheduleTeamMember(name: name))
            }
        }

        if modelContext.hasChanges { try? modelContext.save() }
    }

    private func migrateScheduleOwnershipIfNeeded() {
        let legacyTeamCollections = scheduleCollections.filter {
            $0.teamID != nil || $0.sharingMode == .team
        }
        var teamIDByCollectionID: [UUID: UUID] = [:]

        for collection in legacyTeamCollections {
            collection.assignOwnership(.team)
            teamIDByCollectionID[collection.id] = collection.teamID ?? collection.id
        }

        for entry in scheduleEntries {
            if let teamID = entry.teamID {
                entry.assignOwnership(.team, teamID: teamID)
            } else if entry.sharingMode == .team {
                let teamID = entry.seriesID.flatMap { teamIDByCollectionID[$0] }
                    ?? entry.seriesID
                    ?? entry.id
                entry.assignOwnership(.team, teamID: teamID)
            } else if let seriesID = entry.seriesID,
                      let teamID = teamIDByCollectionID[seriesID] {
                entry.assignOwnership(.team, teamID: teamID)
            } else {
                entry.assignOwnership(.personal)
            }
        }

        if modelContext.hasChanges { try? modelContext.save() }
    }

    private func inspectClipboard() {
        guard presentedSheet == nil else { return }

        guard let text = SystemClipboard.string?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              text != lastSeenClipboardText else {
            return
        }

        lastSeenClipboardText = text
        presentedSheet = .clipboard(text)
    }
}

enum CanvasScope: Equatable {
    case home
    case all
    case schedule
    case category(BrainNoteCategory)
    case archive
    case trash
}

private enum SheetDestination: Identifiable {
    case clipboard(String)
    case edit(BrainNote)
    case addSchedule(Date, ScheduleSharingMode)
    case editSchedule(ScheduleEntry)
    case importSchedule(ScheduleImportDraft, ScheduleSharingMode)
    case batchSchedule(Date, ScheduleSharingMode)
    case bulkEditSchedule(Date, ScheduleSharingMode)
    #if canImport(UIKit)
    case manageTeamShare(PreparedScheduleShare)
    #endif

    var id: String {
        switch self {
        case let .clipboard(text):
            "clipboard-\(text.hashValue)"
        case let .edit(note):
            "edit-\(note.id.uuidString)"
        case let .addSchedule(day, sharingMode):
            "add-schedule-\(sharingMode.rawValue)-\(Calendar.current.startOfDay(for: day).timeIntervalSinceReferenceDate)"
        case let .editSchedule(entry):
            "edit-schedule-\(entry.id.uuidString)"
        case let .importSchedule(draft, sharingMode):
            "import-schedule-\(sharingMode.rawValue)-\(draft.id.uuidString)"
        case let .batchSchedule(month, sharingMode):
            "batch-schedule-\(sharingMode.rawValue)-\(month.timeIntervalSinceReferenceDate)"
        case let .bulkEditSchedule(month, sharingMode):
            "bulk-edit-schedule-\(sharingMode.rawValue)-\(month.timeIntervalSinceReferenceDate)"
        #if canImport(UIKit)
        case let .manageTeamShare(prepared):
            "manage-team-\(prepared.id.uuidString)"
        #endif
        }
    }
}

private struct BrainNoteEdits {
    var rawText: String
    var category: BrainNoteCategory
    var eventDate: Date?
    var tags: [String]
    var isCompleted: Bool

    init(note: BrainNote) {
        rawText = note.rawText
        category = note.category
        eventDate = note.eventDate
        tags = note.tags
        isCompleted = note.isCompleted
    }

    func normalizedRawText(fallback: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    var normalizedTags: [String] {
        var seen = Set<String>()

        return tags.compactMap { tag in
            let normalized = tag
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard !normalized.isEmpty else { return nil }

            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return normalized
        }
        .prefix(8)
        .map { $0 }
    }

    func apply(to note: BrainNote) {
        note.rawText = rawText
        note.category = category
        note.eventDate = eventDate
        note.tags = tags
        note.isCompleted = isCompleted
    }
}

private struct LifecycleSnapshot {
    let state: BrainNoteLifecycleState
    let archivedAt: Date?
    let trashedAt: Date?

    init(note: BrainNote) {
        state = note.lifecycleState
        archivedAt = note.archivedAt
        trashedAt = note.trashedAt
    }

    func apply(to note: BrainNote) {
        note.lifecycleState = state
        note.archivedAt = archivedAt
        note.trashedAt = trashedAt
    }
}

private struct PendingLifecycleUndo: Identifiable {
    let id = UUID()
    let noteID: UUID
    let previous: LifecycleSnapshot
    let message: String
}

private struct StatusToast: View {
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 16, y: 7)
        .accessibilityElement(children: .combine)
    }
}

private struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text(message)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.bold))
                .buttonStyle(.plain)
                .foregroundStyle(.indigo)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 16, y: 7)
        .accessibilityElement(children: .contain)
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

private enum SystemClipboard {
    static var string: String? {
        #if canImport(UIKit)
        guard UIPasteboard.general.hasStrings else { return nil }
        return UIPasteboard.general.string
        #elseif canImport(AppKit)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }
}

private enum DayEditorDestination: Identifiable {
    case add(Date, ScheduleSharingMode)
    case edit(ScheduleEntry)

    var id: String {
        switch self {
        case let .add(day, mode): "add-\(mode.rawValue)-\(day.timeIntervalSinceReferenceDate)"
        case let .edit(entry): "edit-\(entry.id.uuidString)"
        }
    }
}

private struct DayScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ScheduleEntry.startDate) private var allEntries: [ScheduleEntry]

    let day: Date
    let sharingMode: ScheduleSharingMode
    @State private var editor: DayEditorDestination?

    private var entries: [ScheduleEntry] {
        allEntries.filter {
            $0.resolvedSharingMode == sharingMode &&
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
                                        if !entry.assigneeNames.isEmpty {
                                            Label(entry.assigneeNames.joined(separator: ", "), systemImage: "person.fill")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
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
                    Button { editor = .add(day, sharingMode) } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add schedule")
                }
            }
            .sheet(item: $editor) { destination in
                switch destination {
                case let .add(day, mode):
                    ScheduleEditorSheet(entry: nil, initialDay: day, initialSharingMode: mode)
                case let .edit(entry):
                    ScheduleEditorSheet(
                        entry: entry,
                        initialDay: entry.startDate,
                        initialSharingMode: entry.resolvedSharingMode
                    )
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

private struct BulkScheduleEditSheet: View {
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
    @Query(sort: \ScheduleCollection.createdAt) private var collections: [ScheduleCollection]
    @Query(sort: \ScheduleTeamMember.name) private var teamMembers: [ScheduleTeamMember]
    @Query(sort: \ScheduleTimePreset.createdAt) private var presets: [ScheduleTimePreset]

    let month: Date
    let sharingMode: ScheduleSharingMode

    @State private var selectedIDs: Set<UUID> = []
    @State private var labelColor = ScheduleLabelColor.indigo
    @State private var assigneeText = ""
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
            $0.resolvedSharingMode == sharingMode &&
            Calendar.current.isDate($0.startDate, equalTo: month, toGranularity: .month)
        }
    }

    private var filteredEntries: [ScheduleEntry] {
        entries.filter { entry in
            let matchesDay = selectedDays.isEmpty || selectedDays.contains(calendar.startOfDay(for: entry.startDate))
            let matchesColor = colorFilter == nil || entry.labelColor == colorFilter
            let matchesWeekday = weekdayFilter == nil || calendar.component(.weekday, from: entry.startDate) == weekdayFilter
            let matchesSearch = ScheduleSearch.matches(
                query: scheduleSearchText,
                title: entry.title,
                assigneeNames: entry.assigneeNames,
                includesAssignees: sharingMode == .team
            )
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
        NavigationStack {
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

                    if let actionMessage {
                        Label(actionMessage, systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    }

                    if taskMode == .add {
                        if sharingMode == .team {
                            Text("Assign people")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            TeamAssigneePicker(
                                candidateNames: teamMemberNames,
                                assigneeText: $assigneeText,
                                onAddPerson: addTeamMember
                            )
                            .padding(16)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    } else {
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

                        if !selectedIDs.isEmpty {
                            selectedScheduleActions
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Manage Schedules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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

            TextField(
                sharingMode == .team ? "Search schedule name or team member" : "Search schedule name",
                text: $scheduleSearchText
            )
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
            if sharingMode == .team {
                Divider()
                TeamAssigneePicker(
                    candidateNames: teamMemberNames,
                    assigneeText: $assigneeText,
                    onAddPerson: addTeamMember
                )
            }

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

    private var teamMemberNames: [String] {
        TeamAssigneePicker.combineMemberNames(
            savedMembers: teamMembers.map(\.name),
            entries: allEntries
        )
    }

    private func addTeamMember(_ name: String) {
        guard !teamMemberNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        modelContext.insert(ScheduleTeamMember(name: name))
        try? modelContext.save()
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
                teamID: sharingMode == .team ? seriesID : nil,
                sharingMode: sharingMode,
                cloudKitRecordName: sharingMode == .team ? "entry-\(UUID().uuidString)" : nil,
                labelColor: preset.labelColor ?? preset.kind.defaultLabelColor,
                assigneeText: sharingMode == .team
                    ? assigneeText.trimmingCharacters(in: .whitespacesAndNewlines)
                    : nil
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
                kind: preset.kind,
                sharingMode: sharingMode,
                teamID: sharingMode == .team ? seriesID : nil,
                shareState: sharingMode == .team ? .preparing : .local
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

        do {
            if sharingMode == .team {
                for entry in selected {
                    guard let seriesID = entry.seriesID,
                          let collection = collections.first(where: { $0.id == seriesID }),
                          let zone = collection.cloudKitZoneName,
                          let owner = collection.cloudKitZoneOwnerName else { continue }
                    try await ScheduleSharingService.shared.deleteEntry(
                        id: entry.id,
                        zoneName: zone,
                        zoneOwnerName: owner
                    )
                }
            }
            selected.forEach(modelContext.delete)
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
        let cleanAssignees = assigneeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = entries.filter { selectedIDs.contains($0.id) }
        selected.forEach {
            $0.labelColor = labelColor
            if sharingMode == .team { $0.assigneeText = cleanAssignees.isEmpty ? nil : cleanAssignees }
        }

        do {
            try modelContext.save()
            if sharingMode == .team {
                for entry in selected {
                    guard let seriesID = entry.seriesID,
                          let collection = collections.first(where: { $0.id == seriesID }),
                          let zone = collection.cloudKitZoneName,
                          let owner = collection.cloudKitZoneOwnerName else { continue }
                    try await ScheduleSharingService.shared.updateEntry(
                        ScheduleEntrySnapshot(
                            id: entry.id,
                            collectionID: seriesID,
                            title: entry.title,
                            startDate: entry.startDate,
                            endDate: entry.endDate,
                            kind: entry.kind,
                            details: entry.details,
                            labelColor: entry.labelColor,
                            assigneeText: entry.assigneeText
                        ),
                        zoneName: zone,
                        zoneOwnerName: owner
                    )
                }
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
            isSaving = false
        }
    }
}

private struct TeamAssigneePicker: View {
    let candidateNames: [String]
    @Binding var assigneeText: String
    let onAddPerson: (String) -> Void

    @State private var isAddingPerson = false
    @State private var newPersonName = ""

    private var selectedNames: Set<String> {
        Set(
            assigneeText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private var visibleNames: [String] {
        Array(Set(candidateNames).union(selectedNames)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Assign people")
                .font(.subheadline.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visibleNames, id: \.self) { name in
                        Button { toggle(name) } label: {
                            Label(
                                name,
                                systemImage: selectedNames.contains(name)
                                    ? "checkmark.circle.fill"
                                    : "person.circle"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedNames.contains(name) ? Color.white : Color.indigo)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(
                                selectedNames.contains(name) ? Color.indigo : Color.indigo.opacity(0.11),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Assign \(name)")
                        .accessibilityValue(selectedNames.contains(name) ? "Selected" : "Not selected")
                    }

                    Button {
                        newPersonName = ""
                        isAddingPerson = true
                    } label: {
                        Label("Add person", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .alert("Add team member", isPresented: $isAddingPerson) {
            TextField("Name", text: $newPersonName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Add") { addPerson() }
        } message: {
            Text("They will be ready to select for this schedule.")
        }
    }

    static func combineMemberNames(
        savedMembers: [String],
        entries: [ScheduleEntry]
    ) -> [String] {
        Array(
            Set(
                savedMembers + entries
                    .filter { $0.resolvedSharingMode == .team }
                    .flatMap(\.assigneeNames)
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func toggle(_ name: String) {
        var updated = selectedNames
        if updated.contains(name) {
            updated.remove(name)
        } else {
            updated.insert(name)
        }
        assigneeText = updated.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .joined(separator: ", ")
    }

    private func addPerson() {
        let name = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        onAddPerson(name)
    }
}

private struct ScheduleLabelColorPicker: View {
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

private struct BatchScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduleTimePreset.createdAt) private var presets: [ScheduleTimePreset]
    @Query(sort: \ScheduleEntry.startDate) private var existingEntries: [ScheduleEntry]
    @Query(sort: \ScheduleTeamMember.name) private var teamMembers: [ScheduleTeamMember]

    let month: Date
    let sharingMode: ScheduleSharingMode

    @State private var selectedPresetID: UUID?
    @State private var selectedDays: Set<Date> = []
    @State private var presetEditor: ScheduleTimePreset?
    @State private var isNewPresetEditorPresented = false
    @State private var assigneeText = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var preparedShare: PreparedScheduleShare?
    @State private var dismissAfterSharing = false

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private let weekdaySymbols = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    destinationHeader
                    presetPicker
                    datePicker
                }
                .padding(20)
                .padding(.bottom, 82)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Add Favorite Times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) { saveButton }
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
            #if canImport(UIKit)
            .sheet(item: $preparedShare, onDismiss: {
                if dismissAfterSharing { dismiss() }
            }) { prepared in
                CloudSharingController(
                    preparedShare: prepared,
                    title: "Team Calendar",
                    onError: { saveError = $0.localizedDescription }
                )
            }
            #endif
        }
    }

    private var destinationHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: sharingMode.symbolName)
                .foregroundStyle(sharingMode == .team ? .indigo : .blue)
                .frame(width: 34, height: 34)
                .background((sharingMode == .team ? Color.indigo : Color.blue).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(sharingMode.title) calendar")
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

            if sharingMode == .team {
                TeamAssigneePicker(
                    candidateNames: teamMemberNames,
                    assigneeText: $assigneeText,
                    onAddPerson: addTeamMember
                )
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

    private var teamMemberNames: [String] {
        TeamAssigneePicker.combineMemberNames(
            savedMembers: teamMembers.map(\.name),
            entries: existingEntries
        )
    }

    private func addTeamMember(_ name: String) {
        guard !teamMemberNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        modelContext.insert(ScheduleTeamMember(name: name))
        try? modelContext.save()
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
                $0.resolvedSharingMode == sharingMode &&
                $0.startDate == interval.start && $0.endDate == interval.end
            }
            guard !duplicate else { return nil }
            return ScheduleEntry(
                title: preset.name,
                startDate: interval.start,
                endDate: interval.end,
                kind: preset.kind,
                seriesID: seriesID,
                teamID: sharingMode == .team ? seriesID : nil,
                sharingMode: sharingMode,
                cloudKitRecordName: sharingMode == .team ? "entry-\(UUID().uuidString)" : nil,
                labelColor: preset.labelColor ?? preset.kind.defaultLabelColor,
                assigneeText: sharingMode == .team ? assigneeText.trimmingCharacters(in: .whitespacesAndNewlines) : nil
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
            kind: preset.kind,
            sharingMode: sharingMode,
            teamID: sharingMode == .team ? seriesID : nil,
            shareState: sharingMode == .team ? .preparing : .local
        )
        candidates.forEach {
            if sharingMode == .team { $0.cloudKitRecordName = "entry-\($0.id.uuidString)" }
        }
        modelContext.insert(collection)
        candidates.forEach(modelContext.insert)

        do {
            try modelContext.save()
            NotificationCenter.default.post(
                name: .brainNoteScheduleImported,
                object: ScheduleImportOutcome(
                    month: normalizedMonth,
                    firstDate: candidates.first?.startDate,
                    count: candidates.count,
                    sharingMode: sharingMode
                )
            )

            guard sharingMode == .team else {
                dismiss()
                return
            }

            let prepared = try await ScheduleSharingService.shared.prepareShare(
                collection: ScheduleCollectionSnapshot(
                    id: seriesID,
                    title: "Team Calendar",
                    month: normalizedMonth,
                    kind: preset.kind
                ),
                entries: candidates.map {
                    ScheduleEntrySnapshot(
                        id: $0.id,
                        collectionID: seriesID,
                        title: $0.title,
                        startDate: $0.startDate,
                        endDate: $0.endDate,
                        kind: $0.kind,
                        details: $0.details,
                        labelColor: $0.labelColor,
                        assigneeText: $0.assigneeText
                    )
                }
            )
            collection.shareState = .shared
            collection.cloudKitZoneName = prepared.share.recordID.zoneID.zoneName
            collection.cloudKitZoneOwnerName = prepared.share.recordID.zoneID.ownerName
            collection.cloudKitRootRecordName = "collection-\(seriesID.uuidString)"
            collection.cloudKitShareRecordName = prepared.share.recordID.recordName
            collection.shareURLString = prepared.share.url?.absoluteString
            collection.participantCount = max(prepared.share.participants.count, 1)
            try modelContext.save()
            isSaving = false
            dismissAfterSharing = true
            preparedShare = prepared
        } catch {
            // A failed invitation must not leak team-authored data into the
            // personal workspace. Keep it team-owned and allow retry.
            collection.assignOwnership(.team)
            collection.shareState = .failed
            candidates.forEach { $0.assignOwnership(.team, teamID: collection.teamID ?? collection.id) }
            try? modelContext.save()
            isSaving = false
            saveError = "Saved in Team Calendar, but sharing needs to be retried. \(error.localizedDescription)"
        }
    }
}

private struct TimePresetEditorSheet: View {
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

private struct ScheduleImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduleEntry.startDate) private var existingEntries: [ScheduleEntry]

    let draft: ScheduleImportDraft
    let noteProcessor: NoteProcessor
    let sharingMode: ScheduleSharingMode

    @State private var title: String
    @State private var kind: ScheduleKind
    @State private var confidence: Double?
    @State private var isAnalyzing = true
    @State private var hasAnalyzed = false
    @State private var userConfirmedKind = false
    @State private var includeOverlaps = true
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var preparedShare: PreparedScheduleShare?
    @State private var didSaveSchedule = false

    init(
        draft: ScheduleImportDraft,
        noteProcessor: NoteProcessor,
        sharingMode: ScheduleSharingMode
    ) {
        self.draft = draft
        self.noteProcessor = noteProcessor
        self.sharingMode = sharingMode
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
                    sharingDestinationCard
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
            #if canImport(UIKit)
            .sheet(item: $preparedShare, onDismiss: {
                if didSaveSchedule { dismiss() }
            }) { prepared in
                CloudSharingController(
                    preparedShare: prepared,
                    title: title,
                    onError: { error in saveError = error.localizedDescription }
                )
            }
            #endif
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

    private var sharingDestinationCard: some View {
        HStack(spacing: 12) {
            Image(systemName: sharingMode.symbolName)
                .font(.headline)
                .foregroundStyle(sharingMode == .team ? Color.indigo : Color.accentColor)
                .frame(width: 38, height: 38)
                .background(
                    (sharingMode == .team ? Color.indigo : Color.accentColor).opacity(0.12),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("\(sharingMode.title) Calendar")
                    .font(.subheadline.weight(.semibold))
                Text(sharingMode == .team
                    ? "An iCloud invitation opens after import. Your notes remain private."
                    : "Only you can see this schedule.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            if sharingMode == .team {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.indigo)
                    .accessibilityLabel(
                        "An iCloud invitation opens after import. Your notes remain private."
                    )
            }
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
                Label(
                    importButtonTitle,
                    systemImage: sharingMode == .team ? "person.2.badge.plus" : "calendar.badge.plus"
                )
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
        if isSaving { return sharingMode == .team ? "Preparing team schedule…" : "Saving…" }
        return sharingMode == .team
            ? "Add \(selectedShifts.count) and invite team"
            : "Add \(selectedShifts.count) schedules"
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
            existingWorkspaceEntries.contains {
                $0.startDate == shift.startDate && $0.endDate == shift.endDate
            } ? shift.id : nil
        })
    }

    private var overlapIDs: Set<UUID> {
        Set(draft.schedule.shifts.compactMap { shift in
            guard !duplicateIDs.contains(shift.id) else { return nil }
            return existingWorkspaceEntries.contains {
                shift.startDate < $0.endDate && shift.endDate > $0.startDate
            } ? shift.id : nil
        })
    }

    private var existingWorkspaceEntries: [ScheduleEntry] {
        existingEntries.filter { $0.resolvedSharingMode == sharingMode }
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
            kind: kind,
            sharingMode: sharingMode,
            teamID: sharingMode == .team ? seriesID : nil,
            shareState: sharingMode == .team ? .preparing : .local
        )
        let entries = selectedShifts.map { shift in
            ScheduleEntry(
                id: shift.id,
                title: finalTitle,
                startDate: shift.startDate,
                endDate: shift.endDate,
                kind: kind,
                details: shift.details,
                seriesID: seriesID,
                teamID: sharingMode == .team ? seriesID : nil,
                sharingMode: sharingMode,
                cloudKitRecordName: sharingMode == .team ? "entry-\(shift.id.uuidString)" : nil
            )
        }

        modelContext.insert(collection)
        entries.forEach(modelContext.insert)

        do {
            try modelContext.save()
            didSaveSchedule = true
            NotificationCenter.default.post(
                name: .brainNoteScheduleImported,
                object: ScheduleImportOutcome(
                    month: draft.schedule.month,
                    firstDate: entries.first?.startDate,
                    count: entries.count,
                    sharingMode: sharingMode
                )
            )

            guard sharingMode == .team else {
                dismiss()
                return
            }

            let collectionSnapshot = ScheduleCollectionSnapshot(
                id: collection.id,
                title: collection.title,
                month: collection.month,
                kind: collection.kind
            )
            let entrySnapshots = entries.map {
                ScheduleEntrySnapshot(
                    id: $0.id,
                    collectionID: seriesID,
                    title: $0.title,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    kind: $0.kind,
                    details: $0.details
                )
            }
            let prepared = try await ScheduleSharingService.shared.prepareShare(
                collection: collectionSnapshot,
                entries: entrySnapshots
            )

            collection.shareState = .shared
            collection.cloudKitZoneName = prepared.share.recordID.zoneID.zoneName
            collection.cloudKitZoneOwnerName = prepared.share.recordID.zoneID.ownerName
            collection.cloudKitRootRecordName = "collection-\(collection.id.uuidString)"
            collection.cloudKitShareRecordName = prepared.share.recordID.recordName
            collection.shareURLString = prepared.share.url?.absoluteString
            collection.participantCount = max(prepared.share.participants.count, 1)
            try modelContext.save()
            isSaving = false
            preparedShare = prepared
        } catch {
            if didSaveSchedule {
                // Preserve the chosen workspace even when CloudKit setup fails.
                collection.assignOwnership(.team)
                collection.shareState = .failed
                entries.forEach {
                    $0.assignOwnership(.team, teamID: collection.teamID ?? collection.id)
                    $0.cloudKitRecordName = nil
                }
                try? modelContext.save()
                saveError = "The schedule remains in Team Calendar, but sharing needs to be retried. \(error.localizedDescription)"
            } else {
                modelContext.rollback()
                saveError = error.localizedDescription
            }
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

private struct ScheduleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduleEntry.startDate) private var scheduleEntries: [ScheduleEntry]
    @Query(sort: \ScheduleCollection.createdAt) private var scheduleCollections: [ScheduleCollection]
    @Query(sort: \ScheduleTeamMember.name) private var teamMembers: [ScheduleTeamMember]

    let entry: ScheduleEntry?

    @State private var title: String
    @State private var kind: ScheduleKind
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var details: String
    @State private var labelColor: ScheduleLabelColor
    @State private var assigneeText: String
    @State private var saveError: String?
    @State private var sharingMode: ScheduleSharingMode
    @State private var isSaving = false
    @State private var preparedShare: PreparedScheduleShare?
    @State private var dismissAfterSharing = false
    @State private var isDeleteConfirmationPresented = false
    @FocusState private var isTitleFocused: Bool

    init(
        entry: ScheduleEntry?,
        initialDay: Date,
        initialSharingMode: ScheduleSharingMode
    ) {
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
        _assigneeText = State(initialValue: entry?.assigneeText ?? "")
        _sharingMode = State(initialValue: entry?.resolvedSharingMode ?? initialSharingMode)
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

                Section("Calendar") {
                    HStack {
                        Label("\(sharingMode.title) Calendar", systemImage: sharingMode.symbolName)
                            .foregroundStyle(sharingMode == .team ? Color.indigo : Color.accentColor)
                        Spacer()
                        if entry?.resolvedSharingMode == .team {
                            Text(memberSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if sharingMode == .team {
                        TeamAssigneePicker(
                            candidateNames: teamMemberNames,
                            assigneeText: $assigneeText,
                            onAddPerson: addTeamMember
                        )
                    }

                    if entry?.resolvedSharingMode == .team {
                        Button("Manage People") {
                            Task { await managePeople() }
                        }
                        .disabled(isSaving || sharedCollection == nil)
                    } else if sharingMode == .team {
                        Text("An iCloud invitation opens after saving.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
            #if canImport(UIKit)
            .sheet(item: $preparedShare, onDismiss: {
                if dismissAfterSharing { dismiss() }
            }) { prepared in
                CloudSharingController(
                    preparedShare: prepared,
                    title: finalTitle,
                    onError: { error in saveError = error.localizedDescription }
                )
            }
            #endif
        }
    }

    private var finalTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? kind.title : trimmedTitle
    }

    private var sharedCollection: ScheduleCollection? {
        guard let seriesID = entry?.seriesID else { return nil }
        return scheduleCollections.first { $0.id == seriesID }
    }

    private var memberSummary: String {
        guard let collection = sharedCollection else { return "Shared" }
        return collection.participantCount == 1
            ? "Only you"
            : "\(collection.participantCount) people"
    }

    private var teamMemberNames: [String] {
        TeamAssigneePicker.combineMemberNames(
            savedMembers: teamMembers.map(\.name),
            entries: scheduleEntries
        )
    }

    private func addTeamMember(_ name: String) {
        guard !teamMemberNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        modelContext.insert(ScheduleTeamMember(name: name))
        try? modelContext.save()
    }

    @MainActor
    private func deleteSchedule() async {
        guard let entry else { return }
        isSaving = true
        defer { isSaving = false }

        if let collection = sharedCollection,
           collection.resolvedSharingMode == .team,
           let zoneName = collection.cloudKitZoneName,
           let ownerName = collection.cloudKitZoneOwnerName {
            do {
                try await ScheduleSharingService.shared.deleteEntry(
                    id: entry.id,
                    zoneName: zoneName,
                    zoneOwnerName: ownerName
                )
            } catch {
                saveError = "The shared schedule could not be deleted: \(error.localizedDescription)"
                return
            }
        }

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
        let wasAlreadyShared = entry?.resolvedSharingMode == .team
        let savedEntry: ScheduleEntry

        if let entry {
            entry.title = finalTitle
            entry.kind = kind
            entry.startDate = startDate
            entry.endDate = endDate
            entry.details = finalDetails.isEmpty ? nil : finalDetails
            entry.labelColor = labelColor
            entry.assigneeText = sharingMode == .team
                ? assigneeText.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
            if sharingMode == .personal {
                entry.assignOwnership(.personal)
            }
            savedEntry = entry
        } else {
            let newEntry = ScheduleEntry(
                title: finalTitle,
                startDate: startDate,
                endDate: endDate,
                kind: kind,
                details: finalDetails.isEmpty ? nil : finalDetails,
                sharingMode: sharingMode,
                labelColor: labelColor,
                assigneeText: sharingMode == .team
                    ? assigneeText.trimmingCharacters(in: .whitespacesAndNewlines)
                    : nil
            )
            modelContext.insert(newEntry)
            newEntry.assignOwnership(sharingMode)
            savedEntry = newEntry
        }

        do {
            guard sharingMode == .team, !wasAlreadyShared else {
                try modelContext.save()
                if wasAlreadyShared,
                   let collection = sharedCollection,
                   let zoneName = collection.cloudKitZoneName,
                   let ownerName = collection.cloudKitZoneOwnerName,
                   let seriesID = savedEntry.seriesID {
                    try await ScheduleSharingService.shared.updateEntry(
                        ScheduleEntrySnapshot(
                            id: savedEntry.id,
                            collectionID: seriesID,
                            title: savedEntry.title,
                            startDate: savedEntry.startDate,
                            endDate: savedEntry.endDate,
                            kind: savedEntry.kind,
                            details: savedEntry.details,
                            labelColor: savedEntry.labelColor,
                            assigneeText: savedEntry.assigneeText
                        ),
                        zoneName: zoneName,
                        zoneOwnerName: ownerName
                    )
                }
                isSaving = false
                dismiss()
                return
            }

            let seriesID = savedEntry.seriesID ?? UUID()
            savedEntry.seriesID = seriesID
            let groupedEntries = scheduleEntries.filter { $0.seriesID == seriesID } +
                (scheduleEntries.contains(where: { $0.id == savedEntry.id }) ? [] : [savedEntry])
            groupedEntries.forEach { $0.assignOwnership(.team, teamID: seriesID) }

            let collection = scheduleCollections.first { $0.id == seriesID } ?? ScheduleCollection(
                id: seriesID,
                title: finalTitle,
                month: Calendar.current.date(
                    from: Calendar.current.dateComponents([.year, .month], from: startDate)
                ) ?? startDate,
                kind: kind,
                sharingMode: .team,
                teamID: seriesID,
                shareState: .preparing
            )
            if !scheduleCollections.contains(where: { $0.id == seriesID }) {
                modelContext.insert(collection)
            }
            try modelContext.save()

            let prepared = try await ScheduleSharingService.shared.prepareShare(
                collection: ScheduleCollectionSnapshot(
                    id: collection.id,
                    title: collection.title,
                    month: collection.month,
                    kind: collection.kind
                ),
                entries: groupedEntries.map {
                    ScheduleEntrySnapshot(
                        id: $0.id,
                        collectionID: seriesID,
                        title: $0.title,
                        startDate: $0.startDate,
                        endDate: $0.endDate,
                        kind: $0.kind,
                        details: $0.details,
                        labelColor: $0.labelColor,
                        assigneeText: $0.assigneeText
                    )
                }
            )

            collection.shareState = .shared
            collection.cloudKitZoneName = prepared.share.recordID.zoneID.zoneName
            collection.cloudKitZoneOwnerName = prepared.share.recordID.zoneID.ownerName
            collection.cloudKitRootRecordName = "collection-\(collection.id.uuidString)"
            collection.cloudKitShareRecordName = prepared.share.recordID.recordName
            collection.shareURLString = prepared.share.url?.absoluteString
            collection.participantCount = max(prepared.share.participants.count, 1)
            groupedEntries.forEach {
                $0.cloudKitRecordName = "entry-\($0.id.uuidString)"
            }
            try modelContext.save()

            isSaving = false
            dismissAfterSharing = true
            preparedShare = prepared
        } catch {
            if sharingMode == .team, !wasAlreadyShared {
                let seriesID = savedEntry.seriesID
                scheduleEntries.filter { $0.seriesID == seriesID }.forEach {
                    $0.assignOwnership(.team, teamID: seriesID)
                    $0.cloudKitRecordName = nil
                }
                savedEntry.assignOwnership(.team, teamID: seriesID)
                if let seriesID,
                   let collection = scheduleCollections.first(where: { $0.id == seriesID }) {
                    collection.assignOwnership(.team)
                    collection.shareState = .failed
                }
                try? modelContext.save()
                saveError = "Saved in Team Calendar, but sharing needs to be retried. \(error.localizedDescription)"
            } else {
                modelContext.rollback()
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }

    @MainActor
    private func managePeople() async {
        guard let collection = sharedCollection,
              let zoneName = collection.cloudKitZoneName,
              let shareRecordName = collection.cloudKitShareRecordName else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            dismissAfterSharing = false
            preparedShare = try await ScheduleSharingService.shared.existingShare(
                zoneName: zoneName,
                shareRecordName: shareRecordName
            )
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct QuickEditSheet: View {
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

#if canImport(UIKit)
private struct ActivityView: UIViewControllerRepresentable {
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

private struct ClipboardSaveSheet: View {
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

#Preview("Life Canvas") {
    ContentView()
        .modelContainer(PreviewStore.container)
}

@MainActor
private enum PreviewStore {
    static let container: ModelContainer = {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: BrainNote.self,
            ScheduleEntry.self,
            ScheduleCollection.self,
            ScheduleTimePreset.self,
            ScheduleTeamMember.self,
            configurations: configuration
        )

        container.mainContext.insert(
            BrainNote(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                rawText: "Send the product proposal tomorrow at 9 AM",
                createdAt: Date(),
                category: .actionable,
                eventDate: Calendar.current.date(
                    bySettingHour: 9,
                    minute: 0,
                    second: 0,
                    of: Calendar.current.date(byAdding: .day, value: 1, to: Date())!
                ),
                tags: ["work", "proposal"],
                processingState: .complete
            )
        )
        container.mainContext.insert(
            BrainNote(
                rawText: "A calm morning walk made everything feel lighter.",
                createdAt: Date().addingTimeInterval(-60 * 60 * 24 * 3),
                category: .reflective,
                tags: ["morning", "gratitude"],
                processingState: .complete
            )
        )
        container.mainContext.insert(
            BrainNote(
                rawText: "Slow productivity: protect fewer priorities and give them more time.",
                createdAt: Date().addingTimeInterval(-60 * 60 * 24 * 8),
                category: .reference,
                tags: ["productivity", "reading"],
                processingState: .complete
            )
        )
        container.mainContext.insert(
            BrainNote(
                rawText: "Design an ambient sound map for different city neighborhoods",
                createdAt: Date().addingTimeInterval(-600),
                category: .creative,
                processingState: .pending
            )
        )
        container.mainContext.insert(
            BrainNote(
                rawText: "Remember the article about slow productivity",
                createdAt: Date().addingTimeInterval(-900),
                category: .reference,
                tags: ["reading"],
                processingState: .failed
            )
        )
        try! container.mainContext.save()

        return container
    }()
}
