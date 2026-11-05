import SwiftUI
import EventKit
import ServiceManagement

struct PreferencesView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var calendar: CalendarService
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Menu bar") {
                Toggle("Show meeting title", isOn: $settings.showTitle)

                HStack {
                    Text("Max title length")
                    Slider(
                        value: Binding(
                            get: { Double(settings.maxTitleLength) },
                            set: { settings.maxTitleLength = Int($0) }
                        ),
                        in: 8...40, step: 1
                    )
                    Text("\(settings.maxTitleLength)")
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                }
                .disabled(!settings.showTitle)

                Picker("Countdown format", selection: $settings.countdownFormat) {
                    ForEach(CountdownFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
            }

            Section("Alerts") {
                Picker(selection: $settings.soonMinutes) {
                    Text("Off").tag(0)
                    ForEach([5, 10, 15], id: \.self) { Text("\($0) minutes").tag($0) }
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(Brand.primary).frame(width: 10, height: 10)
                        Text("Turn blue at")
                    }
                }
                Picker(selection: $settings.urgentMinutes) {
                    Text("Off").tag(0)
                    ForEach([1, 2, 5], id: \.self) { Text("\($0) minutes").tag($0) }
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(Brand.tertiary).frame(width: 10, height: 10)
                        Text("Turn orange at")
                    }
                }
                Toggle("Send a notification", isOn: $settings.notificationsEnabled)
                Picker("Notify", selection: $settings.notifyMinutes) {
                    ForEach([1, 2, 5, 10], id: \.self) { Text("\($0) min before").tag($0) }
                }
                .disabled(!settings.notificationsEnabled)
            }

            Section("Calendars and events") {
                ForEach(calendar.calendars, id: \.calendarIdentifier) { cal in
                    Toggle(isOn: binding(for: cal)) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(color(for: cal))
                                .frame(width: 10, height: 10)
                            Text(cal.title)
                            Text(cal.source.title)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle("Hide declined events", isOn: $settings.hideDeclined)
                Toggle("Ignore all-day events", isOn: $settings.ignoreAllDay)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
        .tint(Brand.primary)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            calendar.refresh()
        }
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
        .onChange(of: settings.hideDeclined) { _, _ in calendar.refresh() }
        .onChange(of: settings.ignoreAllDay) { _, _ in calendar.refresh() }
        .onChange(of: settings.notificationsEnabled) { _, enabled in
            if enabled { MeetingEngine.requestNotificationAuthorization() }
        }
    }

    private func binding(for cal: EKCalendar) -> Binding<Bool> {
        let id = cal.calendarIdentifier
        return Binding(
            get: { !settings.excludedCalendarIDs.contains(id) },
            set: { included in
                if included {
                    settings.excludedCalendarIDs.remove(id)
                } else {
                    settings.excludedCalendarIDs.insert(id)
                }
                calendar.refresh()
            }
        )
    }

    private func color(for cal: EKCalendar) -> Color {
        let cgColor: CGColor? = cal.cgColor
        return cgColor.map { Color(cgColor: $0) } ?? Color.accentColor
    }
}
