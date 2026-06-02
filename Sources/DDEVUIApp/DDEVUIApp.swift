import SwiftUI

@main
struct DDEVUIApp: App {
    // B1 — the view model and prerequisite monitor are owned by the App (not ContentView) so the
    // MenuBarExtra scene can share the same live data as the main window.
    @State private var viewModel: ProjectDashboardViewModel
    @State private var prerequisites = PrerequisiteMonitor()

    init() {
        _viewModel = State(initialValue: ProjectDashboardViewModel(notifier: DDEVUIApp.makeNotifier()))
    }

    var body: some Scene {
        WindowGroup(id: DDEVUIApp.mainWindowID) {
            ContentView(viewModel: viewModel, prerequisites: prerequisites)
                .frame(minWidth: 1040, minHeight: 680)
        }

        // B1 — always-there menu-bar controls: start/stop/launch any project without the window.
        MenuBarExtra("DDEVUI", systemImage: "shippingbox.fill") {
            MenuBarContentView(viewModel: viewModel)
        }
    }

    static let mainWindowID = "ddevui.main"

    private static func makeNotifier() -> NotificationScheduling {
        let scheduler = UserNotificationScheduler()
        scheduler.activateForegroundPresentation()
        return scheduler
    }
}
