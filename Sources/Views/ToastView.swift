import SwiftUI

public struct ToastView: View {
    @ObservedObject var manager = UndoToastManager.shared
    
    public init() {}
    
    public var body: some View {
        if let message = manager.currentToastMessage {
            HStack(spacing: 12) {
                Image(systemName: manager.canUndo ? "trash.slash.fill" : "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SlateColors.primaryInverted.opacity(0.85))
                
                Text(message)
                    .font(.geist(.medium, size: 13))
                    .foregroundColor(SlateColors.primaryInverted)
                    .lineLimit(1)
                
                if manager.canUndo {
                    Button(action: {
                        manager.undo()
                    }) {
                        HStack(spacing: 5) {
                            Text("Undo")
                                .font(.geist(.semiBold, size: 12))
                                .foregroundColor(SlateColors.primaryInverted)
                            KeycapBadge("⌘Z", inverted: true)
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 5)
                        .padding(.vertical, 3)
                        .background(SlateColors.primaryInverted.opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else if let targetList = manager.targetListJump {
                    Button(action: {
                        manager.requestedFocusList = targetList
                        withAnimation(SlateTheme.easeSpring) {
                            manager.currentToastMessage = nil
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text("View \(targetList.title)")
                                .font(.geist(.semiBold, size: 12))
                                .foregroundColor(SlateColors.primaryInverted)
                            KeycapBadge(targetList.shortcutDisplay, inverted: true)
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 5)
                        .padding(.vertical, 3)
                        .background(SlateColors.primaryInverted.opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(SlateColors.primary)
                    .shadow(color: Color.black.opacity(0.28), radius: 16, x: 0, y: 8)
            )
            .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94)))
            .padding(.bottom, 38)
        }
    }
}
