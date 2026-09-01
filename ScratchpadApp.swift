import SwiftData
import SwiftUI

@main
struct ScratchpadApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(BrainNoteAppDelegate.self) private var appDelegate
    #endif

    private let modelContainer: ModelContainer

    init() {
        do {
            let configuration = ModelConfiguration(cloudKitDatabase: .none)
            modelContainer = try ModelContainer(
                for: BrainNote.self,
                ScheduleEntry.self,
                ScheduleCollection.self,
                ScheduleTimePreset.self,
                ScheduleTeamMember.self,
                configurations: configuration
            )
        } catch {
            fatalError("Could not create the SwiftData model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
