import SwiftData
import SwiftUI
import PhotosUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
struct ContentView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.scenePhase) var scenePhase
    @Query(sort: \BrainNote.createdAt, order: .reverse) var notes: [BrainNote]
    @Query(sort: \ScheduleEntry.startDate) var scheduleEntries: [ScheduleEntry]
    @Query(sort: \ScheduleCollection.createdAt, order: .reverse)
    var scheduleCollections: [ScheduleCollection]

    @State var draft = ""
    @State var processingError: String?
    @State var presentedSheet: SheetDestination?
    @State var lastSeenClipboardText: String?
    @State var searchText = ""
    @State var isSearchPresented = false
    @State var canvasScope = CanvasScope.home
    @State var pendingUndo: PendingLifecycleUndo?
    @State var undoDismissTask: Task<Void, Never>?
    @State var composerFocusTask: Task<Void, Never>?
    @State var notePendingPermanentDeletion: BrainNote?
    @State var displayedScheduleMonth = Date.now
    @State var selectedScheduleDay: Date?
    @AppStorage("brainnote.didLearnCardGestures") var didLearnCardGestures = false
    @State var scheduleImportMessage: String?
    @State var scheduleImportDismissTask: Task<Void, Never>?
    @State var isSchedulePhotoPickerPresented = false
    @State var selectedSchedulePhotoItem: PhotosPickerItem?
    @State var isReadingScheduleImage = false
    @FocusState var isComposerFocused: Bool
    @FocusState var isSearchFieldFocused: Bool

    let noteProcessor = NoteProcessor(apiKey: AppSecrets.openAIAPIKey)
    let notificationScheduler = NotificationScheduler()

    let columns = [
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

                case let .addSchedule(day):
                    ScheduleEditorSheet(entry: nil, initialDay: day)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)

                case let .editSchedule(entry):
                    ScheduleEditorSheet(entry: entry, initialDay: entry.startDate)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)

                case let .importSchedule(draft):
                    ScheduleImportPreviewSheet(draft: draft, noteProcessor: noteProcessor)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)

                case let .batchSchedule(month):
                    BatchScheduleSheet(month: month)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)

                case let .bulkEditSchedule(month):
                    BulkScheduleEditSheet(month: month)
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
                canvasScope = .schedule
                presentScheduleImportConfirmation(
                    "\(outcome.count) schedules added · \(outcome.month.formatted(.dateTime.month(.wide).year()))"
                )
            }
            .onOpenURL(perform: handleOpenURL)
            .onDisappear {
                undoDismissTask?.cancel()
                composerFocusTask?.cancel()
                scheduleImportDismissTask?.cancel()
            }
        }
    }

    var activeNotes: [BrainNote] {
        notes.filter { $0.lifecycleState == .active }
    }

    var archivedNotes: [BrainNote] {
        notes.filter { $0.lifecycleState == .archived }
    }

    var trashedNotes: [BrainNote] {
        notes.filter { $0.lifecycleState == .trashed }
    }

    var processingErrorBinding: Binding<Bool> {
        Binding(
            get: { processingError != nil },
            set: { isPresented in
                if !isPresented { processingError = nil }
            }
        )
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
