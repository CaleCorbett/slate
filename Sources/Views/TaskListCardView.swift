import SwiftUI
import AppKit

public struct TaskListCardView: View {
    let listType: TaskListType
    let tasks: [TodoTask]
    let selectedTaskIDs: Set<UUID>
    let expandedTaskID: UUID?
    let isFocusedCard: Bool
    let onSelectTask: (TodoTask, NSEvent.ModifierFlags) -> Void
    let onSelectAllInGroup: (TaskListType) -> Void
    let onDeselectAllInGroup: (TaskListType) -> Void
    let onToggleExpandTask: (TodoTask) -> Void
    let onToggleStatus: (TodoTask) -> Void
    let onEditTask: (TodoTask) -> Void
    let onDeleteTask: (TodoTask) -> Void
    let onMoveTask: (TodoTask, TaskListType) -> Void
    let onBatchSetStatus: ([TodoTask], TaskStatus) -> Void
    let onBatchMove: ([TodoTask], TaskListType) -> Void
    let onBatchDelete: ([TodoTask]) -> Void
    let onAddTask: (String, TaskListType, Date?, Bool, String?) -> Void
    let onClearCompleted: (TaskListType) -> Void
    let onToggleFocusCard: (TaskListType) -> Void
    let onOpenFreshStart: (() -> Void)?
    let onOpenStaleReview: (() -> Void)?
    
    @ObservedObject private var calendarPeek = CalendarPeekService.shared
    @State private var newTodoText: String = ""
    @State private var isTargetedForDrop = false
    @State private var isSelectionModeActive = false
    @FocusState private var isInputFocused: Bool
    
    public init(
        listType: TaskListType,
        tasks: [TodoTask],
        selectedTaskIDs: Set<UUID> = [],
        expandedTaskID: UUID? = nil,
        isFocusedCard: Bool = false,
        onSelectTask: @escaping (TodoTask, NSEvent.ModifierFlags) -> Void = { _, _ in },
        onSelectAllInGroup: @escaping (TaskListType) -> Void = { _ in },
        onDeselectAllInGroup: @escaping (TaskListType) -> Void = { _ in },
        onToggleExpandTask: @escaping (TodoTask) -> Void = { _ in },
        onToggleStatus: @escaping (TodoTask) -> Void,
        onEditTask: @escaping (TodoTask) -> Void,
        onDeleteTask: @escaping (TodoTask) -> Void,
        onMoveTask: @escaping (TodoTask, TaskListType) -> Void,
        onBatchSetStatus: @escaping ([TodoTask], TaskStatus) -> Void = { _, _ in },
        onBatchMove: @escaping ([TodoTask], TaskListType) -> Void = { _, _ in },
        onBatchDelete: @escaping ([TodoTask]) -> Void = { _ in },
        onAddTask: @escaping (String, TaskListType, Date?, Bool, String?) -> Void = { _, _, _, _, _ in },
        onClearCompleted: @escaping (TaskListType) -> Void,
        onToggleFocusCard: @escaping (TaskListType) -> Void = { _ in },
        onOpenFreshStart: (() -> Void)? = nil,
        onOpenStaleReview: (() -> Void)? = nil
    ) {
        self.listType = listType
        self.tasks = tasks
        self.selectedTaskIDs = selectedTaskIDs
        self.expandedTaskID = expandedTaskID
        self.isFocusedCard = isFocusedCard
        self.onSelectTask = onSelectTask
        self.onSelectAllInGroup = onSelectAllInGroup
        self.onDeselectAllInGroup = onDeselectAllInGroup
        self.onToggleExpandTask = onToggleExpandTask
        self.onToggleStatus = onToggleStatus
        self.onEditTask = onEditTask
        self.onDeleteTask = onDeleteTask
        self.onMoveTask = onMoveTask
        self.onBatchSetStatus = onBatchSetStatus
        self.onBatchMove = onBatchMove
        self.onBatchDelete = onBatchDelete
        self.onAddTask = onAddTask
        self.onClearCompleted = onClearCompleted
        self.onToggleFocusCard = onToggleFocusCard
        self.onOpenFreshStart = onOpenFreshStart
        self.onOpenStaleReview = onOpenStaleReview
    }
    
