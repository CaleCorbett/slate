import SwiftUI
import Combine

public struct DeletedTaskSnapshot {
    public let id: UUID
    public let title: String
    public let list: TaskListType
    public let status: TaskStatus
    public let notes: String?
    public let reminderDate: Date?
    public let orderIndex: Int
}

@MainActor
public final class UndoToastManager: ObservableObject {
    public static let shared = UndoToastManager()
    
    @Published public var currentToastMessage: String? = nil
    @Published public var canUndo: Bool = false
    @Published public var targetListJump: TaskListType? = nil
    @Published public var requestedFocusList: TaskListType? = nil
    
    private var lastDeletedBatch: [DeletedTaskSnapshot] = []
    private var dismissTimer: Timer?
    
    private init() {}
    
    public func recordDeletion(of task: TodoTask) {
        recordDeletion(of: [task])
    }
    
    public func recordDeletion(of tasks: [TodoTask]) {
        guard !tasks.isEmpty else { return }
        lastDeletedBatch = tasks.map { task in
            DeletedTaskSnapshot(
                id: task.id,
                title: task.title,
                list: task.list,
                status: task.status,
                notes: task.notes,
                reminderDate: task.reminderDate,
                orderIndex: task.orderIndex
            )
        }
        
        withAnimation(SlateTheme.snapSpring) {
            canUndo = true
            targetListJump = nil
            if tasks.count == 1, let first = tasks.first {
                currentToastMessage = "Deleted “\(first.title)”"
            } else {
                currentToastMessage = "Deleted \(tasks.count) to-dos"
            }
        }
        
        scheduleDismiss(after: 5.0)
    }
    
    public func showInfo(_ message: String, targetList: TaskListType? = nil) {
        withAnimation(SlateTheme.snapSpring) {
            canUndo = false
            targetListJump = targetList
            currentToastMessage = message
        }
        scheduleDismiss(after: 3.2)
    }
    
    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                withAnimation(SlateTheme.easeSpring) {
                    self?.currentToastMessage = nil
                    self?.targetListJump = nil
                }
            }
        }
    }
    
    public func undo() {
        guard !lastDeletedBatch.isEmpty else { return }
        
        for snapshot in lastDeletedBatch {
            if let existing = DataStore.shared.deletedTasks.first(where: { $0.id == snapshot.id }) {
                existing.deletedDate = nil
                existing.lastTouchedDate = Date()
                if existing.reminderDate != nil {
                    ReminderService.shared.scheduleReminder(for: existing)
                }
            } else {
                let restored = TodoTask(
                    id: snapshot.id,
                    title: snapshot.title,
                    list: snapshot.list,
                    status: snapshot.status,
                    notes: snapshot.notes,
                    reminderDate: snapshot.reminderDate,
                    orderIndex: snapshot.orderIndex
                )
                DataStore.shared.context.insert(restored)
                if restored.reminderDate != nil {
                    ReminderService.shared.scheduleReminder(for: restored)
                }
            }
        }
        
        try? DataStore.shared.context.save()
        DataStore.shared.refreshTrigger = UUID()
        SoundManager.shared.play(.notification)
        
        lastDeletedBatch = []
        canUndo = false
        withAnimation(SlateTheme.easeSpring) {
            currentToastMessage = nil
        }
    }
}
