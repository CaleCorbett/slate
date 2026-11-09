import SwiftUI
import AppKit

public struct SlateTheme {
    public static let cardRadius: CGFloat = 18
    public static let rowRadius: CGFloat = 11
    public static let btnRadius: CGFloat = 10
    public static let checkboxSize: CGFloat = 21
    public static let checkboxRadius: CGFloat = 7

    public static let easeSpring = Animation.spring(response: 0.34, dampingFraction: 0.84)
    public static let snapSpring = Animation.spring(response: 0.24, dampingFraction: 0.72)
    public static let expandSpring = Animation.spring(response: 0.38, dampingFraction: 0.82)
}

public typealias GrindTheme = SlateTheme

public enum GeistWeight {
    case regular
    case medium
    case semiBold
    case bold
    case mono
    
    var fontName: String {
        switch self {
        case .regular: return "Geist-Regular"
        case .medium: return "Geist-Medium"
        case .semiBold: return "Geist-SemiBold"
        case .bold: return "Geist-Bold"
        case .mono: return "GeistMono-Regular"
        }
    }
    
    var systemWeight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semiBold: return .semibold
        case .bold: return .bold
        case .mono: return .regular
        }
    }
}

public extension Font {
    static func geist(_ weight: GeistWeight = .regular, size: CGFloat) -> Font {
        .custom(weight.fontName, size: size)
    }
}

/// Linear / Raycast style monospace keycap pill
public struct KeycapBadge: View {
    public let text: String
    public var inverted: Bool = false
    
    public init(_ text: String, inverted: Bool = false) {
        self.text = text
        self.inverted = inverted
    }
    
    public var body: some View {
        Text(text)
            .font(.geist(.mono, size: 10))
            .foregroundColor(inverted ? SlateColors.primaryInverted.opacity(0.85) : SlateColors.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(inverted ? SlateColors.primaryInverted.opacity(0.16) : SlateColors.hair)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        inverted ? SlateColors.primaryInverted.opacity(0.22) : SlateColors.cardBorder,
                        lineWidth: 0.75
                    )
            )
    }
}
