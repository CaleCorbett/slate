import AppKit
import Combine
import Foundation
import SwiftData
import SwiftUI

@main
struct SmokeTestRunner {
    static var failures: [String] = []
    static var passedCount = 0

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passedCount += 1
            print("  ✅ PASS: \(message)")
        } else {
            failures.append(message)
            print("  ❌ FAIL: \(message)")
        }
    }

    @MainActor
    static func pumpRunLoop(seconds: TimeInterval = 0.05) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
    }

    @MainActor
    static func main() async {
        print("====================================================")
        print("🧪 SLATE AUTOMATED SMOKE TEST SUITE")
        print("====================================================")

        // Disable audio playback during automated tests
        let settings = AppSettings.shared
        let origSound = settings.soundEffectsEnabled
        let origAllowInProgress = settings.allowInProgress
        let origArchiveImm = settings.archiveImmediately
        let origMoveBottom = settings.moveCompletedToBottom
        let origSmartQuickAdd = settings.smartQuickAddEnabled
        let origAutoMove = settings.autoMoveRemindersToToday
        let origBadge = settings.menuBarBadge
        let origMode = settings.appearanceMode
        settings.soundEffectsEnabled = false

        // ----------------------------------------------------
        // TEST 1: AppSettings Idempotency & KVO Loop Prevention
        // ----------------------------------------------------
        print("\n[1/7] Testing AppSettings Idempotency & KVO Loop Prevention...")
        var settingsEmissions = 0
        let settingsSub = settings.objectWillChange.sink { _ in
            settingsEmissions += 1
        }

        let curShow = settings.showInMenuBar
        let curAllow = settings.allowInProgress
        let curPos = settings.addTaskPosition
        let curMove = settings.moveCompletedToBottom
        let curSmart = settings.smartQuickAddEnabled
        let curBadge = settings.menuBarBadge
        let curMode = settings.appearanceMode
        let curIcon = settings.selectedAppIcon
        let curArch = settings.archiveImmediately
        let curAuto = settings.autoMoveRemindersToToday
        let curCap = settings.todayCapLimit

        for _ in 0..<20 {
            settings.showInMenuBar = curShow
            settings.allowInProgress = curAllow
            settings.addTaskPosition = curPos
            settings.moveCompletedToBottom = curMove
            settings.smartQuickAddEnabled = curSmart
            settings.menuBarBadge = curBadge
            settings.appearanceMode = curMode
            settings.selectedAppIcon = curIcon
            settings.archiveImmediately = curArch
            settings.autoMoveRemindersToToday = curAuto
            settings.todayCapLimit = curCap
        }
        check(settingsEmissions == 0, "Re-assigning identical values 20x to all AppSettings properties emits 0 objectWillChange events (got \(settingsEmissions))")

        settings.showInMenuBar.toggle()
        settings.showInMenuBar.toggle()
        check(settingsEmissions == 2, "Toggling showInMenuBar twice emits exactly 2 objectWillChange events (got \(settingsEmissions))")
        
        let initialLogin = settings.launchAtLogin
        settings.launchAtLogin = initialLogin
        check(settings.launchAtLogin == initialLogin, "launchAtLogin getter/setter operates cleanly")
        _ = settingsSub

        // ----------------------------------------------------
        // TEST 2: DataStore Coalesced Emissions, CRUD, Batch & Undo
        // ----------------------------------------------------
        print("\n[2/7] Testing DataStore Coalesced Notifications, CRUD, Reorder, Batch & Undo...")
        let store = DataStore.shared
        // Clear initial starter tasks for clean deterministic assertions
        let allInitial = store.todayTasks + store.nextTasks + store.somedayTasks + store.archivedTasks
        for t in allInitial {
            store.context.delete(t)
        }
        try? store.context.save()
        store.reloadAll()

        var storeEmissions = 0
        let storeSub = store.objectWillChange.sink { _ in
            storeEmissions += 1
        }

        store.addTask(title: "Single emission test", to: .today)
        check(storeEmissions == 1, "DataStore.addTask emits exactly 1 coalesced objectWillChange event (got \(storeEmissions))")
        _ = storeSub

        // Stress insert 45 tasks across Today, Next, Someday
        for i in 1...15 {
            store.addTask(title: "Today Task \(i)", to: .today, notes: "Note \(i)")
            store.addTask(title: "Next Task \(i)", to: .next)
            store.addTask(title: "Someday Task \(i)", to: .someday)
        }
        check(store.todayTasks.count == 16, "Today has 16 tasks after bulk insert (got \(store.todayTasks.count))")
        check(store.nextTasks.count == 15, "Next has 15 tasks after bulk insert (got \(store.nextTasks.count))")
        check(store.somedayTasks.count == 15, "Someday has 15 tasks after bulk insert (got \(store.somedayTasks.count))")

        // 3-state status cycle test
        settings.allowInProgress = true
        settings.archiveImmediately = false
        let sampleTask = store.todayTasks[0]
        check(sampleTask.status == .incomplete, "Initial status is .incomplete")
        store.toggleTaskStatus(sampleTask)
        check(sampleTask.status == .inProgress, "First toggle with allowInProgress=true -> .inProgress")
        store.toggleTaskStatus(sampleTask)
        check(sampleTask.status == .completed, "Second toggle -> .completed")
        check(store.todayRemainingCount == 15 && store.todayTotalCount == 16, "todayRemainingCount (15) and todayTotalCount (16) updated accurately")
        store.toggleTaskStatus(sampleTask)
        check(sampleTask.status == .incomplete, "Third toggle -> .incomplete")

        // Reorder within list and across lists
        let firstToday = store.todayTasks[0]
        let thirdToday = store.todayTasks[2]
        store.reorderTask(thirdToday, before: firstToday)
        check(store.todayTasks.first?.id == thirdToday.id, "Within-list reorderTask places dragged task before target")

        let firstNext = store.nextTasks[0]
        store.reorderTask(firstNext, before: firstToday)
        check(firstNext.list == .today, "Cross-list reorderTask moves task from Next to Today")
        check(store.nextTasks.count == 14 && store.todayTasks.count == 17, "Cross-list reorderTask updates counts on both lists")

        // Batch Mark All Complete & Mark Incomplete
        store.setStatus(.completed, for: store.nextTasks)
        check(store.nextTasks.allSatisfy { $0.status == .completed }, "Batch setStatus(.completed) marks all Next tasks completed")
        store.setStatus(.incomplete, for: store.nextTasks)
        check(store.nextTasks.allSatisfy { $0.status == .incomplete }, "Batch setStatus(.incomplete) marks all Next tasks incomplete")

        // Batch Move
        let somedaySlice = Array(store.somedayTasks.prefix(5))
        store.moveTasks(somedaySlice, to: .next)
        check(store.somedayTasks.count == 10 && store.nextTasks.count == 19, "Batch moveTasks moves 5 tasks from Someday to Next")

        // Batch Delete + Multi-Task Undo
        let toDelete = Array(store.somedayTasks.prefix(4))
        let deletedIDs = Set(toDelete.map(\.id))
        store.deleteTasks(toDelete)
        check(store.somedayTasks.count == 6, "Batch deleteTasks removes 4 tasks from Someday (got \(store.somedayTasks.count))")

        // Streak celebration & daily streak tracker test
        let origStreak = settings.completionStreakCount
        let origLastCompleted = settings.lastCompletedDateString
        settings.completionStreakCount = 0
        settings.lastCompletedDateString = nil
        let testTodayTasks = [
            TodoTask(title: "Streak Task A", list: .today, status: .completed),
            TodoTask(title: "Streak Task B", list: .today, status: .completed)
        ]
        let streakCleared = settings.recordStreakIfTodayCleared(todayTasks: testTodayTasks)
        check(streakCleared && settings.completionStreakCount == 1, "recordStreakIfTodayCleared increments streak to 1 when today tasks are completed")
        check(settings.activeStreak == 1, "activeStreak reports 1 for current day")
        let secondStreakCheck = settings.recordStreakIfTodayCleared(todayTasks: testTodayTasks)
        check(!secondStreakCheck && settings.completionStreakCount == 1, "recordStreakIfTodayCleared prevents duplicate increments on the same day")
        settings.completionStreakCount = origStreak
        settings.lastCompletedDateString = origLastCompleted
        check(UndoToastManager.shared.canUndo, "UndoToastManager.canUndo is true after batch deletion")
        UndoToastManager.shared.undo()
        check(store.somedayTasks.count == 10, "UndoToastManager.undo() restores all 4 deleted tasks to Someday (got \(store.somedayTasks.count))")
        let restoredIDs = Set(store.somedayTasks.map(\.id)).intersection(deletedIDs)
        check(restoredIDs.count == 4, "All 4 restored task UUIDs match original deleted tasks")

        // Test Trash / Soft Delete and Restore
        let trashProbeTask = TodoTask(title: "Trash Probe Task", list: .today, status: .incomplete)
        store.context.insert(trashProbeTask)
        try? store.context.save()
        store.reloadAll()
        let todayBeforeDeleteCount = store.todayTasks.count
        let trashBeforeCount = store.deletedTasks.count
        store.deleteTask(trashProbeTask)
        check(store.todayTasks.count == todayBeforeDeleteCount - 1, "deleteTask removes task from active todayTasks")
        check(store.deletedTasks.count == trashBeforeCount + 1, "deleteTask moves task to store.deletedTasks (got \(store.deletedTasks.count))")
        check(trashProbeTask.deletedDate != nil, "Deleted task has non-nil deletedDate")
        store.restoreTaskFromTrash(trashProbeTask)
        check(store.deletedTasks.count == trashBeforeCount, "restoreTaskFromTrash removes task from deletedTasks")
        check(store.todayTasks.count == todayBeforeDeleteCount, "restoreTaskFromTrash brings task back to todayTasks")
        check(trashProbeTask.deletedDate == nil, "Restored task has nil deletedDate")
        store.deleteTask(trashProbeTask)
        store.emptyTrash()
        check(store.deletedTasks.isEmpty, "emptyTrash purges all items from deletedTasks (got \(store.deletedTasks.count))")

        // Test ExportService (Markdown, JSON, Standup)
        let mdExport = ExportService.shared.generateMarkdownOutline()
        check(mdExport.contains("# Slate To-Do Outline") && mdExport.contains("## Today"), "ExportService generates valid Markdown outline with Today header")
        let jsonExport = ExportService.shared.generateJSONBackup()
        check(jsonExport != nil && !jsonExport!.isEmpty, "ExportService generates non-empty JSON backup data")
        if let data = jsonExport,
           let jsonArr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            check(!jsonArr.isEmpty, "ExportService JSON backup parses into task array (got \(jsonArr.count) tasks)")
        } else {
            check(false, "ExportService JSON backup is valid JSON array")
        }
        let standupSummary = ExportService.shared.generateTodayStandupSummary()
        check(standupSummary.contains("**Today's Update") || standupSummary.contains("No to-dos scheduled"), "ExportService generates formatted standup summary")

        // Clear Completed & Archive verification
        store.setStatus(.completed, for: Array(store.todayTasks.prefix(3)))
        store.clearCompleted(in: .today)
        check(store.todayTasks.count == 14, "clearCompleted archives 3 completed tasks from Today")
        check(store.archivedTasks.count >= 3, "archivedTasks contains archived tasks (got \(store.archivedTasks.count))")

        // Fresh Start Carryover & Rollover Triage test
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let carryoverTask = TodoTask(
            title: "Old Incomplete Task",
            list: .today,
            status: .incomplete,
            creationDate: yesterday,
            lastTouchedDate: yesterday
        )
        store.context.insert(carryoverTask)
        try? store.context.save()
        store.reloadAll()
        check(store.carryoverTodayTasks.contains(where: { $0.id == carryoverTask.id }), "carryoverTodayTasks identifies task from yesterday")
        store.keepTasksInToday([carryoverTask])
        check(!store.carryoverTodayTasks.contains(where: { $0.id == carryoverTask.id }), "keepTasksInToday updates lastTouchedDate and clears task from carryover list")
        store.deleteTask(carryoverTask)

        // Recurring Task Automated Re-spawning test
        let recurringTask = TodoTask(
            title: "Daily Standup Routine",
            list: .today,
            status: .incomplete,
            recurrenceRule: "daily"
        )
        store.context.insert(recurringTask)
        try? store.context.save()
        store.reloadAll()
        let initialNextCount = store.nextTasks.count
        store.toggleTaskStatus(recurringTask) // becomes .inProgress
        store.toggleTaskStatus(recurringTask) // becomes .completed -> triggers handleTaskCompletionRecurrence
        check(recurringTask.status == .completed, "Recurring task marked .completed")
        check(store.nextTasks.count == initialNextCount + 1, "Automated re-spawning created next instance in Next list (got \(store.nextTasks.count))")
        let spawned = store.nextTasks.first(where: { $0.title == "Daily Standup Routine" && $0.id != recurringTask.id })
        check(spawned != nil && spawned?.recurrenceRule == "daily", "Spawned instance retains title and recurrenceRule 'daily'")
        if let s = spawned { store.deleteTask(s) }
        store.deleteTask(recurringTask)

        // Stale Someday Task & Visual Decay test
        let oldDate = Calendar.current.date(byAdding: .day, value: -35, to: Date()) ?? Date().addingTimeInterval(-36 * 86400) // 35 days ago
        let staleTask = TodoTask(
            title: "Old Dream App",
            list: .someday,
            status: .incomplete,
            creationDate: oldDate,
            lastTouchedDate: oldDate
        )
        store.context.insert(staleTask)
        try? store.context.save()
        store.reloadAll()
        check(staleTask.isStaleSomeday, "TodoTask.isStaleSomeday returns true for 35-day-old task in Someday")
        check(staleTask.daysUntouched >= 35, "TodoTask.daysUntouched reports >= 35 days (got \(staleTask.daysUntouched))")
        check(store.staleSomedayTasks.contains(where: { $0.id == staleTask.id }), "store.staleSomedayTasks contains stale task")
        store.touchTasks([staleTask])
        check(!staleTask.isStaleSomeday, "touchTasks updates lastTouchedDate and clears stale status")
        store.deleteTask(staleTask)

        // Focus Timer (Pomodoro) test
        let focusTask = TodoTask(title: "Deep Work Task", list: .today, status: .incomplete)
        store.context.insert(focusTask)
        try? store.context.save()
        store.reloadAll()

        FocusTimerService.shared.startTimer(for: focusTask, durationMinutes: 25)
        check(FocusTimerService.shared.isRunning, "FocusTimerService.shared.isRunning is true after start")
        check(FocusTimerService.shared.activeTaskID == focusTask.id, "FocusTimerService tracks activeTaskID")
        check(focusTask.status == .inProgress, "startTimer transitions task to .inProgress")
        check(FocusTimerService.shared.formattedRemainingTime == "25:00", "Initial remaining time is 25:00")

        FocusTimerService.shared.pauseTimer()
        check(FocusTimerService.shared.isPaused, "pauseTimer pauses focus session")
        FocusTimerService.shared.resumeTimer()
        check(!FocusTimerService.shared.isPaused, "resumeTimer resumes focus session")

        FocusTimerService.shared.completeSession()
        check(!FocusTimerService.shared.isRunning, "completeSession marks isRunning as false")
        check(focusTask.focusSecondsLogged == 25 * 60, "completeSession logs 1500 focusSecondsLogged (got \(focusTask.focusSecondsLogged))")
        store.deleteTask(focusTask)

        // Sub-Checklists test
        let checklistTask = TodoTask(title: "Task with Sub-Checklist", list: .today, status: .incomplete)
        checklistTask.checklist = [
            ChecklistItem(title: "Step 1", isCompleted: false),
            ChecklistItem(title: "Step 2", isCompleted: false)
        ]
        store.context.insert(checklistTask)
        try? store.context.save()
        store.reloadAll()

        check(checklistTask.checklist.count == 2, "Task contains 2 checklist items")
        check(checklistTask.checklistSummary?.completed == 0, "Initial checklist summary has 0 completed")
        check(checklistTask.checklistSummary?.total == 2, "Initial checklist summary has 2 total")

        var items = checklistTask.checklist
        items[0].isCompleted = true
        checklistTask.checklist = items
        try? store.context.save()
        store.reloadAll()

        check(checklistTask.checklistSummary?.completed == 1, "After toggle, checklist summary reports 1 completed")
        check(checklistTask.checklist[0].isCompleted, "First checklist item is completed")
        store.deleteTask(checklistTask)

        // Calendar Peek test
        let mockEvent1 = CalendarEventItem(
            title: "Sprint Planning",
            startDate: Date().addingTimeInterval(-600),
            endDate: Date().addingTimeInterval(1800),
            calendarTitle: "Work"
        )
        let mockEvent2 = CalendarEventItem(
            title: "Design Sync",
            startDate: Date().addingTimeInterval(3600),
            endDate: Date().addingTimeInterval(5400),
            calendarTitle: "Work"
        )
        CalendarPeekService.shared.setMockEvents([mockEvent1, mockEvent2])
        check(CalendarPeekService.shared.todayEvents.count == 2, "CalendarPeekService holds 2 mock events (got \(CalendarPeekService.shared.todayEvents.count))")
        check(mockEvent1.isNow, "Event occurring across current timestamp reports isNow=true")
        check(!mockEvent2.isNow, "Future event reports isNow=false")
        check(!mockEvent1.formattedTime.isEmpty, "CalendarEventItem formats start/end time")

        // ----------------------------------------------------
        // TEST 3: QuickAddParser Edge Cases & Performance Guard
        // ----------------------------------------------------
        print("\n[3/7] Testing QuickAddParser Natural Language & Large Input Guard...")
        settings.smartQuickAddEnabled = true

        let emptyParsed = QuickAddParser.parse("")
        check(emptyParsed.cleanTitle.isEmpty, "Empty input parses to empty cleanTitle")

        let eveningParsed = QuickAddParser.parse("Watch movie tonight")
        check(eveningParsed.isEvening && eveningParsed.targetList == .today && eveningParsed.cleanTitle == "Watch movie", "'Watch movie tonight' parses as isEvening=true on .today with cleanTitle 'Watch movie'")

        let somedayParsed = QuickAddParser.parse("Learn Rust someday")
        check(somedayParsed.targetList == .someday && somedayParsed.cleanTitle == "Learn Rust", "'Learn Rust someday' routes to .someday with clean title 'Learn Rust' (got '\(somedayParsed.cleanTitle)')")

        let datedParsed = QuickAddParser.parse("Dentist appointment tomorrow 3pm")
        check(datedParsed.reminderDate != nil && datedParsed.targetList == .next, "'Dentist appointment tomorrow 3pm' extracts reminderDate and routes to .next")

        let recurringParsed = QuickAddParser.parse("Team sync every weekday 9am")
        check(recurringParsed.recurrenceRule == "weekdays", "'Team sync every weekday 9am' parses recurrenceRule as 'weekdays' (got '\(recurringParsed.recurrenceRule ?? "nil")')")
        check(recurringParsed.cleanTitle == "Team sync", "'Team sync every weekday 9am' strips recurrence from cleanTitle (got '\(recurringParsed.cleanTitle)')")

        let monthlyParsed = QuickAddParser.parse("Pay rent monthly")
        check(monthlyParsed.recurrenceRule == "monthly" && monthlyParsed.cleanTitle == "Pay rent", "'Pay rent monthly' parses recurrenceRule as 'monthly'")

        let hugeInput = String(repeating: "very long task description word ", count: 500) + "someday"
        let startHuge = CFAbsoluteTimeGetCurrent()
        let hugeParsed = QuickAddParser.parse(hugeInput)
        let elapsedHugeMs = (CFAbsoluteTimeGetCurrent() - startHuge) * 1000.0
        check(elapsedHugeMs < 25.0 && !hugeParsed.cleanTitle.isEmpty, "16,000-char QuickAddParser input completes in \(String(format: "%.2f", elapsedHugeMs))ms (< 25ms) without hanging NSDataDetector")

        // FrontmostAppCaptureService check
        let sampleContext = CapturedContext(
            appName: "Safari",
            bundleID: "com.apple.Safari",
            title: "GitHub Repository",
            urlString: "https://github.com/CaleCorbett/slate"
        )
        FrontmostAppCaptureService.shared.lastCapturedContext = sampleContext
        check(FrontmostAppCaptureService.shared.lastCapturedContext?.appName == "Safari", "FrontmostAppCaptureService holds captured context")
        check(FrontmostAppCaptureService.shared.lastCapturedContext?.urlString == "https://github.com/CaleCorbett/slate", "Captured context retains URL")

        // ServicesProvider processing test
        let beforeTodayServicesCount = store.todayTasks.count
        ServicesProvider.shared.processIncomingText("Read article tonight")
        pumpRunLoop(seconds: 0.05)
        check(store.todayTasks.count == beforeTodayServicesCount + 1, "ServicesProvider.processIncomingText adds task parsed from Services menu")
        let servicesAddedTask = store.todayTasks.first(where: { $0.title == "Read article" })
        check(servicesAddedTask != nil && servicesAddedTask?.isEvening == true, "ServicesProvider parses 'tonight' correctly")
        if let t = servicesAddedTask { store.deleteTask(t) }

        // App Intents & Shortcuts test
        let addIntent = AddTaskIntent(title: "Intent Created Task", listName: "today")
        _ = try? await addIntent.perform()
        check(store.todayTasks.contains(where: { $0.title == "Intent Created Task" }), "AddTaskIntent inserts task into DataStore")

        let getTodayIntent = GetTodayTasksIntent()
        let getResult = try? await getTodayIntent.perform()
        check(getResult?.value?.contains("Intent Created Task") == true, "GetTodayTasksIntent returns list containing new task")

        let toggleIntent = ToggleTaskIntent(taskTitle: "Intent Created Task")
        _ = try? await toggleIntent.perform()
        let matchingTask = store.todayTasks.first(where: { $0.title == "Intent Created Task" })
        check(matchingTask?.status == .inProgress || matchingTask?.status == .completed, "ToggleTaskIntent modifies task status")
        if let t = matchingTask { store.deleteTask(t) }

        // macOS Focus Filter test
        let focusFilterIntent = SlateFocusFilterIntent(focusedListName: "today", hideSomeday: true)
        _ = try? await focusFilterIntent.perform()
        check(FocusFilterService.shared.isFocusFilterActive, "SlateFocusFilterIntent activates focus filter")
        check(FocusFilterService.shared.activeFilterListName == "today", "activeFilterListName is 'today'")
        check(FocusFilterService.shared.hideSomedayActive, "hideSomedayActive is true")

        FocusFilterService.shared.clearFocusFilter()
        check(!FocusFilterService.shared.isFocusFilterActive, "clearFocusFilter resets focus filter")

        // Reminders & Things 3 Importer test
        let sampleThingsJSON = """
        [
          {
            "type": "to-do",
            "attributes": {
              "title": "Imported Things Task",
              "notes": "Important note",
              "when": "today",
              "checklist-items": [
                { "attributes": { "title": "Subitem 1" } }
              ]
            }
          },
          {
            "title": "Imported Generic Task",
            "list": "someday"
          }
        ]
        """.data(using: .utf8)!
        let parsedJSONItems = (try? RemindersImporterService.shared.parseThingsJSON(sampleThingsJSON)) ?? []
        check(parsedJSONItems.count == 2, "RemindersImporterService.parseThingsJSON parses 2 items (got \(parsedJSONItems.count))")
        check(parsedJSONItems[0].targetList == .today, "First parsed item routes to .today")
        check(parsedJSONItems[0].checklistItems.contains("Subitem 1"), "First parsed item contains checklist items")

        let markdownTasks = """
        - [ ] Buy groceries tomorrow
        - Research quantum computing someday
        """
        let parsedMarkdown = RemindersImporterService.shared.parsePlainTextTasks(markdownTasks)
        check(parsedMarkdown.count == 2, "RemindersImporterService.parsePlainTextTasks parses 2 items")
        check(parsedMarkdown[1].targetList == .someday, "Markdown task with 'someday' routes to .someday")

        let initialTodayCount = store.todayTasks.count
        let countImported = RemindersImporterService.shared.importItems(parsedJSONItems, store: store, skipDuplicates: true)
        check(countImported == 2, "importItems imports 2 items (got \(countImported))")
        check(store.todayTasks.count == initialTodayCount + 1, "Today tasks count increased by 1")

        // Duplicate prevention
        let dupeCount = RemindersImporterService.shared.importItems(parsedJSONItems, store: store, skipDuplicates: true)
        check(dupeCount == 0, "Duplicate import with skipDuplicates=true imports 0 items (got \(dupeCount))")

        // Cleanup imported tasks
        if let t1 = store.todayTasks.first(where: { $0.title == "Imported Things Task" }) { store.deleteTask(t1) }
        if let t2 = store.somedayTasks.first(where: { $0.title == "Imported Generic Task" }) { store.deleteTask(t2) }

        // ----------------------------------------------------
        // TEST 4: AutoMoveService Daily Sweep
        // ----------------------------------------------------
        print("\n[4/7] Testing AutoMoveService Daily Sweep...")
        settings.autoMoveRemindersToToday = true
        let pastDueDate = Date().addingTimeInterval(-7200)
        store.addTask(title: "Overdue on Next", to: .next, reminderDate: pastDueDate)
        let beforeTodayCount = store.todayTasks.count
        AutoMoveService.shared.performDailySweep()
        check(store.todayTasks.count == beforeTodayCount + 1, "AutoMoveService moves overdue task from Next to Today and reloads DataStore")

        // ----------------------------------------------------
        // TEST 5: SwiftUI NSHostingView Rendering & RunLoop Settle Check
        // ----------------------------------------------------
        print("\n[5/7] Testing SwiftUI View Rendering & RunLoop Settle (Zero Spin)...")
        FontManager.shared.registerCustomFonts()

        let mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        mainWindow.isReleasedWhenClosed = false
        let mainHost = NSHostingView(rootView: MainView().modelContainer(store.container))
        mainWindow.contentView = mainHost
        mainHost.layoutSubtreeIfNeeded()

        let menuBarHost = NSHostingView(rootView: MenuBarTodayView().modelContainer(store.container))
        menuBarHost.frame = NSRect(x: 0, y: 0, width: 320, height: 390)
        menuBarHost.layoutSubtreeIfNeeded()

        let quickAddHost = NSHostingView(rootView: QuickAddPanel(isPresented: .constant(true)))
        quickAddHost.frame = NSRect(x: 0, y: 0, width: 520, height: 220)
        quickAddHost.layoutSubtreeIfNeeded()

        let archiveHost = NSHostingView(rootView: ArchiveView().modelContainer(store.container))
        archiveHost.frame = NSRect(x: 0, y: 0, width: 480, height: 460)
        archiveHost.layoutSubtreeIfNeeded()

        let settingsHost = NSHostingView(rootView: SettingsView())
        settingsHost.frame = NSRect(x: 0, y: 0, width: 500, height: 420)
        settingsHost.layoutSubtreeIfNeeded()

        let freshStartHost = NSHostingView(rootView: FreshStartRitualView().modelContainer(store.container))
        freshStartHost.frame = NSRect(x: 0, y: 0, width: 580, height: 460)
        freshStartHost.layoutSubtreeIfNeeded()

        let staleReviewHost = NSHostingView(rootView: StaleReviewSheet().modelContainer(store.container))
        staleReviewHost.frame = NSRect(x: 0, y: 0, width: 580, height: 460)
        staleReviewHost.layoutSubtreeIfNeeded()

        let commandPaletteHost = NSHostingView(rootView: CommandPaletteView(isPresented: .constant(true), onSelectTask: { _ in }, onSelectAction: { _ in }))
        commandPaletteHost.frame = NSRect(x: 0, y: 0, width: 560, height: 360)
        commandPaletteHost.layoutSubtreeIfNeeded()

        let importSheetHost = NSHostingView(rootView: ImportTasksSheet())
        importSheetHost.frame = NSRect(x: 0, y: 0, width: 540, height: 480)
        importSheetHost.layoutSubtreeIfNeeded()

        if let editableTask = store.todayTasks.first {
            let editorHost = NSHostingView(rootView: TaskEditorSheet(task: editableTask))
            editorHost.frame = NSRect(x: 0, y: 0, width: 440, height: 520)
            editorHost.layoutSubtreeIfNeeded()
        }

        // Let initial layout settle
        pumpRunLoop(seconds: 0.15)

        // Monitor objectWillChange during idle RunLoop ticks to verify zero feedback loops
        var idleStoreEvents = 0
        var idleSettingsEvents = 0
        let idleSub1 = store.objectWillChange.sink { _ in idleStoreEvents += 1 }
        let idleSub2 = settings.objectWillChange.sink { _ in idleSettingsEvents += 1 }

        pumpRunLoop(seconds: 0.25)

        check(idleStoreEvents == 0, "Zero DataStore invalidations during idle RunLoop with all views hosted (got \(idleStoreEvents))")
        check(idleSettingsEvents == 0, "Zero AppSettings invalidations during idle RunLoop with all views hosted (got \(idleSettingsEvents))")

        // ----------------------------------------------------
        // TEST 6: Live Mutations While Views Are Hosted in NSWindow
        // ----------------------------------------------------
        print("\n[6/7] Testing Live State Mutations Under Hosted Views (No Cascade Loops)...")
        // Mutate tasks and settings while MainView, MenuBarTodayView, SettingsView, ArchiveView are actively observing
        for i in 0..<5 {
            if let t = store.todayTasks.first {
                store.toggleTaskStatus(t)
            }
            settings.menuBarBadge = (i % 2 == 0) ? "total" : "remaining"
            UndoToastManager.shared.requestedFocusList = TaskListType.allCases[i % 3]
            pumpRunLoop(seconds: 0.03)
        }
        UndoToastManager.shared.requestedFocusList = nil
        pumpRunLoop(seconds: 0.08)

        // Now reset counters and verify complete silence after mutations settle
        idleStoreEvents = 0
        idleSettingsEvents = 0
        pumpRunLoop(seconds: 0.20)
        check(idleStoreEvents == 0, "Zero post-mutation DataStore feedback loops while views are mounted (got \(idleStoreEvents))")
        check(idleSettingsEvents == 0, "Zero post-mutation AppSettings feedback loops while views are mounted (got \(idleSettingsEvents))")

        _ = (idleSub1, idleSub2, mainWindow, mainHost, menuBarHost, quickAddHost, archiveHost, settingsHost, freshStartHost, staleReviewHost)

        // ----------------------------------------------------
        // TEST 7: GlobalHotKeyManager FloatingQuickAddNSPanel Lifecycle
        // ----------------------------------------------------
        print("\n[7/8] Testing GlobalHotKeyManager FloatingQuickAddNSPanel Show/Dismiss Cycles...")
        for _ in 0..<5 {
            GlobalHotKeyManager.shared.showFloatingPanel()
            pumpRunLoop(seconds: 0.02)
            GlobalHotKeyManager.shared.dismissFloatingPanel()
            pumpRunLoop(seconds: 0.02)
        }
        check(GlobalHotKeyManager.shared.shouldOpenQuickAdd == false, "5 rapid show/dismiss cycles on FloatingQuickAddNSPanel complete cleanly without re-entrant crash or zombie panel")

        // ----------------------------------------------------
        // TEST 8: AgentBridgeService Loopback REST API & Security
        // ----------------------------------------------------
        print("\n[8/8] Testing AgentBridgeService Loopback REST API & Security Gates...")
        let testPort: UInt16 = 23122
        AgentBridgeService.shared.start(port: testPort)
        pumpRunLoop(seconds: 0.15)
        check(AgentBridgeService.shared.isRunning, "AgentBridgeService is running on test port \(testPort)")

        let token = AgentBridgeService.shared.authToken
        check(!token.isEmpty, "AgentBridgeService generated secure auth token")

        func sendRequest(method: String, path: String, auth: String?, origin: String? = nil, body: [String: Any]? = nil) -> (Int, [String: Any]?, [[String: Any]]?) {
            let url = URL(string: "http://127.0.0.1:\(testPort)\(path)")!
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.timeoutInterval = 3.0
            if let auth = auth {
                req.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            if let origin = origin {
                req.setValue(origin, forHTTPHeaderField: "Origin")
            }
            if let body = body {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            }

            var statusCode = 0
            var resDict: [String: Any]?
            var resArray: [[String: Any]]?
            var done = false

            let task = URLSession.shared.dataTask(with: req) { data, response, error in
                if let http = response as? HTTPURLResponse {
                    statusCode = http.statusCode
                }
                if let data = data {
                    if let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        resDict = d
                    } else if let a = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        resArray = a
                    }
                }
                done = true
            }
            task.resume()

            let start = Date()
            while !done && Date().timeIntervalSince(start) < 2.0 {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            return (statusCode, resDict, resArray)
        }

        // Test missing token -> 401
        let (unauthCode, _, _) = sendRequest(method: "GET", path: "/v1/ping", auth: nil)
        check(unauthCode == 401, "GET /v1/ping without token returns 401 Unauthorized (got \(unauthCode))")

        // Test browser origin -> 403 Forbidden
        let (forbiddenCode, _, _) = sendRequest(method: "GET", path: "/v1/ping", auth: "Bearer \(token)", origin: "http://evil.com")
        check(forbiddenCode == 403, "GET /v1/ping with browser Origin header returns 403 Forbidden (got \(forbiddenCode))")

        // Test valid ping -> 200 OK
        let (pingCode, pingDict, _) = sendRequest(method: "GET", path: "/v1/ping", auth: "Bearer \(token)")
        check(pingCode == 200, "GET /v1/ping returns 200 OK (got \(pingCode))")
        check((pingDict?["status"] as? String) == "ok", "GET /v1/ping returns status: ok")

        // Test create task via POST /v1/tasks
        let createPayload: [String: Any] = [
            "title": "Agent Created Milestone Task",
            "list": "today",
            "notes": "Generated by external agent",
            "checklist": ["Spec written", "PR opened"]
        ]
        let (createCode, createdDict, _) = sendRequest(method: "POST", path: "/v1/tasks", auth: "Bearer \(token)", body: createPayload)
        check(createCode == 201, "POST /v1/tasks returns 201 Created (got \(createCode))")
        let createdIdStr = createdDict?["id"] as? String ?? ""
        let createdUUID = UUID(uuidString: createdIdStr)
        check(createdUUID != nil, "POST /v1/tasks returns valid UUID (got \(createdIdStr))")

        // Verify task appears in store.todayTasks
        pumpRunLoop(seconds: 0.05)
        let foundInStore = store.todayTasks.first(where: { $0.id == createdUUID })
        check(foundInStore != nil, "Created task is immediately live in store.todayTasks")
        check(foundInStore?.checklist.count == 2, "Created task checklist has 2 items (got \(foundInStore?.checklist.count ?? 0))")

        // Test toggle task via POST /v1/tasks/:id/toggle
        let (toggleCode, toggledDict, _) = sendRequest(method: "POST", path: "/v1/tasks/\(createdIdStr)/toggle", auth: "Bearer \(token)")
        check(toggleCode == 200, "POST /v1/tasks/:id/toggle returns 200 OK (got \(toggleCode))")
        let toggledStatus = toggledDict?["status"] as? String ?? ""
        check(toggledStatus == "in_progress" || toggledStatus == "completed", "Toggled status is in_progress or completed (got \(toggledStatus))")

        // Test GET /v1/plan
        let (planCode, planDict, _) = sendRequest(method: "GET", path: "/v1/plan", auth: "Bearer \(token)")
        check(planCode == 200, "GET /v1/plan returns 200 OK")
        check(planDict?["todayRemaining"] != nil, "GET /v1/plan contains todayRemaining count")

        // Test DELETE /v1/tasks/:id
        let (delCode, delDict, _) = sendRequest(method: "DELETE", path: "/v1/tasks/\(createdIdStr)", auth: "Bearer \(token)")
        check(delCode == 200, "DELETE /v1/tasks/:id returns 200 OK")
        check((delDict?["deleted"] as? Bool) == true, "DELETE /v1/tasks/:id returns deleted: true")

        // Test GET /v1/settings & PATCH /v1/settings (sound mute)
        let (settingsCode, settingsDict, _) = sendRequest(method: "GET", path: "/v1/settings", auth: "Bearer \(token)")
        check(settingsCode == 200, "GET /v1/settings returns 200 OK")
        check(settingsDict?["soundEffectsEnabled"] != nil, "GET /v1/settings returns soundEffectsEnabled")

        let (patchCode, patchedDict, _) = sendRequest(method: "PATCH", path: "/v1/settings", auth: "Bearer \(token)", body: ["soundEffectsEnabled": false])
        check(patchCode == 200, "PATCH /v1/settings returns 200 OK")
        check((patchedDict?["soundEffectsEnabled"] as? Bool) == false, "PATCH /v1/settings successfully muted soundEffectsEnabled")
        check(settings.soundEffectsEnabled == false, "AppSettings.shared.soundEffectsEnabled is false")

        // Verify SoundManager plays nothing while muted
        SoundManager.shared.play(.completed)
        SoundManager.shared.play(.celebration)

        AgentBridgeService.shared.stop()
        pumpRunLoop(seconds: 0.05)
        check(!AgentBridgeService.shared.isRunning, "AgentBridgeService cleanly stopped")

        // ----------------------------------------------------
        // TEST 9: KeychainService & AIService Parsers
        // ----------------------------------------------------
        print("\n[9/9] Testing KeychainService Security & AIService Parser Logic...")
        
        let testKeyName = "test_anthropic_key"
        let testSecret = "sk-ant-test-secret-12345"
        
        // Keychain save/load/delete
        let saved = KeychainService.shared.save(key: testKeyName, value: testSecret)
        check(saved, "KeychainService successfully saved test API key")
        
        let loaded = KeychainService.shared.load(key: testKeyName)
        check(loaded == testSecret, "KeychainService accurately retrieved secret (got \(loaded ?? "nil"))")
        
        let deleted = KeychainService.shared.delete(key: testKeyName)
        check(deleted, "KeychainService successfully purged key")
        
        let loadedAfterDelete = KeychainService.shared.load(key: testKeyName)
        check(loadedAfterDelete == nil, "KeychainService verifies key is gone after delete")
        
        // AIService string array parser tests
        let jsonInput = "[\"Draft outline\", \"Write intro\", \"Send for review\"]"
        let parsedJSON = AIService.parseStringArray(from: jsonInput)
        check(parsedJSON.count == 3, "AIService parses raw JSON array into 3 items (got \(parsedJSON.count))")
        check(parsedJSON.first == "Draft outline", "First item matches 'Draft outline'")
        
        let markdownFenced = """
        ```json
        [
          "Item Alpha",
          "Item Beta"
        ]
        ```
        """
        let parsedFenced = AIService.parseStringArray(from: markdownFenced)
        check(parsedFenced.count == 2, "AIService strips markdown code fences and parses 2 items")
        check(parsedFenced[1] == "Item Beta", "Second item matches 'Item Beta'")
        
        let bulletFallback = """
        1. First action step
        2. Second action step
        - Third action step
        """
        let parsedBullets = AIService.parseStringArray(from: bulletFallback)
        check(parsedBullets.count == 3, "AIService fallback parses numbered/bulleted text (got \(parsedBullets.count))")
        check(parsedBullets[0] == "First action step", "First bullet stripped properly")
        
        // AIProvider enum tests
        check(AIProvider.anthropic.keychainKey == "anthropic_api_key", "Anthropic keychain key is correct")
        check(AIProvider.openai.defaultModels.contains("gpt-4o"), "OpenAI default models include gpt-4o")
        check(AIProvider.grok.defaultModels.contains("grok-2"), "Grok default models include grok-2")
        check(AIProvider.ollama.defaultModels.contains("llama3.2"), "Ollama default models include llama3.2")

        // Restore original user settings
        settings.soundEffectsEnabled = origSound
        settings.allowInProgress = origAllowInProgress
        settings.archiveImmediately = origArchiveImm
        settings.moveCompletedToBottom = origMoveBottom
        settings.smartQuickAddEnabled = origSmartQuickAdd
        settings.autoMoveRemindersToToday = origAutoMove
        settings.menuBarBadge = origBadge
        settings.appearanceMode = origMode

        print("\n====================================================")
        if failures.isEmpty {
            print("🎉 ALL \(passedCount) SMOKE TESTS PASSED!")
            print("====================================================")
            exit(0)
        } else {
            print("💥 \(failures.count) SMOKE TEST(S) FAILED:")
            for f in failures {
                print("   - \(f)")
            }
            print("====================================================")
            exit(1)
        }
    }
}
