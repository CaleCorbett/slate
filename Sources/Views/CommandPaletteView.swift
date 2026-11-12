import SwiftUI

public enum PaletteItemType: Hashable {
    case action(id: String, title: String, subtitle: String?, icon: String, shortcut: String?)
    case task(id: UUID, title: String, list: TaskListType, status: TaskStatus)
}

public struct CommandPaletteView: View {
    @Binding public var isPresented: Bool
    public var onSelectTask: (TodoTask) -> Void
    public var onSelectAction: (String) -> Void
    
    @ObservedObject private var store = DataStore.shared
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool
    
    public init(
        isPresented: Binding<Bool>,
        onSelectTask: @escaping (TodoTask) -> Void,
        onSelectAction: @escaping (String) -> Void
    ) {
        self._isPresented = isPresented
        self.onSelectTask = onSelectTask
        self.onSelectAction = onSelectAction
    }
    
    private var baseActions: [PaletteItemType] {
        [
            .action(id: "new_task", title: "New To-Do", subtitle: "Summon Quick-Add capture", icon: "plus.circle.fill", shortcut: "⌘N"),
            FocusTimerService.shared.isRunning
                ? .action(id: "stop_focus", title: "Stop Active Focus Timer (\(FocusTimerService.shared.formattedRemainingTime))", subtitle: "End focus session and log elapsed time", icon: "stop.circle.fill", shortcut: nil)
                : .action(id: "start_focus", title: "Start Focus Session (\(AppSettings.shared.focusDurationMinutes)m)", subtitle: "Launch Pomodoro timer on first in-progress or selected task", icon: "timer", shortcut: nil),
            .action(id: "focus_today", title: "Focus Today", subtitle: "Zoom into today's list", icon: "sun.max.fill", shortcut: "⌘1"),
            .action(id: "focus_next", title: "Focus Next", subtitle: "Zoom into upcoming list", icon: "arrow.right.circle.fill", shortcut: "⌘2"),
            .action(id: "focus_someday", title: "Focus Someday", subtitle: "Zoom into aspirational list", icon: "sparkles", shortcut: "⌘3"),
            .action(id: "view_all", title: "Show All Lists", subtitle: "Full 3-column board view", icon: "square.grid.3x1.below.line.grid.1x2", shortcut: "⌘0"),
            .action(id: "fresh_start", title: "Daily Fresh Start Ritual", subtitle: "Triage unfinished carryover to-dos", icon: "arrow.clockwise.circle.fill", shortcut: nil),
            .action(id: "stale_review", title: "Review Stale Someday Tasks", subtitle: "Triage ideas untouched for 30+ days", icon: "hourglass", shortcut: nil),
            .action(id: "copy_standup", title: "Copy Today's Summary for Standup", subtitle: "Copy formatted markdown bullets of today's work to clipboard", icon: "doc.on.doc.fill", shortcut: "⌘⇧C"),
            .action(id: "export_markdown", title: "Export To-Dos as Markdown…", subtitle: "Export clean checklist outline to .md file", icon: "text.alignleft", shortcut: nil),
            .action(id: "export_json", title: "Export Full JSON Backup…", subtitle: "Export all active & archived tasks to JSON file", icon: "doc.badge.arrow.up", shortcut: nil),
            .action(id: "open_logbook", title: "Open Logbook & Trash", subtitle: "View completed and deleted to-dos", icon: "archivebox.fill", shortcut: "⌘L"),
            .action(id: "import_tasks", title: "Import To-Dos…", subtitle: "Import from Apple Reminders or Things 3", icon: "arrow.down.doc.fill", shortcut: nil),
            .action(id: "clear_completed", title: "Clear Completed To-Dos", subtitle: "Archive completed tasks from Today", icon: "checkmark.circle", shortcut: "⇧⌘⌫"),
            .action(
                id: "toggle_sounds",
                title: AppSettings.shared.soundEffectsEnabled ? "Mute Sound Effects" : "Enable Sound Effects",
                subtitle: AppSettings.shared.soundEffectsEnabled ? "Silence all tactile audio feedback" : "Turn on tactile audio feedback",
                icon: AppSettings.shared.soundEffectsEnabled ? "speaker.slash.fill" : "speaker.wave.2.fill",
                shortcut: "⇧⌘M"
            ),
            .action(id: "toggle_theme", title: "Toggle Appearance Theme", subtitle: "Switch between Dark and Light mode", icon: "circle.lefthalf.filled", shortcut: nil),
            .action(id: "open_settings", title: "Open Settings", subtitle: "Preferences & shortcuts", icon: "gearshape.fill", shortcut: "⌘,")
        ]
    }
    
