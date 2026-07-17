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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
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
