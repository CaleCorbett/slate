import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
public final class DataStore: ObservableObject {
    public static let shared = DataStore()
    
    public let container: ModelContainer
    public var context: ModelContext { container.mainContext }
    
    public private(set) var todayTasks: [TodoTask] = []
    public private(set) var nextTasks: [TodoTask] = []
    public private(set) var somedayTasks: [TodoTask] = []
    public private(set) var archivedTasks: [TodoTask] = []
    public private(set) var deletedTasks: [TodoTask] = []
    public private(set) var todayRemainingCount: Int = 0
    public private(set) var todayTotalCount: Int = 0
    
    public var refreshTrigger: UUID = UUID() {
        didSet {
            reloadAll()
        }
    }
    
    private init() {
        let schema = Schema([TodoTask.self])
        let inMemoryEnv = ProcessInfo.processInfo.environment["SLATE_IN_MEMORY_STORE"] == "1"
        
        if inMemoryEnv {
            let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            self.container = (try? ModelContainer(for: schema, configurations: [memConfig])) ?? {
                fatalError("Fatal: Failed to initialize in-memory ModelContainer")
            }()
        } else {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            if let persistentContainer = try? ModelContainer(for: schema, configurations: [config]) {
                self.container = persistentContainer
            } else {
                // Persistent container failed to load (e.g. incompatible schema file from old pre-v2 build).
                // Safely back up the incompatible store files and re-create a clean, persistent on-disk database.
                Self.recoverIncompatibleStore(at: config.url)
                if let freshPersistentContainer = try? ModelContainer(for: schema, configurations: [config]) {
                    self.container = freshPersistentContainer
                } else {
                    let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                    self.container = (try? ModelContainer(for: schema, configurations: [fallbackConfig])) ?? {
                        fatalError("Fatal: Failed to initialize ModelContainer")
                    }()
                }
            }
        }
        
        seedStarterTasksIfNeeded()
        reloadAll()
    }
    
    private static func recoverIncompatibleStore(at url: URL) {
        let fm = FileManager.default
        let storePath = url.path
        let walPath = storePath + "-wal"
        let shmPath = storePath + "-shm"
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupPath = storePath + ".incompatible.\(timestamp).bak"
        
        try? fm.moveItem(atPath: storePath, toPath: backupPath)
        try? fm.removeItem(atPath: walPath)
        try? fm.removeItem(atPath: shmPath)
    }
    
    public func seedStarterTasksIfNeeded() {
        let hasSeeded = UserDefaults.standard.bool(forKey: "hasSeededInitialTasks")
        guard !hasSeeded else { return }
        
        let descriptor = FetchDescriptor<TodoTask>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        if count > 0 {
            UserDefaults.standard.set(true, forKey: "hasSeededInitialTasks")
            return
        }
        
        let starterTasks: [(String, TaskListType, TaskStatus, String?, Date?)] = [
            // Today
            ("Review Q2 proposal", .today, .inProgress, nil, nil),
            ("Call dentist", .today, .incomplete, nil, nil),
            ("Send invoice to Acme Co.", .today, .incomplete, nil, Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date())),
            ("Pick up groceries", .today, .incomplete, "Milk, sourdough bread, organic eggs, avocados, cold brew.", nil),
            ("Standup at 9", .today, .completed, nil, nil),
            ("Morning run", .today, .completed, nil, nil),
            
            // Next
            ("Finalize pitch deck", .next, .incomplete, "Send link to investors before Friday review call.", nil),
            ("Plan Barcelona trip", .next, .incomplete, nil, nil),
            ("Annual checkup", .next, .incomplete, nil, nil),
            ("Reply to Sarah", .next, .incomplete, nil, nil),
            
            // Someday
            ("Run a half marathon", .someday, .incomplete, nil, nil),
            ("Read “Atomic Habits”", .someday, .incomplete, "By James Clear. Recommended by Tim.", nil),
            ("Visit Japan in spring", .someday, .incomplete, "Cherry blossom season in Kyoto & Tokyo.", nil),
            ("Start a podcast", .someday, .incomplete, nil, nil)
        ]
        
