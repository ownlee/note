import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum SystemClipboard {
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

extension ContentView {
    func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "brainnote" else { return }

        switch url.host?.lowercased() {
        case "capture":
            openComposer()
        case "schedule":
            openSchedule()
            if url.pathComponents.contains("favorites") {
                presentedSheet = .batchSchedule(displayedScheduleMonth)
            } else if url.pathComponents.contains("add") {
                presentedSheet = .addSchedule(Date.now)
            }
        default:
            break
        }
    }
    @discardableResult
    func openPendingNotificationNote() -> Bool {
        guard let noteID = BrainNoteNotificationRouter.shared.pendingNoteID() else {
            return false
        }

        openNotificationNote(noteID)
        return true
    }
    func openNotificationNote(_ noteID: UUID) {
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
    func openComposerIfRequested() -> Bool {
        guard BrainNoteIntentRouteStore.consumeComposerRequest() else {
            return false
        }

        openComposer()
        return true
    }
    func openComposer() {
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
    func openSchedule() {
        composerFocusTask?.cancel()
        isComposerFocused = false
        searchText = ""
        isSearchPresented = false
        presentedSheet = nil
        notePendingPermanentDeletion = nil
        canvasScope = .schedule
        prepareScheduleMonth()
    }
    func inspectClipboard() {
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
