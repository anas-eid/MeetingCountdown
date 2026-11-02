import Foundation
import Combine
import EventKit
import SwiftUI

/// Reads events through EventKit. Your Google account must be added in
/// System Settings > Internet Accounts with Calendars switched on.
@MainActor
final class CalendarService: ObservableObject {
    enum Access { case notDetermined, granted, denied }

    @Published private(set) var access: Access = .notDetermined
    @Published private(set) var meetings: [Meeting] = []
    @Published private(set) var calendars: [EKCalendar] = []

    private let store = EKEventStore()
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        updateAccess()

        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        if access == .granted { refresh() }
    }

    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            // The status check below reports the outcome.
        }
        refresh()
    }

    func refresh() {
        updateAccess()
        guard access == .granted else {
            meetings = []
            calendars = []
            return
        }

        calendars = store.calendars(for: .event).sorted {
            ($0.source.title, $0.title) < ($1.source.title, $1.title)
        }
        applyDefaultCalendarSelectionIfNeeded()

        let included = calendars.filter { !settings.excludedCalendarIDs.contains($0.calendarIdentifier) }
        guard !included.isEmpty else {
            meetings = []
            return
        }

        let now = Date()
        let from = now.addingTimeInterval(-12 * 3600)
        let startOfToday = Calendar.current.startOfDay(for: now)
        let to = Calendar.current.date(byAdding: .day, value: 2, to: startOfToday) ?? now.addingTimeInterval(48 * 3600)

        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: included)
        meetings = store.events(matching: predicate)
            .compactMap(makeMeeting)
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    private func updateAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .notDetermined
        default: access = .denied
        }
    }

    /// First launch: leave out holiday and birthday style calendars.
    private func applyDefaultCalendarSelectionIfNeeded() {
        guard !settings.hasStoredCalendarSelection else { return }
        let noisy = calendars.filter { $0.type == .subscription || $0.type == .birthday }
        settings.excludedCalendarIDs = Set(noisy.map { $0.calendarIdentifier })
    }

    private func makeMeeting(from event: EKEvent) -> Meeting? {
        if settings.ignoreAllDay && event.isAllDay { return nil }
        if event.status == .canceled { return nil }

        if settings.hideDeclined,
           let me = event.attendees?.first(where: { $0.isCurrentUser }),
           me.participantStatus == .declined {
            return nil
        }

        guard let start = event.startDate, let end = event.endDate else { return nil }

        let trimmed = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = trimmed.isEmpty ? "Untitled" : trimmed

        let cgColor: CGColor? = event.calendar.cgColor
        let color = cgColor.map { Color(cgColor: $0) } ?? Color.accentColor

        return Meeting(
            id: "\(event.calendarItemIdentifier)|\(start.timeIntervalSince1970)",
            title: title,
            start: start,
            end: end,
            attendeeCount: event.attendees?.count ?? 0,
            joinLink: LinkDetector.find(in: [event.url?.absoluteString, event.location, event.notes]),
            calendarColor: color
        )
    }
}
