import SwiftUI
import SwiftData

public struct ArchiveView: View {
    public enum ArchiveTab: String, CaseIterable {
        case logbook = "Logbook"
        case trash = "Recently Deleted"
    }
    
    @ObservedObject private var store = DataStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ArchiveTab = .logbook
    @State private var searchText: String = ""
    @State private var showEmptyTrashConfirmation = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedTab == .logbook ? "Logbook" : "Recently Deleted")
                        .font(.geist(.bold, size: 18))
                        .foregroundColor(SlateColors.primary)
                    Text(selectedTab == .logbook ? "Your completed to-dos, organized by day" : "Safety net for deleted tasks before permanent removal")
                        .font(.geist(.regular, size: 12))
                        .foregroundColor(SlateColors.secondary)
                }
                Spacer()
                
                if selectedTab == .trash && !store.deletedTasks.isEmpty {
                    Button("Empty Trash") {
                        showEmptyTrashConfirmation = true
                    }
                    .font(.geist(.medium, size: 12))
                    .foregroundColor(.red)
                    .buttonStyle(.bordered)
                    .confirmationDialog("Empty Trash?", isPresented: $showEmptyTrashConfirmation) {
                        Button("Empty Trash (\(store.deletedTasks.count) to-dos)", role: .destructive) {
                            store.emptyTrash()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will permanently remove all \(store.deletedTasks.count) deleted to-dos. This action cannot be undone.")
                    }
                }
                
                Button("Done") {
                    dismiss()
                }
                .font(.geist(.semiBold, size: 13))
                .buttonStyle(.borderedProminent)
                .tint(SlateColors.primary)
            }
            .padding(18)
            
            // Tab Selector
            Picker("View", selection: $selectedTab) {
                Text("Logbook (\(store.archivedTasks.count))").tag(ArchiveTab.logbook)
                Text("Trash (\(store.deletedTasks.count))").tag(ArchiveTab.trash)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
            
            Divider()
                .background(SlateColors.hair)
            
            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(SlateColors.secondary)
                TextField(selectedTab == .logbook ? "Search logbook..." : "Search trash...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.geist(.regular, size: 14))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(SlateColors.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(SlateColors.hair.opacity(0.4))
            .cornerRadius(8)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            
            if selectedTab == .logbook {
                logbookView
            } else {
                trashView
            }
        }
        .frame(width: 520, height: 500)
        .background(SlateColors.bg)
    }
    
    // MARK: - Logbook View
    
    private var logbookView: some View {
        Group {
            if archivedTasks.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "archivebox")
                        .font(.system(size: 32))
                        .foregroundColor(SlateColors.secondary.opacity(0.4))
                    Text("No completed to-dos yet")
                        .font(.geist(.medium, size: 15))
                        .foregroundColor(SlateColors.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(groupedArchivedDays, id: \.day) { group in
                        Section {
                            ForEach(group.tasks) { task in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(SlateColors.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.title)
                                            .font(.geist(.medium, size: 14))
                                            .strikethrough(true, color: SlateColors.secondary)
                                            .foregroundColor(SlateColors.secondary)
                                        if let compDate = task.completionDate {
                                            Text(Self.timeOnlyFormatter.string(from: compDate))
                                                .font(.geist(.regular, size: 11))
                                                .foregroundColor(SlateColors.secondary.opacity(0.8))
                                        }
                                    }
                                    Spacer()
                                    Button("Restore") {
                                        task.isArchived = false
                                        task.status = .incomplete
                                        try? store.context.save()
                                        store.refreshTrigger = UUID()
                                    }
                                    .buttonStyle(.plain)
                                    .font(.geist(.medium, size: 12))
                                    .foregroundColor(SlateColors.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(SlateColors.hair)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .padding(.vertical, 3)
                            }
                            .onDelete { indices in
                                for i in indices {
                                    store.context.delete(group.tasks[i])
                                }
                                try? store.context.save()
                                store.refreshTrigger = UUID()
                            }
                        } header: {
                            HStack {
                                Text(group.title)
                                    .font(.geist(.semiBold, size: 12.5))
                                    .foregroundColor(SlateColors.primary)
                                Spacer()
                                Text("\(group.tasks.count) completed")
                                    .font(.geist(.mono, size: 11))
                                    .foregroundColor(SlateColors.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    // MARK: - Trash View
    
    private var trashView: some View {
        Group {
            if filteredTrashTasks.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "trash")
                        .font(.system(size: 32))
                        .foregroundColor(SlateColors.secondary.opacity(0.4))
                    Text(searchText.isEmpty ? "Trash is empty" : "No deleted to-dos match your search")
                        .font(.geist(.medium, size: 15))
                        .foregroundColor(SlateColors.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(filteredTrashTasks) { task in
                        HStack(spacing: 10) {
                            Image(systemName: "trash.circle")
                                .foregroundColor(.red.opacity(0.7))
                                .font(.system(size: 16))
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.title)
                                    .font(.geist(.medium, size: 14))
                                    .foregroundColor(SlateColors.primary)
                                
                                HStack(spacing: 6) {
                                    Text(task.list.title)
                                        .font(.geist(.mono, size: 10))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(SlateColors.hair)
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                        .foregroundColor(SlateColors.secondary)
                                    
                                    if let delDate = task.deletedDate {
                                        Text("Deleted \(formatDate(delDate))")
                                            .font(.geist(.regular, size: 11))
                                            .foregroundColor(SlateColors.secondary.opacity(0.8))
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Button("Restore") {
                                store.restoreTaskFromTrash(task)
                            }
                            .buttonStyle(.plain)
                            .font(.geist(.medium, size: 12))
                            .foregroundColor(SlateColors.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(SlateColors.hair)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            
                            Button(action: {
                                store.permanentlyDeleteTask(task)
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(SlateColors.secondary.opacity(0.8))
                                    .padding(6)
                                    .background(SlateColors.hair.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Permanently delete")
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indices in
                        for i in indices {
                            store.permanentlyDeleteTask(filteredTrashTasks[i])
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private var filteredTrashTasks: [TodoTask] {
        let tasks = store.deletedTasks
        if searchText.isEmpty {
            return tasks
        }
        return tasks.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    
    private struct DayGroup {
        let day: Date
        let title: String
        let tasks: [TodoTask]
    }
    
    private var groupedArchivedDays: [DayGroup] {
        let tasks = archivedTasks
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: tasks) { task -> Date in
            let date = task.completionDate ?? task.creationDate
            return calendar.startOfDay(for: date)
        }
        
        return grouped.keys.sorted(by: >).map { date in
            let title: String
            if calendar.isDateInToday(date) {
                title = "Today"
            } else if calendar.isDateInYesterday(date) {
                title = "Yesterday"
            } else {
                title = Self.dayHeaderFormatter.string(from: date)
            }
            return DayGroup(day: date, title: title, tasks: grouped[date] ?? [])
        }
    }
    
    private static let dayHeaderFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()
    
    private static let timeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    
    private var archivedTasks: [TodoTask] {
        let list = store.archivedTasks
        if searchText.isEmpty {
            return list
        }
        return list.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    
    private static let archiveDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    private func formatDate(_ date: Date) -> String {
        Self.archiveDateFormatter.string(from: date)
    }
}
