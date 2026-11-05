import SwiftUI
import AppKit

/// Harri brand palette.
enum Brand {
    // Core palette
    static let primary = Color(hex: 0x0088DD)       // blue
    static let navy = Color(hex: 0x002137)          // secondary 1
    static let green = Color(hex: 0x2CE3A0)         // secondary 2
    static let tertiary = Color(hex: 0xF15B2C)      // orange
    static let secondaryText = Color(hex: 0x969BAB)
    static let selectedBackground = Color(hex: 0xE7F3FF)

    // Variants that stay readable as small text in the dropdown.
    // Light value first, dark value second.
    static let linkText = adaptive(light: 0x0077C2, dark: 0x5BB8F0)
    static let urgentText = adaptive(light: 0xC9440F, dark: 0xFF7A4D)
    static let progressText = adaptive(light: 0x0B7A55, dark: 0x2CE3A0)
    static let selectedRow = adaptive(light: 0xE7F3FF, dark: 0x0B3F63)

    /// Menu bar label colour for a tone. The menu bar is greyer than the
    /// dropdown, so these are deeper on light bars than the dropdown shades;
    /// every one keeps at least 4.5:1 contrast on its bar. Plain has none,
    /// so the system draws it in its adaptive menu bar colour.
    static func menuBarText(for tone: Tone, onDarkBar isDark: Bool) -> NSColor? {
        switch tone {
        case .plain: return nil
        case .soon: return NSColor(hex: isDark ? 0x5BB8F0 : 0x005A94)
        case .urgent: return NSColor(hex: isDark ? 0xFF7A4D : 0x9E340A)
        case .progress: return NSColor(hex: isDark ? 0x2CE3A0 : 0x075C40)
        }
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
