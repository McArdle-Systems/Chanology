import SwiftUI
import SwiftData
import BackgroundTasks
import UserNotifications

@main
struct ChanologyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([WatchedThread.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(sharedModelContainer)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                BoardsView()
            }
            .tabItem { Label("Boards", systemImage: "list.bullet") }

            NavigationStack {
                WatchListView()
            }
            .tabItem { Label("Watching", systemImage: "bell") }
        }
    }
}
