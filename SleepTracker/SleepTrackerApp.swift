import SwiftUI
import SwiftData

@main
struct SleepTrackerApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([Night.self, SoundClip.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Vytvoření lokálního úložiště při startu appky prakticky nikdy
            // neselže (jde o standardní SwiftData boilerplate); pokud by se
            // tak přesto stalo, appka bez datového úložiště stejně nemá jak
            // fungovat, proto je fatalError namístě.
            fatalError("Nepodařilo se vytvořit SwiftData úložiště: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            NightsListView()
        }
        .modelContainer(sharedModelContainer)
    }
}
