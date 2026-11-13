import SwiftUI
import AppKit

public struct StatusToggleView: View {
    let status: TaskStatus
    let onLeftClick: () -> Void
    let onRightClick: (() -> Void)?
    
    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false
    
    public init(status: TaskStatus, action: @escaping () -> Void) {
        self.status = status
        self.onLeftClick = action
        self.onRightClick = nil
    }
    
    public init(status: TaskStatus, onLeftClick: @escaping () -> Void, onRightClick: (() -> Void)? = nil) {
        self.status = status
        self.onLeftClick = onLeftClick
        self.onRightClick = onRightClick
    }
    
    private var sweepDegrees: Double {
        switch status {
        case .incomplete: return 0
        case .inProgress: return 180
        case .completed: return 360
        }
    }
    
    public var body: some View {
        ZStack {
            // Subtle hover fill for incomplete state
            RoundedRectangle(cornerRadius: SlateTheme.checkboxRadius, style: .continuous)
                .fill(status == .incomplete && isHovered ? SlateColors.hair : Color.clear)
                .frame(width: SlateTheme.checkboxSize, height: SlateTheme.checkboxSize)
            
            // Outer rounded square border
            RoundedRectangle(cornerRadius: SlateTheme.checkboxRadius, style: .continuous)
                .strokeBorder(
                    status == .incomplete
                        ? (isHovered ? SlateColors.primary.opacity(0.55) : SlateColors.primary.opacity(0.28))
                        : SlateColors.primary,
                    lineWidth: 1.5
                )
                .frame(width: SlateTheme.checkboxSize, height: SlateTheme.checkboxSize)
            
            // Continuous 0° -> 180° -> 360° conic sweep fill
            PieSlice(sweep: sweepDegrees)
                .fill(SlateColors.primary)
                .frame(
                    width: status == .completed ? SlateTheme.checkboxSize : 14,
                    height: status == .completed ? SlateTheme.checkboxSize : 14
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: status == .completed ? SlateTheme.checkboxRadius : 4.5,
                        style: .continuous
                    )
                )
                .opacity(status == .incomplete ? 0 : 1)
            
            // Animated vector checkmark on completion (Things 3 style)
            CheckmarkShape()
                .trim(from: 0, to: status == .completed ? 1.0 : 0.0)
                .stroke(
                    SlateColors.primaryInverted,
                    style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 10, height: 8)
                .offset(y: 0.5)
            
            // Mouse event tracking overlay (Left-click & Right-click dispatch)
            ClickTrackingOverlay(
                onLeftClick: onLeftClick,
                onRightClick: onRightClick,
                onHover: { hovering in
                    withAnimation(SlateTheme.snapSpring) {
                        isHovered = hovering
                    }
                },
                onPressedChange: { pressed in
                    withAnimation(SlateTheme.snapSpring) {
                        isPressed = pressed
                    }
                }
            )
            .frame(width: SlateTheme.checkboxSize, height: SlateTheme.checkboxSize)
        }
        .frame(width: SlateTheme.checkboxSize, height: SlateTheme.checkboxSize)
        .scaleEffect(isPressed ? 0.86 : (isHovered ? 1.07 : 1.0))
        .help("Left-click to complete • Right-click for In Progress")
        .animation(SlateTheme.snapSpring, value: status)
    }
}

// MARK: - AppKit Click & Hover Tracking Overlay

struct ClickTrackingOverlay: NSViewRepresentable {
    let onLeftClick: () -> Void
    let onRightClick: (() -> Void)?
    let onHover: (Bool) -> Void
    let onPressedChange: (Bool) -> Void
    
    func makeNSView(context: Context) -> ClickTrackingNSView {
        let view = ClickTrackingNSView()
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        view.onHover = onHover
        view.onPressedChange = onPressedChange
        return view
    }
    
    func updateNSView(_ nsView: ClickTrackingNSView, context: Context) {
        nsView.onLeftClick = onLeftClick
        nsView.onRightClick = onRightClick
        nsView.onHover = onHover
        nsView.onPressedChange = onPressedChange
    }
}

final class ClickTrackingNSView: NSView {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var onPressedChange: ((Bool) -> Void)?
    
    private var trackingArea: NSTrackingArea?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }
    
    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }
    
    override func mouseExited(with event: NSEvent) {
        onHover?(false)
        onPressedChange?(false)
    }
    
    override func mouseDown(with event: NSEvent) {
        onPressedChange?(true)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        onPressedChange?(bounds.contains(pt))
    }
    
    override func mouseUp(with event: NSEvent) {
        onPressedChange?(false)
        let pt = convert(event.locationInWindow, from: nil)
        if bounds.contains(pt) {
            onLeftClick?()
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        onPressedChange?(true)
    }
    
    override func rightMouseUp(with event: NSEvent) {
        onPressedChange?(false)
        let pt = convert(event.locationInWindow, from: nil)
        if bounds.contains(pt) {
            onRightClick?()
        }
    }
}

// Custom shape for 0° -> 180° -> 360° sweep pie
struct PieSlice: Shape {
    var sweep: Double // in degrees
    
    var animatableData: Double {
        get { sweep }
        set { sweep = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard sweep > 0.1 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(rect.width, rect.height)
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + sweep),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

// Vector checkmark path for trim animation
struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.10))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.minY + rect.height * 0.10))
        return path
    }
}
