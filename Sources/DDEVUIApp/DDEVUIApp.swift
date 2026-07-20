import SwiftUI

@main
struct DDEVUIApp: App {
    // B1 — the view model and prerequisite monitor are owned by the App (not ContentView) so the
    // MenuBarExtra scene can share the same live data as the main window.
    @State private var viewModel: ProjectDashboardViewModel
    @State private var prerequisites = PrerequisiteMonitor()
    @State private var dockerDiskViewModel: DockerDiskViewModel

    init() {
        let projectViewModel = ProjectDashboardViewModel(notifier: DDEVUIApp.makeNotifier())
        _viewModel = State(initialValue: projectViewModel)
        // Read the real Task 9 preferences rather than hardcoding the defaults — `viewModel` is
        // already constructed above, so its `PreferencesModel`-backed `preferences` is available
        // here before `ContentView` (and its own preferences plumbing) ever comes into play.
        _dockerDiskViewModel = State(initialValue: DockerDiskViewModel(
            dockerService: DockerSystemService(),
            ddevService: DDEVCommandService(),
            warnThreshold: projectViewModel.preferences.diskWarnThreshold,
            criticalThreshold: projectViewModel.preferences.diskCriticalThreshold
        ))
    }

    var body: some Scene {
        WindowGroup(id: DDEVUIApp.mainWindowID) {
            ContentView(
                viewModel: viewModel,
                prerequisites: prerequisites,
                dockerDiskViewModel: dockerDiskViewModel
            )
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
