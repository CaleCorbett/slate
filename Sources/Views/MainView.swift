import SwiftUI
import SwiftData
import AppKit

public struct MainView: View {
    @ObservedObject private var store = DataStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var hotKey = GlobalHotKeyManager.shared
    @ObservedObject private var toastManager = UndoToastManager.shared
    @ObservedObject private var focusFilter = FocusFilterService.shared
    
    @State private var editingTask: TodoTask? = nil
    @State private var isShowingQuickAdd: Bool = false
    @State private var isShowingArchive: Bool = false
    @State private var isShowingSettings: Bool = false
    @State private var isShowingFreshStart: Bool = false
    @State private var isShowingStaleReview: Bool = false
    @State private var isShowingCommandPalette: Bool = false
    @State private var isShowingImport: Bool = false
    
    // Focus Mode, Multi-Selection & Keyboard Navigation State
    @State private var focusedList: TaskListType? = nil
    @State private var activeList: TaskListType = .today
    @State private var selectedTaskIDs: Set<UUID> = []
    @State private var lastSelectedTaskID: UUID? = nil
    @State private var expandedTaskID: UUID? = nil
    @State private var keyMonitor: Any? = nil
    
    public init() {}
    
    private var visibleLists: [TaskListType] {
        if let focused = focusedList {
            return [focused]
        }
        if focusFilter.isFocusFilterActive {
            if let target = focusFilter.activeFilterListName {
                if target == "today" { return [.today] }
                if target == "next" { return [.next] }
                if target == "someday" { return [.someday] }
            }
            if focusFilter.hideSomedayActive {
                return [.today, .next]
            }
        }
        return TaskListType.allCases
    }
    
    public var body: some View {
        ZStack {
            // Background
            SlateColors.bg
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Main Header Bar
                headerBar
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 18)
                
                // The 3 Signature Lists (or Single Focused Card)
                GeometryReader { geo in
                    let isSingleFocus = (focusedList != nil)
                    let totalGaps = CGFloat(max(0, visibleLists.count - 1)) * 18.0
                    let availableWidth = max(0, geo.size.width - 56.0 - totalGaps)
                    let calculatedCardWidth = availableWidth / CGFloat(max(1, visibleLists.count))
                    let cardWidth = isSingleFocus
                        ? min(720, max(420, geo.size.width - 64))
                        : max(340, calculatedCardWidth)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 18) {
                            if isSingleFocus {
                                Spacer(minLength: 0)
                            }
                            
                            ForEach(visibleLists) { listType in
                                TaskListCardView(
                                    listType: listType,
                                    tasks: store.tasks(for: listType),
                                    selectedTaskIDs: selectedTaskIDs,
                                    expandedTaskID: expandedTaskID,
                                    isFocusedCard: focusedList == listType,
                                    onSelectTask: { task, flags in
                                        handleTaskSelection(task, flags: flags)
                                    },
                                    onSelectAllInGroup: { group in
                                        selectAll(in: group)
                                    },
                                    onDeselectAllInGroup: { group in
                                        deselectAll(in: group)
                                    },
                                    onToggleExpandTask: { task in
                                        activeList = task.list
                                        selectedTaskIDs = [task.id]
                                        lastSelectedTaskID = task.id
                                        if expandedTaskID == task.id {
                                            expandedTaskID = nil
                                        } else {
                                            expandedTaskID = task.id
                                        }
                                    },
                                    onToggleStatus: { store.toggleTaskStatus($0) },
                                    onEditTask: { editingTask = $0 },
                                    onDeleteTask: { task in
                                        selectedTaskIDs.remove(task.id)
                                        if lastSelectedTaskID == task.id { lastSelectedTaskID = selectedTaskIDs.first }
                                        if expandedTaskID == task.id { expandedTaskID = nil }
                                        store.deleteTask(task)
                                    },
                                    onMoveTask: { task, target in
                                        store.moveTask(task, to: target)
                                    },
                                    onBatchSetStatus: { batch, status in
                                        store.setStatus(status, for: batch)
                                    },
                                    onBatchMove: { batch, target in
                                        store.moveTasks(batch, to: target)
                                        for item in batch {
                                            selectedTaskIDs.remove(item.id)
                                        }
                                        UndoToastManager.shared.showInfo(
                                            "Moved \(batch.count) to \(target.title)",
                                            targetList: target
                                        )
                                    },
                                    onBatchDelete: { batch in
                                        for item in batch {
                                            selectedTaskIDs.remove(item.id)
                                            if expandedTaskID == item.id { expandedTaskID = nil }
                                        }
                                        lastSelectedTaskID = selectedTaskIDs.first
                                        store.deleteTasks(batch)
                                    },
                                    onAddTask: { title, list, reminder, isEvening, recurrence in
                                        store.addTask(
                                            title: title,
                                            to: list,
                                            reminderDate: reminder,
                                            isEvening: isEvening,
                                            recurrenceRule: recurrence
                                        )
                                    },
                                    onClearCompleted: { store.clearCompleted(in: $0) },
                                    onToggleFocusCard: { target in
                                        withAnimation(SlateTheme.easeSpring) {
                                            focusedList = (focusedList == target) ? nil : target
                                            activeList = target
                                        }
                                    },
                                    onOpenFreshStart: {
                                        isShowingFreshStart = true
                                    },
                                    onOpenStaleReview: {
                                        isShowingStaleReview = true
                                    }
                                )
                                .frame(width: cardWidth)
                                .frame(maxHeight: .infinity)
                                .transition(.scale(scale: 0.96).combined(with: .opacity))
                            }
                            
                            if isSingleFocus {
                                Spacer(minLength: 0)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 14)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                    }
                }
                
