import XCTest
import SwiftUI
@testable import MeetingCountdown

/// Tests for the pure parts of `MeetingEngine`: choosing the meeting, the
/// display it produces, and time formatting.
final class MeetingEngineTests: XCTestCase {
    /// 10:00 on a fixed day; every test works in minutes from here.
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private let rules = DisplayRules(soonMinutes: 10, urgentMinutes: 2, format: .adaptive)

    private func at(_ minutes: Double) -> Date {
        base.addingTimeInterval(minutes * 60)
    }

    private func meeting(_ id: String, from start: Double, to end: Double) -> Meeting {
        Meeting(
            id: id,
            title: id,
            start: at(start),
            end: at(end),
            attendeeCount: 0,
            joinLink: nil,
            calendarColor: .blue
        )
    }

    private func sorted(_ meetings: [Meeting]) -> [Meeting] {
        meetings.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    // MARK: - Choosing the meeting

    func testUpcomingMeetingsAreOrderedByStartTimeOnly() {
        let long = meeting("long", from: 30, to: 120)
        let short = meeting("short", from: 45, to: 50)
        let picked = MeetingEngine.pick(from: sorted([short, long]), at: at(0))
        XCTAssertEqual(picked?.id, "long", "The earliest start wins, even if another meeting ends sooner")
    }

    func testOverlappingMeetingTakesOverTenMinutesBeforeItStarts() {
        let running = meeting("running", from: 0, to: 60)
        let next = meeting("next", from: 30, to: 90)
        let list = sorted([running, next])

        XCTAssertEqual(MeetingEngine.pick(from: list, at: at(19))?.id, "running", "11 min before: no takeover yet")
        XCTAssertEqual(MeetingEngine.pick(from: list, at: at(20))?.id, "next", "Exactly 10 min before: takes over")
        XCTAssertEqual(MeetingEngine.pick(from: list, at: at(29))?.id, "next")
    }

    func testBarReturnsToEarliestRunningMeetingOnceOverlapStarts() {
        let running = meeting("running", from: 0, to: 60)
        let next = meeting("next", from: 30, to: 90)
        let picked = MeetingEngine.pick(from: sorted([running, next]), at: at(31))
        XCTAssertEqual(picked?.id, "running", "Both are running, so the earliest one shows")
    }

    func testBackToBackMeetingDoesNotTakeOver() {
        let running = meeting("running", from: 0, to: 60)
        let next = meeting("next", from: 60, to: 90)
        let picked = MeetingEngine.pick(from: sorted([running, next]), at: at(55), takeOverOnlyWhenOverlapping: true)
        XCTAssertEqual(picked?.id, "running")
    }

    func testBackToBackMeetingTakesOverWhenOverlapIsNotRequired() {
        let running = meeting("running", from: 0, to: 60)
        let next = meeting("next", from: 60, to: 90)
        let picked = MeetingEngine.pick(from: sorted([running, next]), at: at(55), takeOverOnlyWhenOverlapping: false)
        XCTAssertEqual(picked?.id, "next")
    }

    func testNothingToPickWhenAllMeetingsHaveEnded() {
        XCTAssertNil(MeetingEngine.pick(from: [], at: at(0)))
    }

    // MARK: - Tone

    private func tone(startingIn minutes: Double, rules: DisplayRules? = nil) -> Tone {
        let m = meeting("m", from: minutes, to: minutes + 30)
        return MeetingEngine.makeDisplay(m, in: [m], at: at(0), rules: rules ?? self.rules).tone
    }

    private func tone(runningWithMinutesLeft left: Double) -> Tone {
        let m = meeting("m", from: -30, to: left)
        return MeetingEngine.makeDisplay(m, in: [m], at: at(0), rules: rules).tone
    }

    func testPlainAboveSoonThreshold() {
        XCTAssertEqual(tone(startingIn: 11), .plain)
    }

    func testSoonAtOrUnderTenMinutes() {
        XCTAssertEqual(tone(startingIn: 10), .soon)
        XCTAssertEqual(tone(startingIn: 3), .soon)
    }

    func testUrgentAtOrUnderTwoMinutesToStart() {
        XCTAssertEqual(tone(startingIn: 2), .urgent)
        XCTAssertEqual(tone(startingIn: 0.5), .urgent)
    }

    func testProgressWhileRunning() {
        XCTAssertEqual(tone(runningWithMinutesLeft: 30), .progress)
    }

    func testUrgentInLastFiveMinutesOfRunningMeeting() {
        XCTAssertEqual(tone(runningWithMinutesLeft: 5), .urgent)
        XCTAssertEqual(tone(runningWithMinutesLeft: 1), .urgent)
    }

    func testThresholdsSetToZeroAreOff() {
        let off = DisplayRules(soonMinutes: 0, urgentMinutes: 0, format: .adaptive)
        XCTAssertEqual(tone(startingIn: 1, rules: off), .plain)
    }

    // MARK: - Display text

    func testRunningMeetingShowsTimeLeft() {
        let m = meeting("m", from: -18, to: 42)
        let display = MeetingEngine.makeDisplay(m, in: [m], at: at(0), rules: rules)
        XCTAssertEqual(display.timeText, "42m left")
        XCTAssertFalse(display.showsSeconds)
    }

    func testUnderFiveMinutesShowsMinutesAndSeconds() {
        // Built from whole seconds; fractional minutes could round up to 4:11.
        let m = Meeting(id: "m", title: "m", start: base.addingTimeInterval(250), end: at(30),
                        attendeeCount: 0, joinLink: nil, calendarColor: .blue)
        let display = MeetingEngine.makeDisplay(m, in: [m], at: at(0), rules: rules)
        XCTAssertEqual(display.timeText, "4:10")
        XCTAssertTrue(display.showsSeconds)
    }

    func testRunningUnderFiveMinutesShowsMinutesAndSecondsLeft() {
        let m = meeting("m", from: -30, to: 1.5)
        let display = MeetingEngine.makeDisplay(m, in: [m], at: at(0), rules: rules)
        XCTAssertEqual(display.timeText, "1:30 left")
    }

    func testExtraCountCountsOverlappingMeetings() {
        let a = meeting("a", from: 5, to: 35)
        let b = meeting("b", from: 20, to: 50)
        let c = meeting("c", from: 60, to: 90)
        let display = MeetingEngine.makeDisplay(a, in: [a, b, c], at: at(0), rules: rules)
        XCTAssertEqual(display.extraCount, 1)
    }

    // MARK: - Formatting

    func testAdaptiveFormat() {
        XCTAssertEqual(MeetingEngine.format(42 * 60, mode: .adaptive), "42m")
        XCTAssertEqual(MeetingEngine.format(5 * 60, mode: .adaptive), "5m")
        XCTAssertEqual(MeetingEngine.format(4 * 60 + 59, mode: .adaptive), "4:59")
        XCTAssertEqual(MeetingEngine.format(90, mode: .adaptive), "1:30")
    }

    func testMinutesRoundUpAndShowHours() {
        XCTAssertEqual(MeetingEngine.format(61, mode: .minutes), "2m")
        XCTAssertEqual(MeetingEngine.format(20, mode: .minutes), "1m")
        XCTAssertEqual(MeetingEngine.format(60 * 60, mode: .minutes), "1h")
        XCTAssertEqual(MeetingEngine.format(61 * 60, mode: .minutes), "1h 1m")
    }

    func testClockFormat() {
        XCTAssertEqual(MeetingEngine.format(42 * 60, mode: .clock), "42:00")
        XCTAssertEqual(MeetingEngine.format(3_700, mode: .clock), "1:01:40")
    }

    func testFormatNeverGoesNegative() {
        XCTAssertEqual(MeetingEngine.format(-5, mode: .adaptive), "0:00")
    }
}
