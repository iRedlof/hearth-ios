import Testing
import Foundation
@testable import HearthKit

@Suite("House Features Helpers")
struct HouseFeaturesTests {
    @Test("Next trip subtitle - with trip")
    func nextTripSubtitleWithTrip() async throws {
        let now = Date(timeIntervalSince1970: 1700000000) // Nov 14, 2023
        let startDate = Date(timeIntervalSince1970: 1700000000 + 2 * 24 * 3600) // 2 days later (Thu)
        let trip = Trip(
            title: "Lisbon trip",
            startDate: startDate,
            notifyAt: startDate.addingTimeInterval(-4 * 3600) // 4 hours before
        )

        let subtitle = nextTripSubtitle(trips: [trip], now: now)
        #expect(subtitle == "Next: Lisbon trip · Thu")
    }

    @Test("Next trip subtitle - no trips")
    func nextTripSubtitleEmpty() async throws {
        let now = Date()
        let subtitle = nextTripSubtitle(trips: [], now: now)
        #expect(subtitle == "No trips in the next 7 days")
    }

    @Test("Calendar banner state - feature off")
    func calendarBannerFeatureOff() async throws {
        // EKAuthorizationStatus.denied = 2
        let state = calendarBannerState(enabled: false, calendarStatus: 2)
        #expect(state == .hidden)
    }

    @Test("Calendar banner state - feature on, access granted")
    func calendarBannerAccessGranted() async throws {
        // EKAuthorizationStatus.authorized = 3
        let state = calendarBannerState(enabled: true, calendarStatus: 3)
        #expect(state == .hidden)
    }

    @Test("Calendar banner state - feature on, no access")
    func calendarBannerNoAccess() async throws {
        // EKAuthorizationStatus.denied = 2
        let state = calendarBannerState(enabled: true, calendarStatus: 2)
        #expect(state == .needsPermission)
    }

    @Test("Calendar banner state - feature on, not determined")
    func calendarBannerNotDetermined() async throws {
        // EKAuthorizationStatus.notDetermined = 0
        let state = calendarBannerState(enabled: true, calendarStatus: 0)
        #expect(state == .needsPermission)
    }

    @Test("Calendar banner state - feature on, restricted")
    func calendarBannerRestricted() async throws {
        // EKAuthorizationStatus.restricted = 1
        let state = calendarBannerState(enabled: true, calendarStatus: 1)
        #expect(state == .restricted)
    }

    @Test("Notification banner state - feature off")
    func notificationBannerFeatureOff() async throws {
        let state = notificationBannerState(enabled: false, hasNotificationAccess: false)
        #expect(state == .hidden)
    }

    @Test("Notification banner state - feature on, access granted")
    func notificationBannerAccessGranted() async throws {
        let state = notificationBannerState(enabled: true, hasNotificationAccess: true)
        #expect(state == .hidden)
    }

    @Test("Notification banner state - feature on, no access")
    func notificationBannerNoAccess() async throws {
        let state = notificationBannerState(enabled: true, hasNotificationAccess: false)
        #expect(state == .needsPermission)
    }
}
