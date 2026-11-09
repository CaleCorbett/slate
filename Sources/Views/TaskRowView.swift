import SwiftUI

public struct TaskRowView: View {
    let task: TodoTask
    let isSelected: Bool
    let isExpanded: Bool
    let onSelect: () -> Void
    let onToggleExpand: () -> Void
    let onToggle: () -> Void
    let onOpenSheet: () -> Void
    let onDelete: () -> Void
    let onMove: (TaskListType) -> Void
    let onReorderBefore: ((TodoTask) -> Void)?
    let onSelectAllInList: (() -> Void)?
    let onMarkAllCompleteInList: (() -> Void)?
    
    @ObservedObject private var focusTimer = FocusTimerService.shared
    @State private var isHovered = false
    @State private var isTargetedForRowDrop = false
    @State private var draftTitle: String = ""
    @State private var draftNotes: String = ""
    @State private var newSubItemDraft: String = ""
    @State private var showDatePickerPopover = false
    @State private var isBreakingDownWithAI = false
    @State private var aiErrorMessage: String? = nil
    @FocusState private var focusedField: InlineField?
    
    private enum InlineField {
        case title
        case notes
    }
    
    public init(
        task: TodoTask,
        isSelected: Bool = false,
        isExpanded: Bool = false,
        onSelect: @escaping () -> Void = {},
        onToggleExpand: @escaping () -> Void = {},
        onToggle: @escaping () -> Void,
        onOpenSheet: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onMove: @escaping (TaskListType) -> Void,
        onReorderBefore: ((TodoTask) -> Void)? = nil,
        onSelectAllInList: (() -> Void)? = nil,
        onMarkAllCompleteInList: (() -> Void)? = nil
    ) {
        self.task = task
        self.isSelected = isSelected
        self.isExpanded = isExpanded
        self.onSelect = onSelect
        self.onToggleExpand = onToggleExpand
        self.onToggle = onToggle
        self.onOpenSheet = onOpenSheet
        self.onDelete = onDelete
        self.onMove = onMove
        self.onReorderBefore = onReorderBefore
        self.onSelectAllInList = onSelectAllInList
        self.onMarkAllCompleteInList = onMarkAllCompleteInList
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Row Header
            HStack(alignment: .center, spacing: 13) {
                StatusToggleView(status: task.status, action: onToggle)
                
                if isExpanded {
                    TextField("Task title", text: $draftTitle)
                        .font(.geist(.semiBold, size: 15.5))
                        .foregroundColor(SlateColors.primary)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .title)
                        .onSubmit {
                            commitInlineEdits()
                            onToggleExpand()
                        }
                } else {
                    let isCompleted = (task.status == .completed)
                    // Title with animated left-to-right strikethrough line
                    Text(task.title)
                        .font(.geist(.medium, size: 15.5))
                        .foregroundColor(isCompleted ? SlateColors.secondary : (task.isStaleSomeday && !isHovered ? SlateColors.secondary : SlateColors.primary))
                        .opacity(task.isStaleSomeday && !isCompleted && !isHovered ? 0.72 : 1.0)
                        .lineLimit(2)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(SlateColors.secondary)
                                .frame(height: 1.5)
                                .scaleEffect(x: isCompleted ? 1.0 : 0.0, y: 1.0, anchor: .leading)
                                .animation(SlateTheme.easeSpring, value: isCompleted)
                                .allowsHitTesting(false)
                        }
                        .animation(SlateTheme.easeSpring, value: isCompleted)
                }
                
                Spacer(minLength: 6)
                
