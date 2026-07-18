//
//  Live_RailApp.swift
//  Live Rail
//
//  Created by John Thompson on 26/04/2026.
//

import SwiftUI
import UserNotifications

/// Opts the app into showing notifications while it is in the foreground.
/// Without a delegate implementing `willPresent`, iOS silently discards
/// banners posted while the app is on screen — which is exactly when the
/// tracker's poll loop posts them.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    /// Posted when the user taps any of our notifications; ContentView routes
    /// to the tracked journey. Every notification the app produces concerns
    /// the single tracked journey, so no per-notification payload is needed.
    static let journeyTapNotification = Notification.Name("journeyNotificationTapped")

    /// Set when a tap arrives before ContentView has subscribed (cold start —
    /// the tap itself launched the app). ContentView consumes it in onAppear.
    private(set) var pendingJourneyOpen = false

    func consumePendingJourneyOpen() -> Bool {
        let pending = pendingJourneyOpen
        pendingJourneyOpen = false
        return pending
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        await MainActor.run {
            pendingJourneyOpen = true
            NotificationCenter.default.post(name: Self.journeyTapNotification, object: nil)
        }
    }
}

@main
struct Live_RailApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
