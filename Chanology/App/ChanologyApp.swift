import SwiftUI
import SwiftData
import BackgroundTasks
import UserNotifications

@main
struct ChanologyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([WatchedThread.self, MyPosts.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(sharedModelContainer)
                .task {
                    // Give the refresh service access to SwiftData
                    ForegroundRefreshService.shared.modelContainer = sharedModelContainer
                    ForegroundRefreshService.shared.startPolling()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                ForegroundRefreshService.shared.startPolling()
            case .background:
                ForegroundRefreshService.shared.stopPolling()
                BackgroundRefreshHandler.scheduleRefresh()
            default:
                break
            }
        }
    }
}

@Observable
@MainActor
class NavigationCoordinator {
    static let shared = NavigationCoordinator()

    var selectedTab: Int = 0
    var pendingThread: PendingThread?

    struct PendingThread {
        let board: String
        let threadNo: Int
        let subject: String
    }

    func openThread(board: String, threadNo: Int, subject: String) {
        pendingThread = PendingThread(board: board, threadNo: threadNo, subject: subject)
        selectedTab = 1  // Switch to Watching tab
    }
}

struct ContentView: View {
    @State private var coordinator = NavigationCoordinator.shared

    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            NavigationStack {
                BoardsView()
            }
            .tabItem { Label("Boards", systemImage: "list.bullet") }
            .tag(0)

            NavigationStack {
                WatchListView()
            }
            .tabItem { Label("Watching", systemImage: "bell") }
            .tag(1)
        }
    }
}
