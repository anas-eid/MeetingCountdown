import SwiftUI
import AppKit

@main
struct MeetingCountdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar item and both windows are AppKit, owned by AppDelegate.
        // SwiftUI needs at least one scene, so this one stays empty and its
        // Settings command opens the real preferences window instead.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { appDelegate.showPreferences() }
                        .keyboardShortcut(",")
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let settings = AppSettings()
    private lazy var calendar = CalendarService(settings: settings)
    private lazy var engine = MeetingEngine(calendar: calendar, settings: settings)
    private var statusItem: StatusItemController?
    private var preferencesWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside the app; skip the menu bar item and prompts there.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        if settings.notificationsEnabled {
            MeetingEngine.requestNotificationAuthorization()
        }
        statusItem = StatusItemController(
            engine: engine,
            calendar: calendar,
            settings: settings,
            openPreferences: { [weak self] in self?.showPreferences() },
            openAbout: { [weak self] in self?.showAbout() }
        )
    }

    /// The app has no Dock icon, so it becomes a regular app while the
    /// preferences window is open to bring it forward, and drops back to menu
    /// bar only when the window closes.
    func showPreferences() {
        if preferencesWindow == nil {
            let host = NSHostingController(rootView: PreferencesView(settings: settings, calendar: calendar))
            let window = NSWindow(contentViewController: host)
            window.title = "Harri NextUp Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            preferencesWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === preferencesWindow else { return }
        // Built fresh next time, so the form re-reads launch-at-login and calendars.
        preferencesWindow = nil
        NSApp.setActivationPolicy(.accessory)
    }

    /// The standard About panel, which also shows the copyright from Info.plist.
    func showAbout() {
        let credits = NSMutableAttributedString(
            string: "Developed by AnAs\n",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        )
        credits.append(NSAttributedString(
            string: "anas.eid@harri.com",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .link: URL(string: "mailto:anas.eid@harri.com")!,
            ]
        ))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered,
                             range: NSRange(location: 0, length: credits.length))

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
