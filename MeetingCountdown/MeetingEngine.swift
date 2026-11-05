import Foundation
import Combine
import AppKit
import UserNotifications

enum Phase {
    case upcoming(TimeInterval)   // seconds until it starts
    case running(TimeInterval)    // seconds until it ends
}

/// How the countdown is coloured. See Brand.swift for the actual colours.
///  plain    more than `soonMinutes` away
///  soon     within `soonMinutes` of starting (blue)
///  urgent   within `urgentMinutes` of starting, or the last 5 min of a running meeting (orange)
///  progress a running meeting (green)
enum Tone { case plain, soon, urgent, progress }

/// The settings `makeDisplay` depends on, so it can run without `AppSettings`.
struct DisplayRules {
    /// 0 means off.
    var soonMinutes: Int
    /// 0 means off.
    var urgentMinutes: Int
    var format: CountdownFormat
}

/// Everything the menu bar label and dropdown header need.
struct Display {
    let meeting: Meeting
    let phase: Phase
    let tone: Tone
    let extraCount: Int        // other meetings that overlap this one
    let timeText: String       // "8m", "1:42", "42m left"
    let showsSeconds: Bool
}

/// Decides which meeting the menu bar shows, and keeps the countdown ticking.
///
/// Rules:
///  1. Meetings are ordered by start time only.
///  2. While one is running, the bar shows it (time left) ...
///  3. ... unless another meeting that overlaps it is within `headsUp` of starting.
///     That meeting takes over until it starts, then the bar goes back to the
///     earliest meeting still running.
@MainActor
final class MeetingEngine: ObservableObject {
    @Published private(set) var now = Date()
    @Published private(set) var current: Display?
    @Published private(set) var visibleMeetings: [Meeting] = []
    @Published private(set) var conflictGroup: [Meeting] = []
    @Published private(set) var nextDayMeeting: Meeting?

    /// How early the next meeting takes over the bar while another is running.
    static let headsUp: TimeInterval = 10 * 60
    /// Set to false if a back-to-back meeting should also take over during the last
    /// 10 minutes of the current one (not only an overlapping one).
    static let takeOverOnlyWhenOverlapping = true

    private let calendar: CalendarService
    private let settings: AppSettings
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var notified = Set<String>()
    private var lastRefresh = Date()

    init(calendar: CalendarService, settings: AppSettings) {
        self.calendar = calendar
        self.settings = settings

        // Published values change before they are stored, so hop to the next
        // run loop turn before reading them.
        calendar.$meetings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.tick() }
            .store(in: &cancellables)