    private var completedCount: Int {
        tasks.filter { $0.status == .completed }.count
    }
    
    private var completionFraction: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(completedCount) / Double(tasks.count)
    }
    
    private var selectedTasksInCard: [TodoTask] {
        tasks.filter { selectedTaskIDs.contains($0.id) }
    }
    
    private var isAllSelectedInCard: Bool {
        !tasks.isEmpty && selectedTasksInCard.count == tasks.count
    }
    
    private var shouldShowBatchBar: Bool {
        !selectedTasksInCard.isEmpty && (selectedTasksInCard.count > 1 || isAllSelectedInCard || isSelectionModeActive)
    }
    
    private var inlineParsed: ParsedQuickAdd {
        guard !newTodoText.isEmpty else {
            return ParsedQuickAdd(cleanTitle: "", targetList: listType, isEvening: false, reminderDate: nil, matchedDateString: nil)
        }
        return QuickAddParser.parse(newTodoText)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card Header
            cardHeader
            
            // Per-Group Batch Action Bar (appears when Select All or multi-select is active)
            if shouldShowBatchBar {
                batchActionBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            Divider()
                .background(SlateColors.hair)
            
            // Calendar Events Peek Strip (Today card)
            if listType == .today && AppSettings.shared.showCalendarPeekInToday && !calendarPeek.todayEvents.isEmpty {
                calendarStripView
                    .padding(.top, 8)
            }
            
            // Task List Content
            if tasks.isEmpty {
                emptyStateView
            } else {
                let daytimeTasks = (listType == .today) ? tasks.filter { !$0.isEvening } : tasks
                let eveningTasks = (listType == .today) ? tasks.filter { $0.isEvening } : []
                
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(daytimeTasks) { task in
                            taskRow(for: task)
                        }
                        
                        if listType == .today && !eveningTasks.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "moon.stars.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(SlateColors.secondary)
                                Text("This Evening")
                                    .font(.geist(.semiBold, size: 12))
                                    .foregroundColor(SlateColors.secondary)
                                Rectangle()
                                    .fill(SlateColors.hair)
                                    .frame(height: 1)
                            }
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                            .padding(.horizontal, 4)
                            
                            ForEach(eveningTasks) { task in
                                taskRow(for: task)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 2)
                }
            }
            
            Spacer(minLength: 0)
            
            Divider()
                .background(SlateColors.hair)
            
            // Inline Quick-Add Footer
            inlineInputBar
        }
        .padding(20)
        .background(SlateColors.cardBackground(for: listType))
        .clipShape(RoundedRectangle(cornerRadius: SlateTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SlateTheme.cardRadius, style: .continuous)
                .stroke(
                    isTargetedForDrop ? SlateColors.primary : SlateColors.cardBorder,
                    lineWidth: isTargetedForDrop ? 2.0 : 1.0
                )
        )
        .scaleEffect(isTargetedForDrop ? 1.014 : 1.0)
        .shadow(
            color: Color.black.opacity(isTargetedForDrop ? 0.16 : 0.06),
            radius: isTargetedForDrop ? 18 : 8,
            x: 0,
            y: isTargetedForDrop ? 8 : 3
        )
        .animation(SlateTheme.snapSpring, value: isTargetedForDrop)
        .animation(SlateTheme.snapSpring, value: shouldShowBatchBar)
        .onChange(of: selectedTasksInCard.isEmpty) { _, isEmpty in
            if isEmpty {
                isSelectionModeActive = false
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first, let uuid = UUID(uuidString: idString) else { return false }
            if let task = DataStore.shared.task(with: uuid) {
                onMoveTask(task, listType)
                UndoToastManager.shared.showInfo("Moved to \(listType.title)", targetList: listType)
                return true
            }
            return false
        } isTargeted: { targeted in
            isTargetedForDrop = targeted
        }
    }
    
    // MARK: - Card Header with Progress Ring, Select All & Focus Controls
    
    private var cardHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(listType.title)
                        .font(.geist(.bold, size: 19))
                        .foregroundColor(SlateColors.primary)
                    
                    // Progress Ring + Monospace Counter Pill (click to Mark All Complete / Reset)
                    let isAllDone = !tasks.isEmpty && completedCount == tasks.count
                    Button(action: {
                        guard !tasks.isEmpty else { return }
                        toggleMarkAllCompleteInGroup()
                    }) {
                        HStack(spacing: 5) {
                            if !tasks.isEmpty {
                                ZStack {
                                    if isAllDone {
                                        Circle()
                                            .fill(SlateColors.primary)
                                            .frame(width: 12, height: 12)
                                            .transition(.scale.combined(with: .opacity))
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundColor(SlateColors.primaryInverted)
                                    } else {
                                        Circle()
                                            .stroke(SlateColors.primary.opacity(0.16), lineWidth: 2)
                                            .frame(width: 11, height: 11)
                                        
                                        Circle()
                                            .trim(from: 0, to: completionFraction)
                                            .stroke(
                                                SlateColors.primary,
                                                style: StrokeStyle(lineWidth: 2, lineCap: .round)
                                            )
                                            .rotationEffect(.degrees(-90))
                                            .frame(width: 11, height: 11)
                                            .animation(SlateTheme.easeSpring, value: completionFraction)
                                    }
                                }
                                .scaleEffect(isAllDone ? 1.08 : 1.0)
                                .animation(SlateTheme.snapSpring, value: isAllDone)
                            }
                            
                            Text(!tasks.isEmpty ? "\(completedCount)/\(tasks.count)" : "0")
                                .font(.geist(.mono, size: 11.5))
                                .foregroundColor(isAllDone ? SlateColors.primary : SlateColors.secondary)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(SlateColors.hair)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(isAllDone ? "Reset all in \(listType.title) to To Do" : "Mark all \(tasks.count) in \(listType.title) Complete")
                }
                
                if listType == .today {
                    HStack(spacing: 6) {
                        Text(formattedTodayDate)
                            .font(.geist(.mono, size: 10.5))
                            .foregroundColor(SlateColors.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        let streak = AppSettings.shared.activeStreak
                        if streak > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 8.5))
                                Text("\(streak)d streak")
                                    .font(.geist(.mono, size: 9.5))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                            .help("\(streak)-day daily completion streak!")
                        }
                        
                        let carryover = DataStore.shared.carryoverTodayTasks.count
                        if carryover > 0 {
                            Button(action: { onOpenFreshStart?() }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "sun.and.horizon.fill")
                                        .font(.system(size: 8.5))
                                    Text("Rollover (\(carryover))")
                                        .font(.geist(.mono, size: 9.5))
                                }
                                .foregroundColor(.orange)
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 1.5)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Triage \(carryover) uncompleted to-do\(carryover == 1 ? "" : "s") from previous days")
                        }
                        
                        let cap = AppSettings.shared.todayCapLimit
                        let remaining = tasks.filter { $0.status != .completed }.count
                        if cap > 0 && remaining > cap {
                            HStack(spacing: 3) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 8))
                                Text("Heavy (\(remaining)/\(cap))")
                                    .font(.geist(.mono, size: 9.5))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                            .help("Today is carrying \(remaining) to-dos (recommended limit: \(cap)). Consider moving some to Next.")
                        }
                    }
                } else if listType == .someday {
                    HStack(spacing: 6) {
                        Text(listType.subtitle)
                            .font(.geist(.regular, size: 11))
                            .foregroundColor(SlateColors.secondary.opacity(0.85))
                            .lineLimit(1)
                        
                        let staleCount = DataStore.shared.staleSomedayTasks.count
                        if staleCount > 0 {
                            Button(action: { onOpenStaleReview?() }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "hourglass")
                                        .font(.system(size: 8.5))
                                    Text("Stale (\(staleCount))")
                                        .font(.geist(.mono, size: 9.5))
                                }
                                .foregroundColor(.purple)
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 1.5)
                                .background(Color.purple.opacity(0.12))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Review \(staleCount) stale idea\(staleCount == 1 ? "" : "s") untouched for 30+ days")
                        }
                    }
                } else {
                    Text(listType.subtitle)
                        .font(.geist(.regular, size: 11))
                        .foregroundColor(SlateColors.secondary.opacity(0.85))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Header Action Buttons
            let isAllDoneInCard = !tasks.isEmpty && completedCount == tasks.count
            HStack(spacing: 6) {
                // Focus Mode Toggle Button
                Button(action: {
                    onToggleFocusCard(listType)
                }) {
                    Image(systemName: isFocusedCard ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isFocusedCard ? SlateColors.primaryInverted : SlateColors.secondary)
                        .frame(width: 26, height: 26)
                        .background(isFocusedCard ? SlateColors.primary : SlateColors.hair.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isFocusedCard ? "Exit Focus Mode (⌘0)" : "Focus on \(listType.title) (\(listType.shortcutDisplay))")
                
                Menu {
                    Button(isAllDoneInCard ? "Mark All Incomplete in \(listType.title)" : "Mark All Complete in \(listType.title) (\(tasks.count - completedCount) left)") {
                        toggleMarkAllCompleteInGroup()
                    }
                    .disabled(tasks.isEmpty)
                    
                    Button(isAllSelectedInCard ? "Deselect All in \(listType.title)" : "Select All in \(listType.title) (\(tasks.count))") {
                        withAnimation(SlateTheme.snapSpring) {
                            if isAllSelectedInCard {
                                isSelectionModeActive = false
                                onDeselectAllInGroup(listType)
                            } else {
                                isSelectionModeActive = true
                                onSelectAllInGroup(listType)
                            }
                        }
                    }
                    .disabled(tasks.isEmpty)
                    
                    Divider()
                    
                    Button("Add To-Do to \(listType.title)...") {
                        isInputFocused = true
                    }
                    
                    Divider()
                    
                    Button(isFocusedCard ? "Show All Cards (⌘0)" : "Focus on \(listType.title) (\(listType.shortcutDisplay))") {
                        onToggleFocusCard(listType)
                    }
                    Divider()
                    Button("Clear Completed (\(completedCount))") {
                        onClearCompleted(listType)
                    }
                    .disabled(completedCount == 0)
                    
                    if listType == .today {
                        Divider()
                        Button("Fresh Start Ritual...") {
                            onOpenFreshStart?()
                        }
                    } else if listType == .someday {
                        Divider()
                        Button("Review Stale Ideas... (\(DataStore.shared.staleSomedayTasks.count))") {
                            onOpenStaleReview?()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SlateColors.secondary)
                        .frame(width: 26, height: 26)
                        .background(SlateColors.hair.opacity(0.5))
                        .clipShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .frame(width: 26, height: 26)
            }
        }
        .padding(.bottom, 14)
    }
    
    private func toggleMarkAllCompleteInGroup() {
        guard !tasks.isEmpty else { return }
        let allDone = completedCount == tasks.count
        let targetStatus: TaskStatus = allDone ? .incomplete : .completed
        onBatchSetStatus(tasks, targetStatus)
        if targetStatus == .completed {
            UndoToastManager.shared.showInfo("Completed all \(tasks.count) in \(listType.title)")
        } else {
            UndoToastManager.shared.showInfo("Reset all \(tasks.count) in \(listType.title)")
        }
    }
    
    // MARK: - Per-Group Batch Action Bar (Linear / Superlist style)
    
    private var batchActionBar: some View {
        let selected = selectedTasksInCard
        let allSelectedCompleted = !selected.isEmpty && selected.allSatisfy { $0.status == .completed }
        
        return HStack(spacing: 6) {
            // Selection count & Select All / Clear toggle
            Button(action: {
                withAnimation(SlateTheme.snapSpring) {
                    if isAllSelectedInCard {
                        isSelectionModeActive = false
                        onDeselectAllInGroup(listType)
                    } else {
                        isSelectionModeActive = true
                        onSelectAllInGroup(listType)
                    }
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isAllSelectedInCard ? "checkmark.square.fill" : "minus.square.fill")
                        .font(.system(size: 11))
                    Text("\(selected.count)/\(tasks.count)")
                        .font(.geist(.mono, size: 11))
                }
                .foregroundColor(SlateColors.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(SlateColors.hair)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(isAllSelectedInCard ? "Deselect all in \(listType.title)" : "Select all \(tasks.count) in \(listType.title)")
            
            // Mark All Done / Reset
            Button(action: {
                let targetStatus: TaskStatus = allSelectedCompleted ? .incomplete : .completed
                onBatchSetStatus(selected, targetStatus)
            }) {
                HStack(spacing: 3.5) {
                    Image(systemName: allSelectedCompleted ? "arrow.uturn.backward" : "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                    Text(allSelectedCompleted ? "Reset" : "Done")
                        .font(.geist(.medium, size: 11))
                }
                .foregroundColor(SlateColors.primaryInverted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(SlateColors.primary)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(allSelectedCompleted ? "Reset selected to To Do" : "Mark selected as Done (Space)")
            
            // Move Selected to other groups
            ForEach(TaskListType.allCases) { target in
                if target != listType {
                    Button(action: {
                        onBatchMove(selected, target)
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8, weight: .bold))
                            Text(target.title)
                                .font(.geist(.mono, size: 10.5))
                        }
                        .foregroundColor(SlateColors.primary)
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 3.5)
                        .background(SlateColors.hair)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Move \(selected.count) selected to \(target.title) (\(target.shortcutNumber))")
                }
            }
            
            Spacer(minLength: 2)
            
            // Delete Selected
            Button(role: .destructive, action: {
                onBatchDelete(selected)
                isSelectionModeActive = false
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red)
                    .frame(width: 24, height: 24)
                    .background( Color.red.opacity(0.12) )
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Delete \(selected.count) selected (⌘⌫)")
            
            // Clear selection X button
            Button(action: {
                withAnimation(SlateTheme.snapSpring) {
                    isSelectionModeActive = false
                    onDeselectAllInGroup(listType)
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(SlateColors.secondary)
                    .frame(width: 22, height: 22)
                    .background(SlateColors.hair)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Clear selection (Esc)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SlateColors.hair.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SlateColors.cardBorder, lineWidth: 1)
        )
        .padding(.bottom, 10)
    }
    
    // MARK: - Calendar Events Strip Peek
    
    private var calendarStripView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(calendarPeek.todayEvents) { event in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(event.isNow ? Color.orange : SlateColors.secondary.opacity(0.6))
                            .frame(width: 6, height: 6)
                        
                        Text(event.formattedTime)
                            .font(.geist(.mono, size: 10.5))
                            .foregroundColor(event.isNow ? .orange : SlateColors.secondary)
                        
                        Text(event.title)
                            .font(.geist(.medium, size: 12))
                            .foregroundColor(SlateColors.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(SlateColors.hair.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(.bottom, 6)
            .padding(.horizontal, 2)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: emptyIconName)
                .font(.system(size: 26, weight: .light))
                .foregroundColor(SlateColors.secondary.opacity(0.45))
            Text(emptyMessage)
                .font(.geist(.regular, size: 13.5))
                .foregroundColor(SlateColors.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { isInputFocused = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("Add Item")
                        .font(.geist(.medium, size: 12))
                }
                .foregroundColor(SlateColors.primary.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(SlateColors.hair)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
    
    // MARK: - Inline Quick-Add Footer with Live Date Detection
    
    private var inlineInputBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isInputFocused ? SlateColors.primary : SlateColors.secondary)
            
            TextField("Add to \(listType.title)...", text: $newTodoText)
                .textFieldStyle(.plain)
                .font(.geist(.regular, size: 14.5))
                .focused($isInputFocused)
                .onSubmit {
                    commitNewTodo()
                }
            
            // Live inline parsed reminder badge (Godspeed / Hustla style)
            if let matchedDate = inlineParsed.matchedDateString, inlineParsed.reminderDate != nil {
                HStack(spacing: 3) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 9))
                    Text(matchedDate)
                        .font(.geist(.mono, size: 10.5))
                }
                .foregroundColor(SlateColors.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(SlateColors.hair)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .transition(.scale.combined(with: .opacity))
            }
            
            // Live inline parsed recurrence badge
            if let rule = inlineParsed.recurrenceRule {
                HStack(spacing: 3) {
                    Image(systemName: "repeat")
                        .font(.system(size: 9))
                    Text(RecurrenceService.displayString(for: rule))
                        .font(.geist(.mono, size: 10.5))
                }
                .foregroundColor(SlateColors.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(SlateColors.hair)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .transition(.scale.combined(with: .opacity))
            }
            
            if !newTodoText.isEmpty {
                Button(action: commitNewTodo) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(SlateColors.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 2)
        .animation(SlateTheme.snapSpring, value: inlineParsed.reminderDate != nil)
    }
    
    @ViewBuilder
    private func taskRow(for task: TodoTask) -> some View {
        TaskRowView(
            task: task,
            isSelected: selectedTaskIDs.contains(task.id),
            isExpanded: expandedTaskID == task.id,
            onSelect: {
                let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if !flags.intersection([.command, .shift]).isEmpty {
                    isSelectionModeActive = true
                }
                onSelectTask(task, flags)
            },
            onToggleExpand: {
                withAnimation(SlateTheme.expandSpring) {
                    onToggleExpandTask(task)
                }
            },
            onToggle: { onToggleStatus(task) },
            onOpenSheet: { onEditTask(task) },
            onDelete: { onDeleteTask(task) },
            onMove: { target in onMoveTask(task, target) },
            onReorderBefore: { dragged in
                DataStore.shared.reorderTask(dragged, before: task)
            },
            onSelectAllInList: {
                withAnimation(SlateTheme.snapSpring) {
                    isSelectionModeActive = true
                    onSelectAllInGroup(listType)
                }
            },
            onMarkAllCompleteInList: {
                toggleMarkAllCompleteInGroup()
            }
        )
        .draggable(task.id.uuidString)
    }
    
    private func commitNewTodo() {
        let trimmed = newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parsed = inlineParsed
        let finalTitle = parsed.cleanTitle.isEmpty ? trimmed : parsed.cleanTitle
        onAddTask(finalTitle, listType, parsed.reminderDate, parsed.isEvening, parsed.recurrenceRule)
        newTodoText = ""
    }
    
    private static let todayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()
    
    private var formattedTodayDate: String {
        Self.todayFormatter.string(from: Date())
    }
    
    private var emptyIconName: String {
        switch listType {
        case .today:
            let isClearedToday = AppSettings.shared.lastCompletedDateString == AppSettings.streakDateFormatter.string(from: Date())
            return (AppSettings.shared.activeStreak > 0 && isClearedToday) ? "party.popper.fill" : "sun.max"
        case .next: return "calendar.badge.clock"
        case .someday: return "sparkles"
        }
    }
    
    private var emptyMessage: String {
        switch listType {
        case .today:
            let isClearedToday = AppSettings.shared.lastCompletedDateString == AppSettings.streakDateFormatter.string(from: Date())
            if AppSettings.shared.activeStreak > 0 && isClearedToday {
                return "Today cleared!\n🔥 \(AppSettings.shared.activeStreak)-day streak"
            }
            return "Clear for today.\nAdd what needs doing."
        case .next: return "No upcoming tasks.\nReady for the next sprint."
        case .someday: return "No someday ideas yet.\nJot down big dreams."
        }
    }
}
