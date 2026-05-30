import Foundation
import UserNotifications

/// Surfaces background-project command completions as macOS user notifications.
public protocol NotificationScheduling: Sendable {
    /// Requests notification authorization if the app is able to (no-op otherwise). The
    /// system prompts the user at most once regardless of how often this is called.
    func requestAuthorizationIfNeeded() async
    /// Posts a completion notification for a project command.
    func notifyCommandFinished(projectName: String, summary: String, succeeded: Bool) async
}

/// No-op implementation. Used in tests and whenever the process is not a real app bundle
/// (e.g. the `swift build` executable), where `UNUserNotificationCenter` is unavailable.
public struct NoopNotificationScheduler: NotificationScheduling {
    public init() {}
    public func requestAuthorizationIfNeeded() async {}
    public func notifyCommandFinished(projectName: String, summary: String, succeeded: Bool) async {}
}

/// Real implementation backed by `UNUserNotificationCenter`.
///
/// Local notifications need only user authorization — no Push entitlement. They only work
/// inside a real app bundle, so every entry point guards on `Bundle.main.bundleIdentifier`
/// and silently no-ops otherwise, keeping the unbundled `swift build` executable crash-free.
public final class UserNotificationScheduler: NSObject, NotificationScheduling, UNUserNotificationCenterDelegate {
    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    // Internal, not part of the protocol: only the concrete type can wire itself as the
    // delegate. Called from the app's composition root (ContentView, same module).
    func activateForegroundPresentation() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    public func requestAuthorizationIfNeeded() async {
        guard isBundled else { return }
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    public func notifyCommandFinished(projectName: String, summary: String, succeeded: Bool) async {
        guard isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = projectName
        content.body = succeeded ? "\(summary) finished" : "\(summary) failed"
        content.sound = succeeded ? nil : .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // Present banners even when the app is foregrounded — the user may be viewing a
    // different project than the one whose command just finished.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // `.sound` is a no-op for success notifications because their `content.sound` is nil;
        // only failures (which set `.default`) actually play a sound.
        completionHandler([.banner, .sound])
    }
}
