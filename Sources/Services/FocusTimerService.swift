import Foundation
import Combine
import UserNotifications

@MainActor
public final class FocusTimerService: ObservableObject {
    public static let shared = FocusTimerService()
    
    @Published public private(set) var activeTaskID: UUID? = nil
    @Published public private(set) var activeTaskTitle: String? = nil
    @Published public private(set) var totalDurationSeconds: Int = 25 * 60
    @Published public private(set) var remainingSeconds: Int = 0
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isPaused: Bool = false
    
    private var timerCancellable: AnyCancellable? = nil
    
    public init() {}
    
    public var progress: Double {
        guard totalDurationSeconds > 0 else { return 0 }
        let elapsed = totalDurationSeconds - remainingSeconds
        return Double(elapsed) / Double(totalDurationSeconds)
    }
    
    public var formattedRemainingTime: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    public func startTimer(for task: TodoTask, durationMinutes: Int? = nil) {
        let minutes = durationMinutes ?? AppSettings.shared.focusDurationMinutes
        activeTaskID = task.id
        activeTaskTitle = task.title
        totalDurationSeconds = max(1, minutes * 60)
        remainingSeconds = totalDurationSeconds
        isRunning = true
        isPaused = false
        
        // Ensure task is in progress
        if task.status != .inProgress {
            task.status = .inProgress
            try? DataStore.shared.context.save()
            DataStore.shared.reloadAll()
        }
        
        startTicker()
        UndoToastManager.shared.showInfo("Focus timer started (\(minutes)m): “\(task.title)”")
    }
    
    public func pauseTimer() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    public func resumeTimer() {
        guard isRunning, isPaused else { return }
        isPaused = false
        startTicker()
    }
    
    public func stopTimer(logElapsed: Bool = true) {
        timerCancellable?.cancel()
        timerCancellable = nil
        
        if logElapsed, let taskID = activeTaskID {
            let elapsed = totalDurationSeconds - remainingSeconds
            if elapsed > 10, let task = DataStore.shared.task(with: taskID) {
                task.focusSecondsLogged += elapsed
                try? DataStore.shared.context.save()
                DataStore.shared.reloadAll()
            }
        }
        
        activeTaskID = nil
        activeTaskTitle = nil
        remainingSeconds = 0
        isRunning = false
        isPaused = false
    }
    
    public func completeSession() {
        timerCancellable?.cancel()
        timerCancellable = nil
        
        let title = activeTaskTitle ?? "To-do"
        let minutes = totalDurationSeconds / 60
        
        if let taskID = activeTaskID, let task = DataStore.shared.task(with: taskID) {
            task.focusSecondsLogged += totalDurationSeconds
            try? DataStore.shared.context.save()
            DataStore.shared.reloadAll()
        }
        
        SoundManager.shared.play(.completed)
        UndoToastManager.shared.showInfo("Focus session complete! (\(minutes)m logged)")
        sendCompletionNotification(taskTitle: title)
        
        activeTaskID = nil
        activeTaskTitle = nil
        remainingSeconds = 0
        isRunning = false
        isPaused = false
    }
    
    private func startTicker() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                guard self.isRunning, !self.isPaused else { return }
                
                if self.remainingSeconds > 1 {
                    self.remainingSeconds -= 1
                } else {
                    self.completeSession()
                }
            }
    }
    
    private func sendCompletionNotification(taskTitle: String) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let content = UNMutableNotificationContent()
        content.title = "Focus Session Finished"
        content.body = "Great work! You logged a focused session on “\(taskTitle)”."
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "slate.focus.completed.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

