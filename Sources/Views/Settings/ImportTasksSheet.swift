import SwiftUI
import UniformTypeIdentifiers

public struct ImportTasksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var importedItems: [ImportedTaskItem] = []
    @State private var isFetchingReminders = false
    @State private var errorMessage: String? = nil
    @State private var plainTextInput: String = ""
    @State private var importedResultCount: Int? = nil
    @State private var skipDuplicates: Bool = true
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import To-Dos")
                        .font(.geist(.bold, size: 16))
                        .foregroundColor(SlateColors.primary)
                    Text("Bring your tasks from Apple Reminders, Things 3, or plain text.")
                        .font(.geist(.regular, size: 12))
                        .foregroundColor(SlateColors.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(SlateColors.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)
            
            Divider()
            
            // Source Selector
            Picker("Source", selection: $selectedTab) {
                Text("Apple Reminders").tag(0)
                Text("Things 3 / JSON").tag(1)
                Text("Plain Text / Markdown").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            
            // Tab Contents
            Group {
                if selectedTab == 0 {
                    appleRemindersTab
                } else if selectedTab == 1 {
                    thingsJSONTab
                } else {
                    plainTextTab
                }
            }
            .frame(maxHeight: .infinity)
            
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            
            Divider()
            
            // Bottom Bar
            HStack {
                Toggle("Skip duplicate to-dos", isOn: $skipDuplicates)
                    .font(.caption)
                    .foregroundColor(SlateColors.secondary)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Import \(importedItems.count) To-Dos") {
                    executeImport()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(importedItems.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 540, height: 480)
        .background(SlateColors.cardToday)
    }
    
    // MARK: - Apple Reminders Tab
    private var appleRemindersTab: some View {
        VStack(spacing: 14) {
            if importedItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checklist")
                        .font(.system(size: 40))
                        .foregroundColor(SlateColors.secondary.opacity(0.6))
                    
                    Text("Import from Apple Reminders")
                        .font(.geist(.medium, size: 14))
                        .foregroundColor(SlateColors.primary)
                    
                    Text("Slate will scan your Apple Reminders lists for incomplete tasks and map their due dates to Today or Next.")
                        .font(.geist(.regular, size: 12))
                        .foregroundColor(SlateColors.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button {
                        fetchReminders()
                    } label: {
                        if isFetchingReminders {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Scan Apple Reminders", systemImage: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isFetchingReminders)
                    
                    Spacer()
                }
            } else {
                itemsPreviewList
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Things 3 / JSON Tab
    private var thingsJSONTab: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Choose JSON File...") {
                    openJSONFilePicker()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                if !importedItems.isEmpty {
                    Text("\(importedItems.count) to-dos detected")
                        .font(.caption)
                        .foregroundColor(SlateColors.secondary)
                }
            }
            
            if importedItems.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 36))
                        .foregroundColor(SlateColors.secondary.opacity(0.5))
                    Text("Import Things 3 or Generic JSON")
                        .font(.geist(.medium, size: 13))
                        .foregroundColor(SlateColors.primary)
                    Text("Select a JSON export from Things 3 or any JSON array of tasks with 'title', 'when', or 'notes' fields.")
                        .font(.caption)
                        .foregroundColor(SlateColors.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    Spacer()
                }
            } else {
                itemsPreviewList
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Plain Text Tab
    private var plainTextTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste bullet points, markdown tasks (- [ ] Task), or one task per line:")
                .font(.caption)
                .foregroundColor(SlateColors.secondary)
            
            TextEditor(text: $plainTextInput)
                .font(.geist(.regular, size: 13))
                .padding(8)
                .background(SlateColors.hair.opacity(0.2))
                .cornerRadius(8)
                .onChange(of: plainTextInput) { _, newValue in
                    importedItems = RemindersImporterService.shared.parsePlainTextTasks(newValue)
                }
            
            if !importedItems.isEmpty {
                HStack {
                    Text("Detected \(importedItems.count) to-dos")
                        .font(.caption)
                        .foregroundColor(.green)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Preview List
    private var itemsPreviewList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Found \(importedItems.count) To-Dos")
                    .font(.geist(.medium, size: 13))
                    .foregroundColor(SlateColors.primary)
                Spacer()
                Button("Clear") {
                    importedItems = []
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(SlateColors.secondary)
            }
            
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(importedItems, id: \.id) { item in
                        HStack(spacing: 10) {
                            Circle()
                                .strokeBorder(SlateColors.secondary.opacity(0.4), lineWidth: 1.5)
                                .frame(width: 14, height: 14)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.geist(.regular, size: 13))
                                    .foregroundColor(SlateColors.primary)
                                    .lineLimit(1)
                                if let notes = item.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.caption2)
                                        .foregroundColor(SlateColors.secondary)
                                        .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                            
                            // Target list pill
                            Text(item.targetList.title)
                                .font(.geist(.mono, size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(item.targetList == .today ? Color.orange.opacity(0.2) : SlateColors.hair)
                                .foregroundColor(item.targetList == .today ? .orange : SlateColors.secondary)
                                .cornerRadius(4)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(SlateColors.hair.opacity(0.25))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    private func fetchReminders() {
        isFetchingReminders = true
        errorMessage = nil
        Task {
            do {
                let items = try await RemindersImporterService.shared.fetchAppleReminders()
                await MainActor.run {
                    self.importedItems = items
                    self.isFetchingReminders = false
                    if items.isEmpty {
                        self.errorMessage = "No incomplete reminders found in Apple Reminders."
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isFetchingReminders = false
                }
            }
        }
    }
    
    private func openJSONFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            do {
                let items = try RemindersImporterService.shared.parseThingsJSON(data)
                self.importedItems = items
                self.errorMessage = nil
            } catch {
                self.errorMessage = "Failed to parse JSON file: \(error.localizedDescription)"
            }
        }
    }
    
    private func executeImport() {
        let count = RemindersImporterService.shared.importItems(importedItems, skipDuplicates: skipDuplicates)
        UndoToastManager.shared.showInfo("Imported \(count) to-dos")
        dismiss()
    }
}
