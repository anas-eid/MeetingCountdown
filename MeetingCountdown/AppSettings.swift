import Foundation
import Combine
import SwiftUI

enum CountdownFormat: String, CaseIterable, Identifiable {
    case adaptive, minutes, clock

    var id: String { rawValue }

    var label: String {
        switch self {
        case .adaptive: return "Minutes, then m:ss in the last 5 minutes"
        case .minutes: return "Always minutes"
        case .clock: return "Always m:ss"
        }
    }
}

private enum SettingsKey {
    static let showTitle = "showTitle"
    static let maxTitleLength = "maxTitleLength"
    static let soonMinutes = "soonMinutes"
    static let urgentMinutes = "urgentMinutes"
    static let notificationsEnabled = "notificationsEnabled"
    static let notifyMinutes = "notifyMinutes"
    static let hideDeclined = "hideDeclined"
    static let ignoreAllDay = "ignoreAllDay"
    static let countdownFormat = "countdownFormat"
    static let excludedCalendarIDs = "excludedCalendarIDs"
}

/// User preferences, saved to UserDefaults as they change.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var showTitle: Bool {
        didSet { defaults.set(showTitle, forKey: SettingsKey.showTitle) }
    }
    @Published var maxTitleLength: Int {
        didSet { defaults.set(maxTitleLength, forKey: SettingsKey.maxTitleLength) }
    }
    /// 0 means off.
    @Published var soonMinutes: Int {
        didSet { defaults.set(soonMinutes, forKey: SettingsKey.soonMinutes) }
    }
    /// 0 means off.
    @Published var urgentMinutes: Int {
        didSet { defaults.set(urgentMinutes, forKey: SettingsKey.urgentMinutes) }
    }
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: SettingsKey.notificationsEnabled) }
    }
    @Published var notifyMinutes: Int {
        didSet { defaults.set(notifyMinutes, forKey: SettingsKey.notifyMinutes) }
    }
    @Published var hideDeclined: Bool {
        didSet { defaults.set(hideDeclined, forKey: SettingsKey.hideDeclined) }
    }
    @Published var ignoreAllDay: Bool {
        didSet { defaults.set(ignoreAllDay, forKey: SettingsKey.ignoreAllDay) }
    }
    @Published var countdownFormat: CountdownFormat {
        didSet { defaults.set(countdownFormat.rawValue, forKey: SettingsKey.countdownFormat) }
    }
    @Published var excludedCalendarIDs: Set<String> {
        didSet { defaults.set(Array(excludedCalendarIDs), forKey: SettingsKey.excludedCalendarIDs) }
    }

    /// False until the user (or first launch) has saved a calendar selection.
    var hasStoredCalendarSelection: Bool {
        defaults.object(forKey: SettingsKey.excludedCalendarIDs) != nil
    }

    init() {
        let d = UserDefaults.standard
        showTitle = d.object(forKey: SettingsKey.showTitle) as? Bool ?? true
        maxTitleLength = d.object(forKey: SettingsKey.maxTitleLength) as? Int ?? 18
        soonMinutes = d.object(forKey: SettingsKey.soonMinutes) as? Int ?? 10
        urgentMinutes = d.object(forKey: SettingsKey.urgentMinutes) as? Int ?? 2
        notificationsEnabled = d.object(forKey: SettingsKey.notificationsEnabled) as? Bool ?? true
        notifyMinutes = d.object(forKey: SettingsKey.notifyMinutes) as? Int ?? 1
        hideDeclined = d.object(forKey: SettingsKey.hideDeclined) as? Bool ?? true
        ignoreAllDay = d.object(forKey: SettingsKey.ignoreAllDay) as? Bool ?? true
        countdownFormat = CountdownFormat(rawValue: d.string(forKey: SettingsKey.countdownFormat) ?? "") ?? .adaptive
        excludedCalendarIDs = Set(d.stringArray(forKey: SettingsKey.excludedCalendarIDs) ?? [])
    }
}
