import SwiftUI

public struct TaskEditorSheet: View {
    @Bindable var task: TodoTask
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var selectedList: TaskListType = .today
    @State private var selectedStatus: TaskStatus = .incomplete
    @State private var hasReminder: Bool = false
    @State private var reminderDate: Date = Date().addingTimeInterval(3600)
    @State private var selectedRecurrence: String = ""
    @State private var checklistItems: [ChecklistItem] = []
    @State private var newChecklistTitle: String = ""
    
    public init(task: TodoTask) {
        self.task = task
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Text("Edit To-Do")
                    .font(.geist(.bold, size: 16))
                    .foregroundColor(SlateColors.primary)
                Spacer()
                Button("Done") {
                    saveChanges()
                    dismiss()
                }
                .font(.geist(.semiBold, size: 14))
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(SlateColors.primary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)
            
            Divider()
                .background(SlateColors.hair)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TITLE")
                            .font(.geist(.medium, size: 11))
                            .foregroundColor(SlateColors.secondary)
                            .tracking(0.5)
                        
                        TextField("Task title", text: $title)
                            .font(.geist(.medium, size: 16))
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(SlateColors.hair.opacity(0.4))
                            .cornerRadius(8)
                    }
                    
                    // List Placement
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LIST")
                            .font(.geist(.medium, size: 11))
                            .foregroundColor(SlateColors.secondary)
                            .tracking(0.5)
                        
                        Picker("List", selection: $selectedList) {
                            ForEach(TaskListType.allCases) { list in
                                Text(list.title).tag(list)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Status
                    VStack(alignment: .leading, spacing: 6) {
                        Text("STATUS")
                            .font(.geist(.medium, size: 11))
                            .foregroundColor(SlateColors.secondary)
                            .tracking(0.5)
                        
                        Picker("Status", selection: $selectedStatus) {
                            Text("To Do").tag(TaskStatus.incomplete)
                            if AppSettings.shared.allowInProgress {
                                Text("In Progress").tag(TaskStatus.inProgress)
                            }
                            Text("Done").tag(TaskStatus.completed)
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Reminder
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $hasReminder) {
                            Text("Reminder")
                                .font(.geist(.medium, size: 14))
                                .foregroundColor(SlateColors.primary)
                        }
                        .toggleStyle(.switch)
                        
                        if hasReminder {
                            DatePicker(
                                "Remind at",
                                selection: $reminderDate,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.compact)
                            .padding(8)
                            .background(SlateColors.hair.opacity(0.3))
                            .cornerRadius(8)
                        }
                    }
                    .padding(12)
                    .background(SlateColors.hair.opacity(0.2))
                    .cornerRadius(10)
                    
                    // Recurrence
                    VStack(alignment: .leading, spacing: 6) {
                        Text("REPEAT")
                            .font(.geist(.medium, size: 11))
                            .foregroundColor(SlateColors.secondary)
                            .tracking(0.5)
                        
                        Picker("Repeat", selection: $selectedRecurrence) {
                            Text("Never").tag("")
                            Text("Daily").tag("daily")
                            Text("Weekdays").tag("weekdays")
                            Text("Weekly").tag("weekly")
                            Text("Monthly").tag("monthly")
                        }
                        .pickerStyle(.menu)
                    }
                    
                    // Sub-tasks / Checklist Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("CHECKLIST")
                                .font(.geist(.medium, size: 11))
                                .foregroundColor(SlateColors.secondary)
                                .tracking(0.5)
                            Spacer()
                            if !checklistItems.isEmpty {
                                let done = checklistItems.filter(\.isCompleted).count
                                Text("\(done)/\(checklistItems.count)")
                                    .font(.geist(.mono, size: 11))
                                    .foregroundColor(SlateColors.secondary)
                            }
                        }
                        
                        ForEach($checklistItems) { $item in
                            HStack(spacing: 8) {
                                Button {
                                    item.isCompleted.toggle()
                                } label: {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 13))
                                        .foregroundColor(item.isCompleted ? .green : SlateColors.secondary)
                                }
                                .buttonStyle(.plain)
                                
                                TextField("Sub-task", text: $item.title)
                                    .font(.geist(.regular, size: 13))
                                    .textFieldStyle(.plain)
                                    .strikethrough(item.isCompleted)
                                
                                Button {
                                    checklistItems.removeAll(where: { $0.id == item.id })
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10))
                                        .foregroundColor(SlateColors.secondary.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 3)
                        }
                        
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 11))
                                .foregroundColor(SlateColors.secondary)
                            TextField("Add sub-task...", text: $newChecklistTitle)
                                .font(.geist(.regular, size: 13))
                                .textFieldStyle(.plain)
                                .onSubmit {
                                    let trimmed = newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty {
                                        checklistItems.append(ChecklistItem(title: trimmed))
                                        newChecklistTitle = ""
                                    }
                                }
                        }
                        .padding(.top, 4)
                    }
                    .padding(10)
                    .background(SlateColors.hair.opacity(0.3))
                    .cornerRadius(8)
                    
                    // Notes Editor
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTES & LINKS")
                            .font(.geist(.medium, size: 11))
                            .foregroundColor(SlateColors.secondary)
                            .tracking(0.5)
                        
                        TextEditor(text: $notes)
                            .font(.geist(.regular, size: 14))
                            .frame(minHeight: 100)
                            .padding(6)
                            .background(SlateColors.hair.opacity(0.3))
                            .cornerRadius(8)
                    }
                    
                    // Delete Button
                    Button(role: .destructive) {
                        DataStore.shared.deleteTask(task)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete To-Do")
                        }
                        .foregroundColor(.red)
                        .font(.geist(.medium, size: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }
                .padding(20)
            }
        }
        .frame(width: 440, height: 520)
        .background(SlateColors.bg)
        .onAppear {
            title = task.title
            notes = task.notes ?? ""
            selectedList = task.list
            selectedStatus = task.status
            selectedRecurrence = task.recurrenceRule ?? ""
            checklistItems = task.checklist
            if let date = task.reminderDate {
                hasReminder = true
                reminderDate = date
            }
        }
    }
    
    private func saveChanges() {
        let oldReminder = task.reminderDate
        task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        task.list = selectedList
        task.status = selectedStatus
        task.recurrenceRule = selectedRecurrence.isEmpty ? nil : selectedRecurrence
        task.checklist = checklistItems
        let newReminder = hasReminder ? reminderDate : nil
        task.reminderDate = newReminder
        
        if oldReminder != newReminder {
            if let newDate = newReminder, newDate > Date() {
                ReminderService.shared.scheduleReminder(for: task)
            } else {
                ReminderService.shared.cancelReminder(for: task)
            }
        }
        
        try? DataStore.shared.context.save()
        DataStore.shared.refreshTrigger = UUID()
    }
}