    private var filteredItems: [PaletteItemType] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        let matchingActions: [PaletteItemType]
        if query.isEmpty {
            matchingActions = baseActions
        } else {
            matchingActions = baseActions.filter { item in
                if case .action(_, let title, let subtitle, _, _) = item {
                    return title.lowercased().contains(query) || (subtitle?.lowercased().contains(query) ?? false)
                }
                return false
            }
        }
        
        let allTasks = store.todayTasks + store.nextTasks + store.somedayTasks
        let matchingTasks: [PaletteItemType]
        if query.isEmpty {
            matchingTasks = []
        } else {
            matchingTasks = allTasks
                .filter { $0.title.lowercased().contains(query) || ($0.notes?.lowercased().contains(query) ?? false) }
                .prefix(12)
                .map { .task(id: $0.id, title: $0.title, list: $0.list, status: $0.status) }
        }
        
        return matchingActions + matchingTasks
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Search Input Header
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(SlateColors.secondary)
                
                TextField("Type a command or search to-dos…", text: $searchText)
                    .font(.geist(.regular, size: 15))
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onChange(of: searchText) { _, _ in
                        selectedIndex = 0
                    }
                    .onSubmit {
                        executeSelection()
                    }
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        selectedIndex = 0
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(SlateColors.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Text("ESC to close")
                    .font(.caption2)
                    .foregroundColor(SlateColors.secondary.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(SlateColors.hair)
                    .cornerRadius(4)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            
            Divider()
            
            // Results List
            if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 28))
                        .foregroundColor(SlateColors.secondary.opacity(0.5))
                    Text("No commands or to-dos found")
                        .font(.geist(.regular, size: 13))
                        .foregroundColor(SlateColors.secondary)
                    Spacer()
                }
                .frame(height: 220)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filteredItems.enumerated()), id: \.offset) { index, item in
                                resultRow(item: item, isSelected: index == selectedIndex)
                                    .id(index)
                                    .onTapGesture {
                                        selectedIndex = index
                                        executeSelection()
                                    }
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selectedIndex) { _, newIndex in
                        withAnimation(SlateTheme.easeSpring) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 560)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SlateColors.cardToday)
                .shadow(color: Color.black.opacity(0.28), radius: 30, x: 0, y: 15)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SlateColors.hair.opacity(0.8), lineWidth: 1)
        )
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .background(
            // Invisible keyboard interceptor for Arrow navigation
            Group {
                Button("") {
                    navigate(delta: -1)
                }
                .keyboardShortcut(.upArrow, modifiers: [])
                
                Button("") {
                    navigate(delta: 1)
                }
                .keyboardShortcut(.downArrow, modifiers: [])
                
                Button("") {
                    isPresented = false
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .opacity(0)
        )
    }
    
    // MARK: - Row Rendering
    
    @ViewBuilder
    private func resultRow(item: PaletteItemType, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            switch item {
            case .action(_, let title, let subtitle, let icon, let shortcut):
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? SlateColors.primary : SlateColors.secondary)
                    .frame(width: 22)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.geist(.medium, size: 13))
                        .foregroundColor(SlateColors.primary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(SlateColors.secondary)
                    }
                }
                
                Spacer()
                
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.geist(.mono, size: 11))
                        .foregroundColor(SlateColors.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SlateColors.hair)
                        .cornerRadius(4)
                }
                
            case .task(_, let title, let list, let status):
                Image(systemName: status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundColor(status == .completed ? .green : SlateColors.secondary)
                    .frame(width: 22)
                
                Text(title)
                    .font(.geist(.regular, size: 13))
                    .foregroundColor(SlateColors.primary)
                    .strikethrough(status == .completed)
                    .lineLimit(1)
                
                Spacer()
                
                Text(list.title)
                    .font(.geist(.mono, size: 10))
                    .foregroundColor(list == .today ? .orange : SlateColors.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(list == .today ? Color.orange.opacity(0.15) : SlateColors.hair)
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? SlateColors.hair : Color.clear)
        )
    }
    
    // MARK: - Navigation & Execution
    
    private func navigate(delta: Int) {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }
    
    private func executeSelection() {
        guard selectedIndex >= 0 && selectedIndex < filteredItems.count else { return }
        let selectedItem = filteredItems[selectedIndex]
        isPresented = false
        
        switch selectedItem {
        case .action(let id, _, _, _, _):
            onSelectAction(id)
            
        case .task(let id, _, _, _):
            if let task = store.task(with: id) {
                onSelectTask(task)
            }
        }
    }
}

