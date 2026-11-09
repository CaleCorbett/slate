import Foundation
@preconcurrency import UserNotifications

@MainActor
public final class ReminderService: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = ReminderService()
    
    public static let categoryIdentifier = "SLATE_TASK_REMINDER"
    public static let actionComplete = "ACTION_COMPLETE"
    public static let actionSnooze1Hour = "ACTION_SNOOZE_1H"
    public static let actionTomorrow = "ACTION_TOMORROW"
    
    private override init() {
        super.init()
        setupNotificationCategories()
    }
    
    /// Safely returns `UNUserNotificationCenter.current()` only when running inside a valid `.app` bundle.
    /// Calling `UNUserNotificationCenter.current()` from a bare executable (`swift run` / CLI test) throws
    /// an uncaught Objective-C `NSInternalInconsistencyException` (`bundleProxyForCurrentProcess is nil`).
    private var notificationCenter: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundleURL.pathExtension == "app" else {
            return nil
        }
        return UNUserNotificationCenter.current()
    }
    
    public func setupNotificationCategories() {
        guard let center = notificationCenter else { return }
        center.delegate = self
        
        let completeAction = UNNotificationAction(
            identifier: Self.actionComplete,
            title: "Mark Done",
            options: [.authenticationRequired]
        )
        let snoozeAction = UNNotificationAction(
            identifier: Self.actionSnooze1Hour,
            title: "Snooze 1 Hour",
            options: []
        )
        let tomorrowAction = UNNotificationAction(
            identifier: Self.actionTomorrow,
            title: "Move to Tomorrow",
            options: []
        )
        
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [completeAction, snoozeAction, tomorrowAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        guard let uuid = UUID(uuidString: identifier) else {
            completionHandler()
            return
        }
        
        Task { @MainActor in
            guard let task = DataStore.shared.task(with: uuid) else {
                completionHandler()
                return
            }
            
            switch response.actionIdentifier {
            case Self.actionComplete:
                task.status = .completed
                DataStore.shared.handleTaskCompletionRecurrence(task)
                if AppSettings.shared.archiveImmediately {
                    task.isArchived = true
                }
                try? DataStore.shared.context.save()
                DataStore.shared.reloadAll()
                SoundManager.shared.play(.completed)
                if task.list == .today {
                    DataStore.shared.evaluateTodayClearedCelebration()
                }
                
            case Self.actionSnooze1Hour:
                let newDate = Date().addingTimeInterval(3600)
                task.reminderDate = newDate
                try? DataStore.shared.context.save()
                ReminderService.shared.scheduleReminder(for: task)
                DataStore.shared.reloadAll()
                
            case Self.actionTomorrow:
                let calendar = Calendar.current
                if let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) {
                    let nextDayDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
                    task.reminderDate = nextDayDate
                    if task.list == .today {
                        task.list = .next
                    }
                    try? DataStore.shared.context.save()
                    ReminderService.shared.scheduleReminder(for: task)
                    DataStore.shared.reloadAll()
                }
                
            default:
                break
            }
            completionHandler()
        }
    }
    
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
    
    public func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        guard let center = notificationCenter else {
            completion?(false)
            return
        }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
            Task { @MainActor in
                completion?(granted)
            }
        }
    }
    
    public func scheduleReminder(for task: TodoTask) {
        guard let reminderDate = task.reminderDate, reminderDate > Date(),
              let center = notificationCenter else { return }
        let taskId = task.id.uuidString
        let taskTitle = task.title
        let listTitle = task.list.title
        
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                Task { @MainActor in
                    ReminderService.shared.addNotificationRequest(id: taskId, title: taskTitle, listTitle: listTitle, at: reminderDate)
                }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if granted {
                        Task { @MainActor in
                            ReminderService.shared.addNotificationRequest(id: taskId, title: taskTitle, listTitle: listTitle, at: reminderDate)
                        }
                    } else if let error = error {
                        print("Notification authorization denied or error: \(error)")
                    }
                }
            case .denied:
                print("Notifications are denied by the user.")
            @unknown default:
                break
            }
        }
    }
    
    private func addNotificationRequest(id: String, title: String, listTitle: String, at reminderDate: Date) {
        guard let center = notificationCenter else { return }
        let content = UNMutableNotificationContent()
        content.title = "Slate"
        content.subtitle = listTitle
        content.body = title
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: trigger
        )
        
        center.add(request) { error in
            if let error = error {
                print("Error scheduling reminder: \(error)")
            }
        }
    }
    
    public func cancelReminder(for task: TodoTask) {
        guard task.reminderDate != nil, let center = notificationCenter else { return }
        center.removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
    }
    
    public func cancelReminders(for tasks: [TodoTask]) {
        let ids = tasks.filter { $0.reminderDate != nil }.map { $0.id.uuidString }
        guard !ids.isEmpty, let center = notificationCenter else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