        calendar.$access
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.tick() }
            .store(in: &cancellables)

        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.tick() }
            .store(in: &cancellables)

        // All observers below use the main queue.
        let refreshAndTick: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.calendar.refresh()
                self?.tick()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refreshAndTick)
        NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main, using: refreshAndTick)
        NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main, using: refreshAndTick)

        tick()
    }

    // MARK: - Ticking

    func tick() {
        now = Date()

        // Safety net in case an EventKit change notification is missed.
        if now.timeIntervalSince(lastRefresh) > 300 {
            lastRefresh = now
            calendar.refresh()
        }

        let live = calendar.meetings
            .filter { $0.end > now }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }

        let startOfToday = Calendar.current.startOfDay(for: now)
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(86400)

        let today = live.filter { $0.start < endOfToday }
        visibleMeetings = today
        nextDayMeeting = live.first { $0.start >= endOfToday }

        if calendar.access == .granted, let chosen = Self.pick(from: today, at: now) {
            let rules = DisplayRules(
                soonMinutes: settings.soonMinutes,
                urgentMinutes: settings.urgentMinutes,
                format: settings.countdownFormat
            )
            let display = Self.makeDisplay(chosen, in: today, at: now, rules: rules)
            current = display
            conflictGroup = today.filter { $0.overlaps(chosen) }
        } else {
            current = nil
            conflictGroup = []
        }

        notifyIfNeeded(live)
        scheduleNextTick()
    }

    private func scheduleNextTick() {
        timer?.invalidate()
        let interval: TimeInterval
        if let current {
            interval = current.showsSeconds ? 1 : 5
        } else {
            interval = 15
        }
        let newTimer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            // Scheduled on the main run loop below.
            MainActor.assumeIsolated { self?.tick() }
        }
        newTimer.tolerance = interval * 0.1
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    // MARK: - Choosing the meeting

    /// Pure, so tests can call it with fake meetings. `list` must be sorted by start.
    /// `takeOverOnlyWhenOverlapping` defaults to the static setting of the same name.
    static func pick(
        from list: [Meeting],
        at now: Date,
        takeOverOnlyWhenOverlapping: Bool? = nil
    ) -> Meeting? {
        let onlyWhenOverlapping = takeOverOnlyWhenOverlapping ?? Self.takeOverOnlyWhenOverlapping
        let running = list.filter { $0.isRunning(at: now) }
        let upcoming = list.filter { $0.start > now }

        guard let firstRunning = running.first else { return upcoming.first }

        if let next = upcoming.first, next.start.timeIntervalSince(now) <= headsUp {
            let overlapsRunning = running.contains { next.start < $0.end }
            if overlapsRunning || !onlyWhenOverlapping {
                return next
            }
        }
        return firstRunning
    }

    static func makeDisplay(
        _ meeting: Meeting,
        in list: [Meeting],
        at now: Date,
        rules: DisplayRules
    ) -> Display {
        let mode = rules.format
        let phase: Phase
        let seconds: TimeInterval
        var isRunning = false

        if meeting.isRunning(at: now) {
            seconds = meeting.end.timeIntervalSince(now)
            phase = .running(seconds)
            isRunning = true
        } else {
            seconds = meeting.start.timeIntervalSince(now)
            phase = .upcoming(seconds)
        }

        let tone: Tone
        switch phase {
        case .upcoming(let s):
            if rules.urgentMinutes > 0 && s <= Double(rules.urgentMinutes) * 60 {
                tone = .urgent
            } else if rules.soonMinutes > 0 && s <= Double(rules.soonMinutes) * 60 {
                tone = .soon
            } else {
                tone = .plain
            }
        case .running(let left):
            tone = left <= 5 * 60 ? .urgent : .progress
        }

        let base = format(seconds, mode: mode)
        let extra = list.filter { $0.id != meeting.id && $0.overlaps(meeting) }.count

        return Display(
            meeting: meeting,
            phase: phase,
            tone: tone,
            extraCount: extra,
            timeText: isRunning ? "\(base) left" : base,
            showsSeconds: usesClock(seconds, mode: mode)
        )
    }

    // MARK: - Formatting

    static func usesClock(_ seconds: TimeInterval, mode: CountdownFormat) -> Bool {
        switch mode {
        case .adaptive: return seconds < 5 * 60
        case .minutes: return false
        case .clock: return true
        }
    }

    static func format(_ seconds: TimeInterval, mode: CountdownFormat) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        if usesClock(seconds, mode: mode) {
            if total >= 3600 {
                return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            }
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        let minutes = max(1, Int((Double(total) / 60).rounded(.up)))
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        return "\(minutes)m"
    }

    // MARK: - Notifications

    static func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyIfNeeded(_ list: [Meeting]) {
        guard settings.notificationsEnabled else { return }
        let lead = TimeInterval(settings.notifyMinutes * 60)

        for meeting in list where meeting.start > now
            && meeting.start.timeIntervalSince(now) <= lead
            && !notified.contains(meeting.id) {
            notified.insert(meeting.id)

            let content = UNMutableNotificationContent()
            content.title = meeting.title
            content.body = "Starting soon"
            content.sound = .default
            let request = UNNotificationRequest(identifier: meeting.id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }

        let liveIDs = Set(list.map { $0.id })
        notified = notified.intersection(liveIDs)
    }
}