        for (i, item) in starterTasks.enumerated() {
            let task = TodoTask(
                title: item.0,
                list: item.1,
                status: item.2,
                notes: item.3,
                reminderDate: item.4,
                orderIndex: i
            )
            context.insert(task)
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: "hasSeededInitialTasks")
    }
    
    public func reloadAll() {
        let moveCompleted = UserDefaults.standard.object(forKey: "moveCompletedToBottom") as? Bool ?? true
        
        let fetchedToday = fetchTasksFromStore(for: .today, moveCompletedToBottom: moveCompleted)
        let fetchedNext = fetchTasksFromStore(for: .next, moveCompletedToBottom: moveCompleted)
        let fetchedSomeday = fetchTasksFromStore(for: .someday, moveCompletedToBottom: moveCompleted)
        
        let archiveDesc = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { task in
                (task.isArchived || task.rawStatus == 2) && task.deletedDate == nil
            },
            sortBy: [SortDescriptor(\.completionDate, order: .reverse)]
        )
        let fetchedArchived = (try? context.fetch(archiveDesc)) ?? []
        
        let trashDesc = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { task in
                task.deletedDate != nil
            },
            sortBy: [SortDescriptor(\.deletedDate, order: .reverse)]
        )
        let fetchedTrash = (try? context.fetch(trashDesc)) ?? []
        
        objectWillChange.send()
        self.todayTasks = fetchedToday
        self.nextTasks = fetchedNext
        self.somedayTasks = fetchedSomeday
        self.todayTotalCount = fetchedToday.count
        self.todayRemainingCount = fetchedToday.filter { $0.status != .completed }.count
        self.archivedTasks = fetchedArchived
        self.deletedTasks = fetchedTrash
    }
    
    public var carryoverTodayTasks: [TodoTask] {
        let cal = Calendar.current
        return todayTasks.filter { task in
            task.status != .completed && !cal.isDateInToday(task.lastTouchedDate ?? task.creationDate)
        }
    }
    
    public func keepTasksInToday(_ tasksToKeep: [TodoTask]) {
        guard !tasksToKeep.isEmpty else { return }
        let now = Date()
        for task in tasksToKeep {
            task.lastTouchedDate = now
        }
        try? context.save()
        reloadAll()
    }
    
    public var staleSomedayTasks: [TodoTask] {
        somedayTasks.filter { $0.isStaleSomeday }
    }
    
    public func touchTasks(_ tasksToTouch: [TodoTask]) {
        guard !tasksToTouch.isEmpty else { return }
        let now = Date()
        for task in tasksToTouch {
            task.lastTouchedDate = now
        }
        try? context.save()
        reloadAll()
    }
    
    private func fetchTasksFromStore(for list: TaskListType, moveCompletedToBottom: Bool) -> [TodoTask] {
        let raw = list.rawValue
        let predicate = #Predicate<TodoTask> { task in
            task.rawList == raw && !task.isArchived && task.deletedDate == nil
        }
        var descriptor = FetchDescriptor<TodoTask>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.orderIndex, order: .forward)]
        
        var listTasks = (try? context.fetch(descriptor)) ?? []
        
        if moveCompletedToBottom {
            listTasks.sort { a, b in
                if (a.status == .completed) == (b.status == .completed) {
                    return a.orderIndex < b.orderIndex
                }
                return a.status != .completed
            }
        }
        return listTasks
    }
    
    public func tasks(for list: TaskListType, includeArchived: Bool = false) -> [TodoTask] {
        if !includeArchived {
            switch list {
            case .today: return todayTasks
            case .next: return nextTasks
            case .someday: return somedayTasks
            }
        }
        let raw = list.rawValue
        let predicate = #Predicate<TodoTask> { task in
            task.rawList == raw && task.deletedDate == nil
        }
        var descriptor = FetchDescriptor<TodoTask>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.orderIndex, order: .forward)]
        return (try? context.fetch(descriptor)) ?? []
    }
    
    public func task(with id: UUID) -> TodoTask? {
        if let found = (todayTasks + nextTasks + somedayTasks).first(where: { $0.id == id }) {
            return found
        }
        let descriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }
    
    @discardableResult
    public func addTask(
        title: String,
        to list: TaskListType,
        notes: String? = nil,
        reminderDate: Date? = nil,
        isEvening: Bool = false,
        recurrenceRule: String? = nil,
        checklistJSON: String? = nil
    ) -> TodoTask? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let existing = tasks(for: list)
        let order = (AppSettings.shared.addTaskPosition == "top")
            ? (existing.map(\.orderIndex).min() ?? 0) - 1
            : (existing.map(\.orderIndex).max() ?? 0) + 1
        
        let task = TodoTask(
            title: trimmed,
            list: list,
            status: .incomplete,
            notes: notes,
            reminderDate: reminderDate,
            orderIndex: order,
            recurrenceRule: recurrenceRule,
            isEvening: isEvening,
            checklistJSON: checklistJSON
        )
        context.insert(task)
        try? context.save()
        
        if task.reminderDate != nil {
            ReminderService.shared.scheduleReminder(for: task)
        }
        
        SoundManager.shared.play(.button)
        reloadAll()
        return task
    }
    
    public func toggleTaskStatus(_ task: TodoTask) {
        let prev = task.status
        let next = prev.nextStatus(allowInProgress: AppSettings.shared.allowInProgress)
        task.status = next
        if next == .completed {
            if AppSettings.shared.archiveImmediately {
                task.isArchived = true
            }
            handleTaskCompletionRecurrence(task)
        }
        try? context.save()
        
        switch next {
        case .completed:
            ReminderService.shared.cancelReminder(for: task)
            SoundManager.shared.play(.completed)
            if task.list == .today {
                evaluateTodayClearedCelebration()
            }
        case .inProgress:
            SoundManager.shared.play(.inProgress)
        case .incomplete:
            if task.reminderDate != nil {
                ReminderService.shared.scheduleReminder(for: task)
            }
            SoundManager.shared.play(.button)
        }
        
        reloadAll()
    }
    
    public func moveTask(_ task: TodoTask, to list: TaskListType) {
        guard task.list != list else { return }
        let existing = tasks(for: list)
        let order = (AppSettings.shared.addTaskPosition == "top")
            ? (existing.map(\.orderIndex).min() ?? 0) - 1
            : (existing.map(\.orderIndex).max() ?? 0) + 1
        task.list = list
        task.orderIndex = order
        try? context.save()
        SoundManager.shared.play(.button)
        reloadAll()
    }
    
    /// Reorders `draggedTask` directly before `targetTask` (moving across lists if needed).
    public func reorderTask(_ draggedTask: TodoTask, before targetTask: TodoTask) {
        guard draggedTask.id != targetTask.id else { return }
        let destinationList = targetTask.list
        draggedTask.list = destinationList
        
        var listItems = tasks(for: destinationList).filter { $0.id != draggedTask.id }
        if let targetIdx = listItems.firstIndex(where: { $0.id == targetTask.id }) {
            listItems.insert(draggedTask, at: targetIdx)
        } else {
            listItems.append(draggedTask)
        }
        
        for (idx, item) in listItems.enumerated() {
            item.orderIndex = idx
        }
        
        try? context.save()
        SoundManager.shared.play(.button)
        reloadAll()
    }
    
    public func deleteTask(_ task: TodoTask) {
        ReminderService.shared.cancelReminder(for: task)
        UndoToastManager.shared.recordDeletion(of: task)
        task.deletedDate = Date()
        try? context.save()
        SoundManager.shared.play(.deleted)
        reloadAll()
    }
    
    public func deleteTasks(_ tasksToDelete: [TodoTask]) {
        guard !tasksToDelete.isEmpty else { return }
        ReminderService.shared.cancelReminders(for: tasksToDelete)
        UndoToastManager.shared.recordDeletion(of: tasksToDelete)
        let now = Date()
        for task in tasksToDelete {
            task.deletedDate = now
        }
        try? context.save()
        SoundManager.shared.play(tasksToDelete.count > 1 ? .allDeleted : .deleted)
        reloadAll()
    }
    
    public func restoreTaskFromTrash(_ task: TodoTask) {
        task.deletedDate = nil
        task.lastTouchedDate = Date()
        if task.reminderDate != nil {
            ReminderService.shared.scheduleReminder(for: task)
        }
        try? context.save()
        SoundManager.shared.play(.notification)
        UndoToastManager.shared.showInfo("Restored “\(task.title)” to \(task.list.title)")
        reloadAll()
    }
    
    public func permanentlyDeleteTask(_ task: TodoTask) {
        ReminderService.shared.cancelReminder(for: task)
        context.delete(task)
        try? context.save()
        SoundManager.shared.play(.deleted)
        reloadAll()
    }
    
    public func emptyTrash() {
        guard !deletedTasks.isEmpty else { return }
        let count = deletedTasks.count
        ReminderService.shared.cancelReminders(for: deletedTasks)
        for task in deletedTasks {
            context.delete(task)
        }
        try? context.save()
        SoundManager.shared.play(.allDeleted)
        UndoToastManager.shared.showInfo("Emptied trash (\(count) to-dos permanently deleted)")
        reloadAll()
    }
    
    public func moveTasks(_ tasksToMove: [TodoTask], to list: TaskListType) {
        let valid = tasksToMove.filter { $0.list != list }
        guard !valid.isEmpty else { return }
        let existing = tasks(for: list)
        var nextOrder = (AppSettings.shared.addTaskPosition == "top")
            ? (existing.map(\.orderIndex).min() ?? 0) - valid.count
            : (existing.map(\.orderIndex).max() ?? 0) + 1
        
        for task in valid {
            task.list = list
            task.orderIndex = nextOrder
            nextOrder += 1
        }
        try? context.save()
        SoundManager.shared.play(.button)
        reloadAll()
    }
    
    public func setStatus(_ status: TaskStatus, for targetTasks: [TodoTask]) {
        guard !targetTasks.isEmpty else { return }
        if status == .completed {
            ReminderService.shared.cancelReminders(for: targetTasks)
        }
        for task in targetTasks {
            let wasCompleted = task.status == .completed
            task.status = status
            if status == .completed {
                if !wasCompleted {
                    handleTaskCompletionRecurrence(task)
                }
                if AppSettings.shared.archiveImmediately {
                    task.isArchived = true
                }
            } else if status == .incomplete, task.reminderDate != nil {
                ReminderService.shared.scheduleReminder(for: task)
            }
        }
        try? context.save()
        switch status {
        case .completed:
            SoundManager.shared.play(.completed)
            if targetTasks.contains(where: { $0.list == .today }) {
                evaluateTodayClearedCelebration()
            }
        case .inProgress:
            SoundManager.shared.play(.inProgress)
        case .incomplete:
            SoundManager.shared.play(.button)
        }
        reloadAll()
    }
    
    public func handleTaskCompletionRecurrence(_ task: TodoTask) {
        guard let rule = task.recurrenceRule, !rule.isEmpty else { return }
        
        let nextDate = RecurrenceService.nextDueDate(for: rule, from: Date())
        let nextList: TaskListType = Calendar.current.isDateInToday(nextDate) ? .today : .next
        let nextReminder: Date? = task.reminderDate != nil ? nextDate : nil
        
        let existing = tasks(for: nextList)
        let order = (AppSettings.shared.addTaskPosition == "top")
            ? (existing.map(\.orderIndex).min() ?? 0) - 1
            : (existing.map(\.orderIndex).max() ?? 0) + 1
        
        let nextTask = TodoTask(
            title: task.title,
            list: nextList,
            status: .incomplete,
            notes: task.notes,
            reminderDate: nextReminder,
            orderIndex: order,
            recurrenceRule: rule,
            isEvening: task.isEvening
        )
        context.insert(nextTask)
        if nextReminder != nil {
            ReminderService.shared.scheduleReminder(for: nextTask)
        }
        
        let ruleDisplay = RecurrenceService.displayString(for: rule)
        UndoToastManager.shared.showInfo("Next \(ruleDisplay) to-do scheduled in \(nextList.title)", targetList: nextList)
    }
    
    public func evaluateTodayClearedCelebration() {
        let todayListTasks = tasks(for: .today)
        let cleared = AppSettings.shared.recordStreakIfTodayCleared(todayTasks: todayListTasks)
        if cleared {
            let streak = AppSettings.shared.completionStreakCount
            NSSound(named: "Hero")?.play()
            UndoToastManager.shared.showInfo("🎉 Today cleared! 🔥 \(streak)-day streak")
        }
    }
    
    public func clearCompleted(in list: TaskListType) {
        let completed = tasks(for: list).filter { $0.status == .completed }
        guard !completed.isEmpty else { return }
        for t in completed {
            t.isArchived = true
        }
        try? context.save()
        SoundManager.shared.play(.allDeleted)
        reloadAll()
    }
}
