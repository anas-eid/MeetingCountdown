import AppKit
import SwiftUI
import Combine

/// The menu bar item and its dropdown.
///
/// This is AppKit rather than `MenuBarExtra` because the label needs the menu
/// bar's real appearance to pick a readable tone colour. That appearance
/// follows the wallpaper, not the system light or dark setting, and only the
/// status bar button reports it.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let engine: MeetingEngine
    private let calendar: CalendarService
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?

    init(engine: MeetingEngine,
         calendar: CalendarService,
         settings: AppSettings,
         openPreferences: @escaping () -> Void,
         openAbout: @escaping () -> Void) {
        self.engine = engine
        self.calendar = calendar
        self.settings = settings
        super.init()

        let menu = MenuView(
            engine: engine,
            calendar: calendar,
            openPreferences: { [weak self] in
                self?.popover.performClose(nil)
                openPreferences()
            },
            openAbout: { [weak self] in
                self?.popover.performClose(nil)
                openAbout()
            }
        )
        let host = NSHostingController(rootView: menu)
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            // Fires when the wallpaper or system appearance flips the bar.
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updateLabel() }
            }
        }

        // Published values change before they are stored, so hop to the next
        // run loop turn before reading them.
        engine.$current.map { _ in () }
            .merge(with: calendar.$access.map { _ in () },
                   settings.objectWillChange.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateLabel() }
            .store(in: &cancellables)

        updateLabel()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        calendar.refresh()
        engine.tick()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Key window, so the dropdown's ⌘ shortcuts work.
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - Label

    private func updateLabel() {
        guard let button = statusItem.button else { return }

        if calendar.access != .granted {
            showIcon("calendar.badge.exclamationmark", on: button)
        } else if let display = engine.current {
            button.image = nil
            button.attributedTitle = title(for: display, on: button)
        } else {
            showIcon("calendar", on: button)
        }
    }

    private func showIcon(_ symbol: String, on button: NSStatusBarButton) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Meeting Countdown")
        image?.isTemplate = true
        button.image = image
        button.title = ""
    }

    /// "Title · 8m" (+N for overlapping meetings). The plain tone has no colour,
    /// so the menu bar draws it in its own adaptive text colour. The other
    /// tones are coloured as a whole, in a shade that keeps at least 4.5:1
    /// contrast on the bar the label is actually sitting on.
    private func title(for display: Display, on button: NSStatusBarButton) -> NSAttributedString {
        var parts: [String] = []
        if settings.showTitle {
            parts.append(truncated(display.meeting.title))
        }
        parts.append(display.timeText)
        var text = parts.joined(separator: " · ")
        if display.extraCount > 0 {
            text += " +\(display.extraCount)"
        }

        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        let isDark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua

        var attributes: [NSAttributedString.Key: Any] = [:]
        if let color = Self.color(for: display.tone, onDarkBar: isDark) {
            attributes[.font] = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
            attributes[.foregroundColor] = color
        } else {
            attributes[.font] = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    private func truncated(_ title: String) -> String {
        let limit = settings.maxTitleLength
        guard title.count > limit else { return title }
        return title.prefix(max(1, limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Dark shades for a light bar, bright ones for a dark bar.
    private static func color(for tone: Tone, onDarkBar isDark: Bool) -> NSColor? {
        switch tone {
        case .plain: return nil
        case .amber: return isDark ? rgb(0xFFB340) : rgb(0x8A4500)
        case .red: return isDark ? rgb(0xFF6961) : rgb(0xB0161D)
        case .green: return isDark ? rgb(0x32D74B) : rgb(0x0B6128)
        }
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }
}
