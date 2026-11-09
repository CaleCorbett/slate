import Foundation
import AppKit

@objc(ServicesProvider)
public final class ServicesProvider: NSObject {
    public static let shared = ServicesProvider()
    
    public func registerServices() {
        DispatchQueue.main.async {
            NSApplication.shared.servicesProvider = self
            NSUpdateDynamicServices()
        }
    }
    
    @objc public func handleSendToSlateService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        guard let text = pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return
        }
        
        processIncomingText(text)
    }
    
    public func processIncomingText(_ text: String) {
        let parsed = QuickAddParser.parse(text)
        let finalTitle = parsed.cleanTitle.isEmpty ? text : parsed.cleanTitle
        
        Task { @MainActor in
            DataStore.shared.addTask(
                title: finalTitle,
                to: parsed.targetList,
                reminderDate: parsed.reminderDate,
                isEvening: parsed.isEvening,
                recurrenceRule: parsed.recurrenceRule
            )
            SoundManager.shared.play(.notification)
            UndoToastManager.shared.showInfo("Added via Services: “\(finalTitle)”", targetList: parsed.targetList)
        }
    }
}

