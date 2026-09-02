import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension ContentView {
    var composer: some View {
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
    var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func saveNote() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }

        let didSave = presentScheduleImport(from: text) || createNote(from: text)
        guard didSave else { return }

        withAnimation(.snappy) {
            draft = ""
        }
        isComposerFocused = true
    }
    func saveClipboardText(_ text: String) {
        if let draft = makeScheduleImportDraft(from: text) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                presentedSheet = .importSchedule(draft)
            }
        } else {
            _ = createNote(from: text)
        }
    }
    @discardableResult
    func presentScheduleImport(from rawText: String) -> Bool {
        guard let draft = makeScheduleImportDraft(from: rawText) else { return false }
        presentedSheet = .importSchedule(draft)
        return true
    }
    func makeScheduleImportDraft(from rawText: String) -> ScheduleImportDraft? {
        WorkScheduleParser.parse(rawText).map {
            ScheduleImportDraft(rawText: rawText, schedule: $0)
        }
    }
    @MainActor
    func readScheduleImage(_ item: PhotosPickerItem) async {
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
            presentedSheet = .importSchedule(draft)
        } catch is CancellationError {
            return
        } catch {
            processingError = error.localizedDescription
        }
    }
    func optimizedScheduleImage(_ data: Data) -> (data: Data, mimeType: String) {
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
    func presentScheduleImportConfirmation(_ message: String) {
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
    func createNote(from rawText: String) -> Bool {
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
    func startProcessing(_ note: BrainNote) {
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
}
