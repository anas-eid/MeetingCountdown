# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Harri NextUp (repo, project, scheme and Swift module still named `MeetingCountdown`) is a macOS menu bar app (SwiftUI + AppKit + EventKit, no third-party dependencies) that shows a countdown to the next calendar meeting, with a dropdown agenda, overlap/conflict display, join-link buttons (Google Meet, Zoom, Teams) and "starting soon" notifications. It runs as an agent app (`LSUIElement = YES`), is sandboxed with the calendars entitlement, and targets macOS 14.6.

## Build and run

There is no package manager or linter. Build with Xcode or:

```bash
xcodebuild -project MeetingCountdown.xcodeproj -scheme MeetingCountdown -configuration Debug build
```

Run the unit tests (all of them, or one with `-only-testing`):

```bash
xcodebuild test -project MeetingCountdown.xcodeproj -scheme MeetingCountdown
```

```bash
xcodebuild test -project MeetingCountdown.xcodeproj -scheme MeetingCountdown -only-testing:MeetingCountdownTests/MeetingEngineTests/testBackToBackMeetingDoesNotTakeOver
```

The product is `Harri NextUp.app` (bundle ID `com.harri.nextup`), but `PRODUCT_MODULE_NAME` is pinned to `MeetingCountdown`, so tests use `@testable import MeetingCountdown`. The tests are hosted in the app; `AppDelegate` skips the status item and permission prompts when `XCTestConfigurationFilePath` is set. Both targets sign with "Sign to Run Locally" (`CODE_SIGN_IDENTITY = "-"`) because this Mac has no development certificate. Release builds have Hardened Runtime on. The target defaults to `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so even `Meeting`'s methods are main-actor isolated; don't mark helpers `nonisolated` unless everything they touch is too.

The project uses a file-system-synchronized group, so new `.swift` files placed in `MeetingCountdown/` are picked up without editing `project.pbxproj`. Info.plist keys (e.g. `NSCalendarsFullAccessUsageDescription`, `LSUIElement`) are set as `INFOPLIST_KEY_*` build settings, not in a plist file.

The app icon is drawn by `Tools/draw_icon.swift` (Core Graphics, run with `swift Tools/draw_icon.swift out.png`). Resize its 1024px output with `sips -z` into the ten `icon_*.png` slots in `Assets.xcassets/AppIcon.appiconset`. `Tools/` sits outside the synchronized source folder, so it is not compiled into the app.

Calendars are read through EventKit, so Google calendars only appear if the account is added in System Settings > Internet Accounts.

Files using `@Published`/`ObservableObject` must `import Combine` explicitly; importing SwiftUI alone fails to build with this project's settings.

## Entry point

The UI shell is AppKit, not `MenuBarExtra`. `MeetingCountdownApp.swift` has an empty SwiftUI `Settings` scene (SwiftUI needs one scene) whose Settings command is rerouted to `AppDelegate`. `AppDelegate` owns the three shared objects, the status item, the preferences window (an `NSWindow` hosting `PreferencesView`) and the About panel. It switches the activation policy to `.regular` while preferences are open and back to `.accessory` when the window closes. SwiftUI's `openSettings` doesn't work from the AppKit popover, so `MenuView` takes `openPreferences`/`openAbout` closures instead.

`StatusItemController` owns the `NSStatusItem` and an `NSPopover` hosting `MenuView`. The label is the button's `attributedTitle`. The menu bar's light/dark look follows the wallpaper, not the system appearance, so the controller reads the button's `effectiveAppearance` (and observes it with KVO) to choose the tone shade from `Brand.menuBarText(for:onDarkBar:)`. Each tone (soon = blue, urgent = orange, progress = green) has a deep shade for light bars and a bright one for dark bars, both at least 4.5:1 on a gray menu bar. The plain tone has no colour, so the system draws it in its adaptive menu bar colour. `Brand.swift` holds the Harri palette; its `linkText`/`urgentText`/`progressText` shades are tuned for the dropdown's white background and are too light for the menu bar, which is why the menu bar has its own shades.

## Architecture

Data flows one way: `AppSettings` → `CalendarService` → `MeetingEngine` → views. All three are `@MainActor ObservableObject`s.

- **`AppSettings`**: every preference is a `@Published` property persisted to `UserDefaults` in `didSet`, with defaults in `init`. Add new settings the same way (key in `SettingsKey`, default in `init`). For the colour thresholds (`soonMinutes`, `urgentMinutes`), `0` means off. `excludedCalendarIDs` is a deny-list; `hasStoredCalendarSelection` tells whether it has ever been written.
- **`CalendarService`**: owns the `EKEventStore`, access state and the calendar list. `refresh()` fetches events from 12 hours ago to the end of tomorrow, applies the filters (all-day, cancelled, declined-by-me, excluded calendars) and maps them to `Meeting`s. On first run it excludes subscription and birthday calendars. It refreshes itself on `.EKEventStoreChanged`.
- **`MeetingEngine`**: the core logic. `tick()` recomputes everything (today's visible meetings, tomorrow's first meeting, the chosen meeting's `Display`, the conflict group, notifications) and reschedules itself with a one-shot timer: 1s while the countdown shows seconds, 5s otherwise, 15s when idle. It also re-ticks on calendar, access and settings changes and on wake, clock change and time-zone change, and forces a calendar refresh every 5 minutes as a safety net. The rules for which meeting the bar shows (running meeting vs. an overlapping one starting within `headsUp`) are documented on the class; `takeOverOnlyWhenOverlapping` toggles the back-to-back behaviour. `pick(from:at:)`, `makeDisplay(_:in:at:rules:)`, `format` and `usesClock` are static and pure: they take the current time and a `DisplayRules` snapshot of the thresholds instead of reading `AppSettings`, which is what the unit tests exercise.
- **`Models.swift`**: `Meeting` (id is `calendarItemIdentifier|startTimestamp`, so recurring instances are distinct) and `LinkDetector`, a single regex that scans the event URL, location and notes in that order for a join link.
- **Views**: `MenuView` is the dropdown (agenda or calendar-access card, plus Refresh/Preferences/Quit rows with keyboard shortcuts). `PreferencesView` is the settings form, including the per-calendar include toggles and launch-at-login via `ServiceManagement`.

Notifications are posted immediately (`trigger: nil`) from `tick()` when a meeting enters the `notifyMinutes` window. The `notified` set prevents repeats and is pruned to meetings that are still live.