                // Subtle Keyboard Command Legend Footer (Godspeed / Linear style)
                keyboardLegendFooter
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
            }
            
            // Floating Quick-Add HUD Overlay
            if isShowingQuickAdd {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { isShowingQuickAdd = false }
                
                QuickAddPanel(isPresented: $isShowingQuickAdd)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
            
            // Floating Command Palette Overlay
            if isShowingCommandPalette {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { isShowingCommandPalette = false }
                
                CommandPaletteView(
                    isPresented: $isShowingCommandPalette,
                    onSelectTask: { task in
                        withAnimation(SlateTheme.easeSpring) {
                            focusedList = task.list
                            activeList = task.list
                            selectedTaskIDs = [task.id]
                            lastSelectedTaskID = task.id
                            editingTask = task
                        }
                    },
                    onSelectAction: { actionId in
                        handlePaletteAction(actionId)
                    }
                )
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
            
            // Floating Undo / Destination Toast
            VStack {
                Spacer()
                ToastView()
            }
        }
        .animation(SlateTheme.easeSpring, value: isShowingQuickAdd)
        .animation(SlateTheme.easeSpring, value: isShowingCommandPalette)
        .animation(SlateTheme.easeSpring, value: focusedList)
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task)
        }
        .sheet(isPresented: $isShowingArchive) {
            ArchiveView()
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $isShowingFreshStart) {
            FreshStartRitualView()
        }
        .sheet(isPresented: $isShowingStaleReview) {
            StaleReviewSheet()
        }
        .sheet(isPresented: $isShowingImport) {
            ImportTasksSheet()
        }
        .preferredColorScheme(settings.preferredColorScheme)
        .onReceive(hotKey.$shouldOpenQuickAdd) { shouldOpen in
            if shouldOpen {
                withAnimation(SlateTheme.easeSpring) {
                    isShowingQuickAdd = true
                }
                hotKey.shouldOpenQuickAdd = false
            }
        }
        .onReceive(toastManager.$requestedFocusList) { requested in
            if let target = requested {
                withAnimation(SlateTheme.easeSpring) {
                    focusedList = target
                    activeList = target
                }
                toastManager.requestedFocusList = nil
            }
        }
        .onAppear {
            AutoMoveService.shared.performDailySweep()
            installKeyboardNavigationMonitor()
            checkFreshStartRitual()
            ensureMinimumOptimalWindowSize()
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
        .background(
            Group {
                Button("") { UndoToastManager.shared.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                
                Button("") { isShowingQuickAdd.toggle() }
                    .keyboardShortcut("n", modifiers: .command)
                
                Button("") { ExportService.shared.copyTodayStandupSummaryToClipboard() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                
                Button("") {
                    withAnimation(SlateTheme.easeSpring) {
                        isShowingCommandPalette.toggle()
                    }
                }
                .keyboardShortcut("k", modifiers: .command)
                
                Button("") {
                    withAnimation(SlateTheme.easeSpring) { focusedList = nil }
                }
                .keyboardShortcut("0", modifiers: .command)
                
                Button("") {
                    withAnimation(SlateTheme.easeSpring) {
                        focusedList = (focusedList == .today) ? nil : .today
                        activeList = .today
                    }
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("") {
                    withAnimation(SlateTheme.easeSpring) {
                        focusedList = (focusedList == .next) ? nil : .next
                        activeList = .next
                    }
                }
                .keyboardShortcut("2", modifiers: .command)
                
                Button("") {
                    withAnimation(SlateTheme.easeSpring) {
                        focusedList = (focusedList == .someday) ? nil : .someday
                        activeList = .someday
                    }
                }
                .keyboardShortcut("3", modifiers: .command)
            }
            .opacity(0)
        )
    }
    
    // MARK: - Selection & Per-Group Select All Helpers
    
    private func handleTaskSelection(_ task: TodoTask, flags: NSEvent.ModifierFlags) {
        activeList = task.list
        
        if flags.contains(.command) {
            if selectedTaskIDs.contains(task.id) {
                selectedTaskIDs.remove(task.id)
            } else {
                selectedTaskIDs.insert(task.id)
                lastSelectedTaskID = task.id
            }
        } else if flags.contains(.shift),
                  let anchorID = lastSelectedTaskID,
                  let anchorTask = store.task(with: anchorID),
                  anchorTask.list == task.list {
            let groupTasks = store.tasks(for: task.list)
            if let startIdx = groupTasks.firstIndex(where: { $0.id == anchorID }),
               let endIdx = groupTasks.firstIndex(where: { $0.id == task.id }) {
                let range = min(startIdx, endIdx)...max(startIdx, endIdx)
                for idx in range {
                    selectedTaskIDs.insert(groupTasks[idx].id)
                }
            }
        } else {
            selectedTaskIDs = [task.id]
            lastSelectedTaskID = task.id
        }
    }
    
    private func selectAll(in group: TaskListType) {
        activeList = group
        let groupTasks = store.tasks(for: group)
        for task in groupTasks {
            selectedTaskIDs.insert(task.id)
        }
        if let first = groupTasks.first {
            lastSelectedTaskID = first.id
        }
    }
    
    private func deselectAll(in group: TaskListType) {
        let groupTasks = store.tasks(for: group)
        for task in groupTasks {
            selectedTaskIDs.remove(task.id)
        }
        if let lastID = lastSelectedTaskID, groupTasks.contains(where: { $0.id == lastID }) {
            lastSelectedTaskID = selectedTaskIDs.first
        }
    }
    
    private func toggleSelectAllInActiveGroup() {
        let targetGroup = focusedList ?? activeList
        let groupTasks = store.tasks(for: targetGroup)
        guard !groupTasks.isEmpty else { return }
        let allSelected = groupTasks.allSatisfy { selectedTaskIDs.contains($0.id) }
        withAnimation(SlateTheme.snapSpring) {
            if allSelected {
                deselectAll(in: targetGroup)
            } else {
                selectAll(in: targetGroup)
            }
        }
    }
    
    private func toggleMarkAllCompleteInActiveGroup() {
        let targetGroup = focusedList ?? activeList
        let groupTasks = store.tasks(for: targetGroup)
        guard !groupTasks.isEmpty else { return }
        let allDone = groupTasks.allSatisfy { $0.status == .completed }
        let targetStatus: TaskStatus = allDone ? .incomplete : .completed
        store.setStatus(targetStatus, for: groupTasks)
        if targetStatus == .completed {
            UndoToastManager.shared.showInfo("Completed all \(groupTasks.count) in \(targetGroup.title)")
        } else {
            UndoToastManager.shared.showInfo("Reset all \(groupTasks.count) in \(targetGroup.title)")
        }
    }
    
    private var selectedTasks: [TodoTask] {
        selectedTaskIDs.compactMap { store.task(with: $0) }
    }
    
    // MARK: - Header Bar with Focus Mode Switcher
    
    private var headerBar: some View {
        HStack(alignment: .center) {
            // App Branding & Title
            HStack(spacing: 10) {
                if let icon = NSImage(named: "AppIcon") ?? (Bundle.main.path(forResource: "AppIcon", ofType: "icns").flatMap { NSImage(contentsOfFile: $0) }) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(SlateColors.primary)
                            .frame(width: 28, height: 28)
                        Text("S")
                            .font(.geist(.bold, size: 16))
                            .foregroundColor(SlateColors.primaryInverted)
                    }
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("Slate")
                        .font(.geist(.bold, size: 18))
                        .foregroundColor(SlateColors.primary)
                    Text("Clean slate. Quiet focus.")
                        .font(.geist(.regular, size: 11))
                        .foregroundColor(SlateColors.secondary)
                }
            }
            
            if focusFilter.isFocusFilterActive {
                HStack(spacing: 5) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 9))
                    Text("Focus: \(focusFilter.activeFilterListName?.capitalized ?? "Filtered")")
                        .font(.geist(.mono, size: 10.5))
                    Button {
                        withAnimation(SlateTheme.easeSpring) {
                            focusFilter.clearFocusFilter()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.18))
                .foregroundColor(.purple)
                .clipShape(Capsule())
                .transition(.scale.combined(with: .opacity))
            }
            
            Spacer()
            
            // Header Action Buttons
            HStack(spacing: 8) {
                // Command Palette Button
                Button(action: {
                    withAnimation(SlateTheme.easeSpring) {
                        isShowingCommandPalette.toggle()
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(SlateColors.secondary)
                        .frame(width: 32, height: 32)
                        .background(SlateColors.hair)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Command Palette (⌘K)")
                
                // Quick-Add Trigger Button with Monospace Keycap
                Button(action: { isShowingQuickAdd = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Quick-Add")
                            .font(.geist(.semiBold, size: 12.5))
                        KeycapBadge("⌘N", inverted: true)
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .padding(.vertical, 6)
                    .background(SlateColors.primary)
                    .foregroundColor(SlateColors.primaryInverted)
                    .clipShape(RoundedRectangle(cornerRadius: SlateTheme.btnRadius, style: .continuous))
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                
                // Archive Button
                Button(action: { isShowingArchive = true }) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(SlateColors.secondary)
                        .frame(width: 32, height: 32)
                        .background(SlateColors.hair)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Open Archive")
                
                // Settings Button
                Button(action: { isShowingSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(SlateColors.secondary)
                        .frame(width: 32, height: 32)
                        .background(SlateColors.hair)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Slate Settings (⌘,)")
            }
        }
    }
    
    // MARK: - Keyboard Legend Footer
    
    private var keyboardLegendFooter: some View {
        HStack(spacing: 14) {
            legendItem(key: "↑↓←→", label: "Navigate")
            legendItem(key: "⌘A", label: "Select All")
            legendItem(key: "⇧⌘↵", label: "Complete All in \((focusedList ?? activeList).title)")
            legendItem(key: "Space", label: "Cycle Status")
            legendItem(key: "1·2·3", label: "Move")
            legendItem(key: "⌘K", label: "Palette")
            legendItem(key: "^⌥Space", label: "Global Capture")
            Spacer()
            if !selectedTaskIDs.isEmpty {
                Button(action: {
                    withAnimation(SlateTheme.snapSpring) {
                        selectedTaskIDs.removeAll()
                        lastSelectedTaskID = nil
                        expandedTaskID = nil
                    }
                }) {
                    HStack(spacing: 4) {
                        KeycapBadge("Esc")
                        Text("Clear (\(selectedTaskIDs.count))")
                            .font(.geist(.mono, size: 11))
                            .foregroundColor(SlateColors.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(0.85)
    }
    
    private func legendItem(key: String, label: String) -> some View {
        HStack(spacing: 4) {
            KeycapBadge(key)
            Text(label)
                .font(.geist(.regular, size: 11))
                .foregroundColor(SlateColors.secondary)
        }
    }
    
    // MARK: - Local Keyboard Navigation Monitor (Godspeed / Linear style)
    
    private func installKeyboardNavigationMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Ignore when modal overlays are open
            if isShowingQuickAdd || isShowingCommandPalette || isShowingArchive || isShowingSettings || editingTask != nil {
                return event
            }
            
            // Ignore if user is actively typing in a TextField / NSTextView
            if let responder = event.window?.firstResponder, responder is NSTextView {
                // Allow Escape to exit inline expansion or unfocus text field
                if event.keyCode == 53 { // Escape
                    if expandedTaskID != nil {
                        withAnimation(SlateTheme.expandSpring) {
                            expandedTaskID = nil
                        }
                        event.window?.makeFirstResponder(nil)
                        return nil
                    }
                    event.window?.makeFirstResponder(nil)
                    return nil
                }
                return event
            }
            
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            // Command + A (keyCode 0) -> Select All / Deselect All in active group
            if flags == .command && event.keyCode == 0 {
                toggleSelectAllInActiveGroup()
                return nil
            }
            
            // Shift + Command + Return (keyCode 36) -> Mark All Complete / Reset in active group
            if flags == [.command, .shift] && event.keyCode == 36 {
                toggleMarkAllCompleteInActiveGroup()
                return nil
            }
            
            // Command + Backspace (keyCode 51) -> Delete selected task(s)
            if flags == .command && event.keyCode == 51 {
                let batch = selectedTasks
                if !batch.isEmpty {
                    selectedTaskIDs.removeAll()
                    lastSelectedTaskID = nil
                    expandedTaskID = nil
                    store.deleteTasks(batch)
                    return nil
                }
            }
            
            // Command + Shift + C (keyCode 8) -> Copy Today for Standup
            if flags == [.command, .shift] && event.keyCode == 8 {
                ExportService.shared.copyTodayStandupSummaryToClipboard()
                return nil
            }
            
            // Command + T (keyCode 17) -> Move to Today
            if flags == .command && event.keyCode == 17 {
                if moveSelectedTasks(to: .today) { return nil }
            }
            // Command + E (keyCode 14) -> Move to Next
            if flags == .command && event.keyCode == 14 {
                if moveSelectedTasks(to: .next) { return nil }
            }
            // Command + S (keyCode 1) -> Move to Someday
            if flags == .command && event.keyCode == 1 {
                if moveSelectedTasks(to: .someday) { return nil }
            }
            
            // Only handle unmodified keys below
            guard flags.subtracting([.numericPad, .function]).isEmpty else {
                return event
            }
            
            switch event.keyCode {
            case 126, 40: // Up arrow or 'K'
                navigateVertical(direction: -1)
                return nil
            case 125, 38: // Down arrow or 'J'
                navigateVertical(direction: 1)
                return nil
            case 123, 4: // Left arrow or 'H'
                navigateHorizontal(direction: -1)
                return nil
            case 124, 37: // Right arrow or 'L'
                navigateHorizontal(direction: 1)
                return nil
            case 51: // Backspace -> Delete selected task(s)
                let batch = selectedTasks
                if !batch.isEmpty {
                    selectedTaskIDs.removeAll()
                    lastSelectedTaskID = nil
                    expandedTaskID = nil
                    store.deleteTasks(batch)
                    return nil
                }
            case 49: // Space -> Cycle status (single) or batch toggle Done/Reset (multi)
                let batch = selectedTasks
                if batch.count == 1, let single = batch.first {
                    store.toggleTaskStatus(single)
                    return nil
                } else if batch.count > 1 {
                    let allDone = batch.allSatisfy { $0.status == .completed }
                    store.setStatus(allDone ? .incomplete : .completed, for: batch)
                    return nil
                }
            case 36: // Return -> Toggle inline expand on primary selected task
                if let id = lastSelectedTaskID ?? selectedTaskIDs.first {
                    withAnimation(SlateTheme.expandSpring) {
                        expandedTaskID = (expandedTaskID == id) ? nil : id
                    }
                    return nil
                }
            case 53: // Escape -> Clear expansion or selection
                if expandedTaskID != nil {
                    withAnimation(SlateTheme.expandSpring) {
                        expandedTaskID = nil
                    }
                    return nil
                } else if !selectedTaskIDs.isEmpty {
                    selectedTaskIDs.removeAll()
                    lastSelectedTaskID = nil
                    return nil
                } else if focusedList != nil {
                    withAnimation(SlateTheme.easeSpring) {
                        focusedList = nil
                    }
                    return nil
                }
            case 18: // "1" -> Move selected task(s) to Today
                if moveSelectedTasks(to: .today) { return nil }
            case 19: // "2" -> Move selected task(s) to Next
                if moveSelectedTasks(to: .next) { return nil }
            case 20: // "3" -> Move selected task(s) to Someday
                if moveSelectedTasks(to: .someday) { return nil }
            default:
                break
            }
            
            return event
        }
    }
    
    private func navigateVertical(direction: Int) {
        let lists = visibleLists
        guard !lists.isEmpty else { return }
        
        if let currentID = lastSelectedTaskID ?? selectedTaskIDs.first,
           let currentTask = store.task(with: currentID) {
            let listTasks = store.tasks(for: currentTask.list)
            if let idx = listTasks.firstIndex(where: { $0.id == currentID }) {
                let nextIdx = idx + direction
                if listTasks.indices.contains(nextIdx) {
                    let target = listTasks[nextIdx]
                    selectedTaskIDs = [target.id]
                    lastSelectedTaskID = target.id
                    activeList = target.list
                }
                return
            }
        }
        
        // Select first available task in visible lists
        for list in lists {
            let listTasks = store.tasks(for: list)
            if let first = listTasks.first {
                selectedTaskIDs = [first.id]
                lastSelectedTaskID = first.id
                activeList = list
                return
            }
        }
    }
    
    private func navigateHorizontal(direction: Int) {
        let lists = visibleLists
        guard lists.count > 1 else { return }
        
        let currentList: TaskListType
        if let currentID = lastSelectedTaskID ?? selectedTaskIDs.first,
           let task = store.task(with: currentID) {
            currentList = task.list
        } else {
            currentList = activeList
        }
        
        guard let listIdx = lists.firstIndex(of: currentList) else { return }
        let targetIdx = (listIdx + direction + lists.count) % lists.count
        let targetList = lists[targetIdx]
        activeList = targetList
        let targetTasks = store.tasks(for: targetList)
        if let first = targetTasks.first {
            selectedTaskIDs = [first.id]
            lastSelectedTaskID = first.id
        } else {
            selectedTaskIDs.removeAll()
            lastSelectedTaskID = nil
        }
    }
    
    private func moveSelectedTasks(to target: TaskListType) -> Bool {
        let batch = selectedTasks
        guard !batch.isEmpty else { return false }
        let movable = batch.filter { $0.list != target }
        guard !movable.isEmpty else { return true }
        store.moveTasks(movable, to: target)
        activeList = target
        let msg = movable.count == 1 ? "Moved to \(target.title)" : "Moved \(movable.count) to \(target.title)"
        UndoToastManager.shared.showInfo(msg, targetList: target)
        return true
    }
    
    // MARK: - Command Palette Action Handler
    
    private func handlePaletteAction(_ actionId: String) {
        switch actionId {
        case "new_task":
            withAnimation(SlateTheme.easeSpring) { isShowingQuickAdd = true }
        case "start_focus":
            let targetTask = selectedTasks.first ?? store.todayTasks.first(where: { $0.status == .inProgress }) ?? store.todayTasks.first
            if let task = targetTask {
                FocusTimerService.shared.startTimer(for: task)
            } else {
                UndoToastManager.shared.showInfo("No to-dos in Today to focus on.")
            }
        case "stop_focus":
            FocusTimerService.shared.stopTimer(logElapsed: true)
        case "focus_today":
            withAnimation(SlateTheme.easeSpring) { focusedList = .today; activeList = .today }
        case "focus_next":
            withAnimation(SlateTheme.easeSpring) { focusedList = .next; activeList = .next }
        case "focus_someday":
            withAnimation(SlateTheme.easeSpring) { focusedList = .someday; activeList = .someday }
        case "view_all":
            withAnimation(SlateTheme.easeSpring) { focusedList = nil }
        case "fresh_start":
            isShowingFreshStart = true
        case "stale_review":
            isShowingStaleReview = true
        case "open_logbook":
            isShowingArchive = true
        case "import_tasks":
            isShowingImport = true
        case "clear_completed":
            store.clearCompleted(in: focusedList ?? activeList)
        case "copy_standup":
            ExportService.shared.copyTodayStandupSummaryToClipboard()
        case "export_markdown":
            ExportService.shared.exportMarkdownToFile()
        case "export_json":
            ExportService.shared.exportJSONToFile()
        case "toggle_theme":
            if settings.appearanceMode == "dark" {
                settings.appearanceMode = "light"
            } else {
                settings.appearanceMode = "dark"
            }
        case "open_settings":
            isShowingSettings = true
        default:
            break
        }
    }
    
    private func checkFreshStartRitual() {
        guard settings.freshStartRitualEnabled else { return }
        let todayStr = AppSettings.streakDateFormatter.string(from: Date())
        if settings.lastFreshStartDateString != todayStr && !store.carryoverTodayTasks.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isShowingFreshStart = true
            }
        }
    }
    
    private func ensureMinimumOptimalWindowSize() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isMiniaturized }) else { return }
            let current = window.frame
            if current.width < 1260 || current.height < 740 {
                let targetWidth: CGFloat = max(current.width, 1280)
                let targetHeight: CGFloat = max(current.height, 760)
                let newX = max(0, current.origin.x - (targetWidth - current.width) / 2)
                let newY = max(0, current.origin.y - (targetHeight - current.height) / 2)
                window.setFrame(NSRect(x: newX, y: newY, width: targetWidth, height: targetHeight), display: true, animate: true)
            }
        }
    }
}
