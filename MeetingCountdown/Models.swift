import Foundation
import SwiftUI

enum JoinProvider: String {
    case googleMeet = "Google Meet"
    case zoom = "Zoom"
    case teams = "Microsoft Teams"
}

struct JoinLink {
    let url: URL
    let provider: JoinProvider
}

struct Meeting: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let attendeeCount: Int
    let joinLink: JoinLink?
    let calendarColor: Color

    func isRunning(at now: Date) -> Bool { start <= now && now < end }

    /// True when the two meetings share any time.
    func overlaps(_ other: Meeting) -> Bool { start < other.end && other.start < end }
}

/// Finds a Google Meet, Zoom or Teams link in an event's URL, location or notes.
enum LinkDetector {
    private static let pattern =
        #"https?://(?:meet\.google\.com/[a-z0-9\-]+(?:\?[^\s"<>)]*)?|[a-z0-9.\-]*zoom\.us/(?:j|my)/[^\s"<>)]+|teams\.microsoft\.com/l/meetup-join/[^\s"<>)]+|teams\.live\.com/meet/[^\s"<>)]+)"#

    private static let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])

    static func find(in texts: [String?]) -> JoinLink? {
        for case let text? in texts {
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  let swiftRange = Range(match.range, in: text) else { continue }
            var candidate = String(text[swiftRange])
            while let last = candidate.last, ".,;:".contains(last) { candidate.removeLast() }
            if let url = URL(string: candidate) {
                return JoinLink(url: url, provider: provider(for: url))
            }
        }
        return nil
    }

    private static func provider(for url: URL) -> JoinProvider {
        let host = url.host?.lowercased() ?? ""
        if host.contains("zoom.us") { return .zoom }
        if host.contains("teams") { return .teams }
        return .googleMeet
    }
}
