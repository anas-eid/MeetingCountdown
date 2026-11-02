import SwiftUI
import AppKit

/// The dropdown shown when you click the menu bar item.
struct MenuView: View {
    @ObservedObject var engine: MeetingEngine
    @ObservedObject var calendar: CalendarService
    let openPreferences: () -> Void
    let openAbout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if calendar.access == .granted {
                agenda
            } else {
                accessCard
            }

            Divider()

            VStack(spacing: 2) {
                MenuRow(title: "Refresh", shortcut: "⌘R", key: "r") {
                    calendar.refresh()
                    engine.tick()
                }
                MenuRow(title: "About Meeting Countdown") {
                    openAbout()
                }
                MenuRow(title: "Preferences…", shortcut: "⌘,", key: ",") {
                    openPreferences()
                }
                MenuRow(title: "Quit Meeting Countdown", shortcut: "⌘Q", key: "q") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            calendar.refresh()
            engine.tick()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var agenda: some View {
        if let display = engine.current {
            header(display)

            if engine.conflictGroup.count > 1 {
                conflict
            }

            Divider()
            todayList(display)
        } else {
            freeCard
        }
    }

    private func header(_ display: Display) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline(display))
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(toneColor(display.tone))

            Text(display.meeting.title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)

            Text(subtitle(display.meeting))
                .font(.callout)
                .foregroundStyle(.secondary)

            if let link = display.meeting.joinLink {
                Button {
                    NSWorkspace.shared.open(link.url)
                } label: {
                    Label("Join \(link.provider.rawValue)", systemImage: "video.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
            }
        }
    }

    private var conflict: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Conflict · \(engine.conflictGroup.count) meetings overlap")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.orange)

            ForEach(engine.conflictGroup) { meeting in
                HStack(spacing: 8) {
                    Circle().fill(meeting.calendarColor).frame(width: 8, height: 8)
                    Text(meeting.title).fontWeight(.semibold).lineLimit(1)
                    Spacer()
                    Text("\(timeString(meeting.start)) – \(timeString(meeting.end))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    joinButton(meeting)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    private func todayList(_ display: Display) -> some View {
        let all = engine.visibleMeetings
        let shown = Array(all.prefix(8))
        return VStack(alignment: .leading, spacing: 4) {
            Text("Today")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            ForEach(shown) { meeting in
                HStack(spacing: 10) {
                    Circle().fill(meeting.calendarColor).frame(width: 8, height: 8)
                    Text(timeString(meeting.start))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)
                    Text(meeting.title)
                        .fontWeight(meeting.id == display.meeting.id ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer()
                    joinButton(meeting)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(meeting.id == display.meeting.id ? Color.primary.opacity(0.08) : Color.clear)
                )
            }

            if all.count > shown.count {
                Text("+\(all.count - shown.count) more")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var freeCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("You are clear for the day")
                .font(.headline)
            if let next = engine.nextDayMeeting {
                Text("Next up: \(next.title) tomorrow at \(timeString(next.start)).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calendar access is off")
                .font(.headline)
            Text("Allow access, and make sure your Google account is added under System Settings > Internet Accounts with Calendars switched on.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if calendar.access == .notDetermined {
                Button("Allow Calendar Access") {
                    Task { await calendar.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func joinButton(_ meeting: Meeting) -> some View {
        if let link = meeting.joinLink {
            Button("Join") { NSWorkspace.shared.open(link.url) }
                .buttonStyle(.link)
        }
    }

    private func headline(_ display: Display) -> String {
        switch display.phase {
        case .running: return "Now · \(display.timeText)"
        case .upcoming: return "Next up · in \(display.timeText)"
        }
    }

    private func subtitle(_ meeting: Meeting) -> String {
        var text = "\(timeString(meeting.start)) – \(timeString(meeting.end))"
        if meeting.attendeeCount > 1 {
            text += " · \(meeting.attendeeCount) attendees"
        }
        return text
    }

    private func timeString(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func toneColor(_ tone: Tone) -> Color {
        switch tone {
        case .plain: return .secondary
        case .amber: return .orange
        case .red: return .red
        case .green: return .green
        }
    }
}

private struct MenuRow: View {
    let title: String
    var shortcut: String? = nil
    var key: String? = nil
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)

        if let key {
            button.keyboardShortcut(KeyEquivalent(Character(key)), modifiers: .command)
        } else {
            button
        }
    }
}
