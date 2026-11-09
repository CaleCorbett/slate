import SwiftUI
import AppKit

public struct SlateColors {
    public static let bg = Color(nsColor: NSColor(name: "slateBg") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.145, green: 0.145, blue: 0.145, alpha: 1.0) // #252525
            : NSColor(red: 0.918, green: 0.918, blue: 0.918, alpha: 1.0) // #EAEAEA
    })

    public static let cardToday = Color(nsColor: NSColor(name: "slateCardToday") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1.0) // #1A1A1A
            : NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)       // #FFFFFF
    })

    public static let cardNext = Color(nsColor: NSColor(name: "slateCardNext") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.082, green: 0.082, blue: 0.082, alpha: 1.0) // #151515
            : NSColor(red: 0.984, green: 0.973, blue: 0.937, alpha: 1.0) // #FBF8EF
    })

    public static let cardSomeday = Color(nsColor: NSColor(name: "slateCardSomeday") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1.0) // #111111
            : NSColor(red: 0.992, green: 0.961, blue: 0.902, alpha: 1.0) // #FDF5E6
    })

    public static let primary = Color(nsColor: NSColor(name: "slatePrimary") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            : NSColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1.0) // #111111
    })

    public static let primaryInverted = Color(nsColor: NSColor(name: "slatePrimaryInverted") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1.0)
            : NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    })

    public static let secondary = Color(nsColor: NSColor(name: "slateSecondary") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.631, green: 0.631, blue: 0.631, alpha: 1.0) // #A1A1A1
            : NSColor(red: 0.467, green: 0.467, blue: 0.467, alpha: 1.0) // #777777
    })

    public static let settingsBg = Color(nsColor: NSColor(name: "slateSettingsBg") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.184, green: 0.184, blue: 0.184, alpha: 1.0) // #2F2F2F
            : NSColor(red: 0.882, green: 0.882, blue: 0.882, alpha: 1.0) // #E1E1E1
    })

    public static let hair = Color(nsColor: NSColor(name: "slateHair") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.08)
            : NSColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 0.08)
    })

    public static let cardBorder = Color(nsColor: NSColor(name: "slateCardBorder") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.09)
            : NSColor(white: 0.0, alpha: 0.10)
    })
    
    public static func cardBackground(for list: TaskListType) -> Color {
        switch list {
        case .today: return cardToday
        case .next: return cardNext
        case .someday: return cardSomeday
        }
    }
}

