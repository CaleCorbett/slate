import Foundation
import AppKit

public enum SoundEvent {
    case completed
    case inProgress
    case deleted
    case allDeleted
    case notification
    case button
    case celebration
    
    var fileName: String? {
        switch self {
        case .completed: return "TaskCompleted.wav"
        case .inProgress: return "TaskInProgress.wav"
        case .deleted, .allDeleted: return "TaskDeleted.wav"
        case .notification: return "TaskNotification.wav"
        case .button: return "ButtonSound.wav"
        case .celebration: return nil
        }
    }
}

@MainActor
public final class SoundManager {
    public static let shared = SoundManager()
    private var soundCache: [String: NSSound] = [:]
    
    private init() {}
    
    public func play(_ event: SoundEvent) {
        guard AppSettings.shared.soundEffectsEnabled else { return }
        
        if event == .celebration {
            NSSound(named: "Hero")?.play()
            return
        }
        
        guard let soundName = event.fileName else { return }
        
        if let sound = soundCache[soundName] {
            sound.stop()
            sound.play()
            return
        }
        
        if let soundURL = Bundle.main.url(forResource: soundName, withExtension: nil),
           let sound = NSSound(contentsOf: soundURL, byReference: true) {
            soundCache[soundName] = sound
            sound.play()
        }
    }
}