                // Right-aligned Meta Badges & Hover Quick-Triage Actions
                if !isExpanded {
                    trailingCompactAccessories
                } else {
                    Button(action: {
                        commitInlineEdits()
                        onToggleExpand()
                    }) {
                        KeycapBadge("↵ Done")
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Things 3-style Inline Unfolding Detail Drawer
            if isExpanded {
                expandedDetailContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, isExpanded ? 14 : 12)
        .padding(.vertical, isExpanded ? 14 : 11)
        .background(
            RoundedRectangle(cornerRadius: SlateTheme.rowRadius, style: .continuous)
                .fill(rowBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SlateTheme.rowRadius, style: .continuous)
                .strokeBorder(rowBorderColor, lineWidth: isExpanded || isSelected ? 1.0 : 0)
        )
        .overlay(alignment: .top) {
            if isTargetedForRowDrop {
                Capsule()
                    .fill(SlateColors.primary)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
                    .offset(y: -2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .shadow(
            color: Color.black.opacity(isExpanded ? 0.09 : 0.0),
            radius: isExpanded ? 8 : 0,
            x: 0,
            y: isExpanded ? 3 : 0
        )
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first,
                  let uuid = UUID(uuidString: idString),
                  uuid != task.id,
                  let dragged = DataStore.shared.task(with: uuid) else {
                return false
            }
            if let onReorderBefore {
                onReorderBefore(dragged)
            } else {
                DataStore.shared.reorderTask(dragged, before: task)
            }
            return true
        } isTargeted: { targeted in
            withAnimation(SlateTheme.snapSpring) {
                isTargetedForRowDrop = targeted
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
        .onTapGesture(count: 2) {
            onSelect()
            onToggleExpand()
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                draftTitle = task.title
                draftNotes = task.notes ?? ""
                focusedField = .notes
            } else {
                commitInlineEdits()
            }
        }
        .onAppear {
            draftTitle = task.title
            draftNotes = task.notes ?? ""
        }
        .contextMenu {
            Button(isExpanded ? "Collapse Inline Editor" : "Expand Inline (↵)") {
                onToggleExpand()
            }
            Button("Open Detail Sheet...") {
                onOpenSheet()
            }
            Button {
                breakDownWithAI()
            } label: {
                Label("Break Down with AI (✨)", systemImage: "sparkles")
            }
            .disabled(isBreakingDownWithAI)
            
            Divider()
            
            if focusTimer.activeTaskID == task.id {
                Button(focusTimer.isPaused ? "Resume Focus Session" : "Pause Focus Session") {
                    if focusTimer.isPaused {
                        focusTimer.resumeTimer()
                    } else {
                        focusTimer.pauseTimer()
                    }
                }
                Button("Stop Focus Session") {
                    focusTimer.stopTimer(logElapsed: true)
                }
            } else {
                Menu("Start Focus Timer") {
                    Button("25 Minutes (Standard)") {
                        focusTimer.startTimer(for: task, durationMinutes: 25)
                    }
                    Button("15 Minutes (Sprint)") {
                        focusTimer.startTimer(for: task, durationMinutes: 15)
                    }
                    Button("45 Minutes (Deep Work)") {
                        focusTimer.startTimer(for: task, durationMinutes: 45)
                    }
                    Button("60 Minutes") {
                        focusTimer.startTimer(for: task, durationMinutes: 60)
                    }
                }
            }
            
            if let onSelectAllInList {
                Button("Select All in \(task.list.title) (⌘A)") {
                    onSelectAllInList()
                }
            }
            if let onMarkAllCompleteInList {
                Button("Mark All Complete in \(task.list.title) (⇧⌘↵)") {
                    onMarkAllCompleteInList()
                }
            }
            
            Divider()
            
            if task.list == .today {
                Button(task.isEvening ? "Move to Daytime" : "Move to This Evening") {
                    task.isEvening.toggle()
                    try? DataStore.shared.context.save()
                    DataStore.shared.reloadAll()
                }
                
                Divider()
            }
            
            Menu("Move To") {
                ForEach(TaskListType.allCases) { target in
                    if task.list != target {
                        Button("\(target.title) (\(target.shortcutNumber))") {
                            onMove(target)
                        }
                    }
                }
            }
            
            Divider()
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Trailing Compact Accessories & Hover Quick-Triage
    
    @ViewBuilder
    private var trailingCompactAccessories: some View {
        HStack(spacing: 6) {
            // Active Focus Timer Indicator
            if focusTimer.activeTaskID == task.id {
                HStack(spacing: 4) {
                    Image(systemName: focusTimer.isPaused ? "pause.fill" : "timer")
                        .font(.system(size: 8.5))
                    Text(focusTimer.formattedRemainingTime)
                        .font(.geist(.mono, size: 10.5))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.orange.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .help("Focus session active — click to pause/resume")
                .onTapGesture {
                    if focusTimer.isPaused {
                        focusTimer.resumeTimer()
                    } else {
                        focusTimer.pauseTimer()
                    }
                }
            } else if task.focusSecondsLogged > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "timer")
                        .font(.system(size: 8))
                    Text("\(max(1, task.focusSecondsLogged / 60))m")
                        .font(.geist(.mono, size: 9))
                }
                .foregroundColor(SlateColors.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(SlateColors.hair.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .help("Logged \(task.focusSecondsLogged / 60) minutes of focus")
            }
            
            // Hover Quick-Triage Actions (Linear / Superlist style)
            if isHovered || isSelected {
                let target = task.list.primaryQuickMoveTarget
                Button(action: {
                    onMove(target)
                    UndoToastManager.shared.showInfo("Moved to \(target.title)", targetList: target)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: target == .today ? "arrow.turn.left.up" : "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(target.title)
                            .font(.geist(.mono, size: 10.5))
                    }
                    .foregroundColor(SlateColors.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(SlateColors.hair)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Move to \(target.title) (\(target.shortcutNumber))")
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                
                Button(action: onToggleExpand) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(SlateColors.secondary)
                        .frame(width: 20, height: 20)
                        .background(SlateColors.hair)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Expand notes & details (↵)")
                .transition(.opacity)
            }
            
            // Note indicator badge
            if let notes = task.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: onToggleExpand) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundColor(SlateColors.secondary)
                }
                .buttonStyle(.plain)
                .help("Has notes — click to expand")
            }
            
            // Recurrence Indicator Badge
            if let rule = task.recurrenceRule, !rule.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "repeat")
                        .font(.system(size: 8.5))
                    Text(RecurrenceService.displayString(for: rule))
                        .font(.geist(.mono, size: 9.5))
                }
                .foregroundColor(SlateColors.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(SlateColors.hair)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .help("Repeats \(RecurrenceService.displayString(for: rule))")
            }
            
            // Checklist Progress Badge
            if let summary = task.checklistSummary {
                HStack(spacing: 3) {
                    Image(systemName: summary.completed == summary.total ? "checkmark.circle.fill" : "checklist")
                        .font(.system(size: 8.5))
                    Text("\(summary.completed)/\(summary.total)")
                        .font(.geist(.mono, size: 9.5))
                }
                .foregroundColor(summary.completed == summary.total ? .green : SlateColors.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(SlateColors.hair.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .help("Sub-tasks: \(summary.completed) of \(summary.total) completed")
            }
            
            // Stale Someday Indicator Badge
            if task.isStaleSomeday {
                HStack(spacing: 3) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 8.5))
                    Text("\(task.daysUntouched)d")
                        .font(.geist(.mono, size: 9.5))
                }
                .foregroundColor(SlateColors.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(SlateColors.hair.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .help("Untouched for \(task.daysUntouched) days")
            }
            
            // Monospace Reminder Badge
            if let reminder = task.reminderDate {
                HStack(spacing: 3.5) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 9))
                    Text(formatTime(reminder))
                        .font(.geist(.mono, size: 11))
                }
                .foregroundColor(isOverdue(reminder) ? .red : SlateColors.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(SlateColors.hair)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
    }
    
    // MARK: - Things 3-Style Inline Expanded Card Content
    
    private var expandedDetailContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .background(SlateColors.hair)
                .padding(.top, 8)
            
            // Inline Notes Field
            TextField("Add notes, links, or sub-steps...", text: $draftNotes, axis: .vertical)
                .font(.geist(.regular, size: 13.5))
                .foregroundColor(SlateColors.primary.opacity(0.9))
                .textFieldStyle(.plain)
                .lineLimit(2...6)
                .focused($focusedField, equals: .notes)
                .onChange(of: draftNotes) { _, newValue in
                    guard isExpanded else { return }
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    let normalized: String? = trimmed.isEmpty ? nil : newValue
                    guard task.notes != normalized else { return }
                    task.notes = normalized
                    try? DataStore.shared.context.save()
                }
            
            // Clickable detected URLs in notes
            if !detectedURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(detectedURLs, id: \.absoluteString) { url in
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Image(systemName: "link")
                                        .font(.system(size: 9, weight: .bold))
                                    Text(url.host ?? url.absoluteString)
                                        .font(.geist(.mono, size: 11))
                                        .lineLimit(1)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .foregroundColor(SlateColors.primary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(SlateColors.hair)
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            
            // Sub-tasks checklist inside expanded row
            let subItems = task.checklist
            VStack(alignment: .leading, spacing: 6) {
                ForEach(subItems) { item in
                    HStack(spacing: 8) {
                        Button {
                            toggleSubItem(item.id)
                        } label: {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11.5))
                                .foregroundColor(item.isCompleted ? .green : SlateColors.secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Text(item.title)
                            .font(.geist(.regular, size: 12.5))
                            .foregroundColor(item.isCompleted ? SlateColors.secondary : SlateColors.primary)
                            .strikethrough(item.isCompleted)
                        
                        Spacer()
                        
                        Button {
                            deleteSubItem(item.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8))
                                .foregroundColor(SlateColors.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 1)
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 9))
                        .foregroundColor(SlateColors.secondary)
                    TextField("Add sub-task...", text: $newSubItemDraft)
                        .font(.geist(.regular, size: 12))
                        .textFieldStyle(.plain)
                        .onSubmit {
                            addSubItem()
                        }
                    
                    Spacer()
                    
                    Button {
                        breakDownWithAI()
                    } label: {
                        HStack(spacing: 4) {
                            if isBreakingDownWithAI {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                            }
                            Text(isBreakingDownWithAI ? "Generating..." : "AI Breakdown")
                                .font(.geist(.medium, size: 10.5))
                                .foregroundColor(SlateColors.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SlateColors.hair.opacity(0.6))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBreakingDownWithAI)
                    .help("Generate subtasks automatically with AI")
                }
                .padding(.top, 2)
                
                if let err = aiErrorMessage {
                    Text(err)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(.top, 1)
                }
            }
            .padding(8)
            .background(SlateColors.hair.opacity(0.3))
            .cornerRadius(6)
            
            // Quick Controls Bar: Reminder Presets + List Switcher + Actions
            HStack(spacing: 6) {
                // Reminder Pill / Picker
                Menu {
                    Button("Later Today (5:00 PM)") {
                        setQuickReminder(hour: 17, dayOffset: 0)
                    }
                    Button("Tomorrow Morning (9:00 AM)") {
                        setQuickReminder(hour: 9, dayOffset: 1)
                    }
                    Button("Next Monday (9:00 AM)") {
                        setNextMondayReminder()
                    }
                    Divider()
                    Button("Custom Date & Time...") {
                        onOpenSheet()
                    }
                    if task.reminderDate != nil {
                        Divider()
                        Button("Clear Reminder", role: .destructive) {
                            clearReminder()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: task.reminderDate != nil ? "bell.badge.fill" : "bell")
                            .font(.system(size: 10))
                        Text(task.reminderDate.map { formatTime($0) } ?? "Remind")
                            .font(.geist(.mono, size: 11))
                    }
                    .foregroundColor(task.reminderDate != nil ? SlateColors.primary : SlateColors.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(SlateColors.hair)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                // Move List Pills
                ForEach(TaskListType.allCases) { list in
                    if list != task.list {
                        Button(action: {
                            commitInlineEdits()
                            onMove(list)
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8, weight: .bold))
                                Text(list.title)
                                    .font(.geist(.mono, size: 10.5))
                            }
                            .foregroundColor(SlateColors.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3.5)
                            .background(SlateColors.hair.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
                
                Button(action: onOpenSheet) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11))
                        .foregroundColor(SlateColors.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Open full editor sheet")
                
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Delete task (⌘⌫)")
            }
        }
    }
    
    // MARK: - Helpers
    
    private var rowBackgroundColor: Color {
        if isExpanded {
            return SlateColors.hair.opacity(0.75)
        } else if isSelected {
            return SlateColors.hair.opacity(0.62)
        } else if isHovered {
            return SlateColors.hair.opacity(0.42)
        }
        return Color.clear
    }
    
    private var rowBorderColor: Color {
        if isExpanded {
            return SlateColors.primary.opacity(0.22)
        } else if isSelected {
            return SlateColors.primary.opacity(0.18)
        }
        return Color.clear
    }
    
    private func commitInlineEdits() {
        var didChange = false
        let cleanTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty && cleanTitle != task.title {
            task.title = cleanTitle
            didChange = true
        }
        let cleanNotes = draftNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes: String? = cleanNotes.isEmpty ? nil : draftNotes
        if task.notes != normalizedNotes {
            task.notes = normalizedNotes
            didChange = true
        }
        if didChange {
            try? DataStore.shared.context.save()
            DataStore.shared.reloadAll()
        }
    }
    
    private func setQuickReminder(hour: Int, dayOffset: Int) {
        let cal = Calendar.current
        guard let baseDay = cal.date(byAdding: .day, value: dayOffset, to: Date()),
              let target = cal.date(bySettingHour: hour, minute: 0, second: 0, of: baseDay) else { return }
        let finalDate = target > Date() ? target : target.addingTimeInterval(86400)
        task.reminderDate = finalDate
        try? DataStore.shared.context.save()
        ReminderService.shared.scheduleReminder(for: task)
        DataStore.shared.refreshTrigger = UUID()
    }
    
    private func setNextMondayReminder() {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.weekday = 2 // Monday
        comps.hour = 9
        comps.minute = 0
        if let nextMon = cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime) {
            task.reminderDate = nextMon
            try? DataStore.shared.context.save()
            ReminderService.shared.scheduleReminder(for: task)
            DataStore.shared.refreshTrigger = UUID()
        }
    }
    
    private func toggleSubItem(_ id: UUID) {
        var items = task.checklist
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isCompleted.toggle()
            task.checklist = items
            try? DataStore.shared.context.save()
            DataStore.shared.reloadAll()
        }
    }
    
    private func deleteSubItem(_ id: UUID) {
        var items = task.checklist
        items.removeAll(where: { $0.id == id })
        task.checklist = items
        try? DataStore.shared.context.save()
        DataStore.shared.reloadAll()
    }
    
    private func addSubItem() {
        let trimmed = newSubItemDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = task.checklist
        items.append(ChecklistItem(title: trimmed))
        task.checklist = items
        newSubItemDraft = ""
        try? DataStore.shared.context.save()
        DataStore.shared.reloadAll()
    }
    
    private func breakDownWithAI() {
        guard !isBreakingDownWithAI else { return }
        isBreakingDownWithAI = true
        aiErrorMessage = nil
        
        Task {
            do {
                let items = try await AIService.shared.breakdownTask(title: task.title, notes: task.notes)
                await MainActor.run {
                    var current = task.checklist
                    for title in items {
                        if !current.contains(where: { $0.title.lowercased() == title.lowercased() }) {
                            current.append(ChecklistItem(title: title))
                        }
                    }
                    task.checklist = current
                    task.lastTouchedDate = Date()
                    try? DataStore.shared.context.save()
                    DataStore.shared.reloadAll()
                    SoundManager.shared.play(.button)
                    isBreakingDownWithAI = false
                }
            } catch {
                await MainActor.run {
                    isBreakingDownWithAI = false
                    aiErrorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func clearReminder() {
        task.reminderDate = nil
        try? DataStore.shared.context.save()
        ReminderService.shared.cancelReminder(for: task)
        DataStore.shared.refreshTrigger = UUID()
    }
    
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    
    private var detectedURLs: [URL] {
        guard !draftNotes.isEmpty, let detector = Self.linkDetector else { return [] }
        let matches = detector.matches(in: draftNotes, options: [], range: NSRange(location: 0, length: draftNotes.utf16.count))
        return matches.compactMap { $0.url }
    }
    
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()
    
    private func formatTime(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        } else {
            return Self.dateTimeFormatter.string(from: date)
        }
    }
    
    private func isOverdue(_ date: Date) -> Bool {
        task.status != .completed && date < Date()
    }
}
