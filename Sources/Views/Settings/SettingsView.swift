import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var showImportSheet = false
    
    public init() {}
    
    public var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            
            soundsTab
                .tabItem {
                    Label("Sounds", systemImage: "speaker.wave.2")
                }
            
            quickAddTab
                .tabItem {
                    Label("Quick-Add", systemImage: "plus.circle")
                }
            
            menuBarTab
                .tabItem {
                    Label("Menu Bar", systemImage: "menubar.rectangle")
                }
            
            importTab
                .tabItem {
                    Label("Data", systemImage: "externaldrive")
                }
            
            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 590, height: 490)
        .padding(12)
    }
    
    // MARK: - General Tab
    private var generalTab: some View {
        Form {
            Section("Startup & System") {
                Toggle("Launch Slate at Login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
                Text("Start Slate automatically in your menu bar when you boot or log into your Mac.")
                    .font(.caption)
                    .foregroundColor(SlateColors.secondary)
            }
            
            Section("Status Steps") {
                Toggle("Enable 'In Progress' State", isOn: $settings.allowInProgress)
                Text("When enabled, checking a to-do cycles: To Do → In Progress (half pie) → Done.")
                    .font(.caption)
                    .foregroundColor(SlateColors.secondary)
            }
            
            Section("Task Placement & Auto-Move") {
                Picker("New To-Dos Added At", selection: $settings.addTaskPosition) {
                    Text("Bottom of List").tag("bottom")
                    Text("Top of List").tag("top")
                }
                .pickerStyle(.radioGroup)
                
                Toggle("Move Completed To-Dos to Bottom", isOn: $settings.moveCompletedToBottom)
                
                Toggle("Auto-Move Reminders to Today", isOn: $settings.autoMoveRemindersToToday)
                Text("Any to-do on Next or Someday with a reminder due today slides onto Today automatically.")
                    .font(.caption)
                    .foregroundColor(SlateColors.secondary)
                
                Toggle("Archive Completed Immediately", isOn: $settings.archiveImmediately)
            }
            
            Section("Focus & Daily Limits") {
                HStack {
                    Text("Today Completion Streak")
                    Spacer()
                    if settings.activeStreak > 0 {
                        Text("🔥 \(settings.activeStreak) days")
                            .font(.geist(.mono, size: 12))
                            .foregroundColor(.orange)
                    } else {
                        Text("0 days")
                            .font(.geist(.mono, size: 12))
                            .foregroundColor(SlateColors.secondary)
                    }
                }
                
                Picker("Today Cap Soft Warning", selection: $settings.todayCapLimit) {
                    Text("Off").tag(0)
                    Text("3 to-dos (Ivy Lee / Essential)").tag(3)
                    Text("5 to-dos (Recommended)").tag(5)
                    Text("7 to-dos").tag(7)
                    Text("10 to-dos").tag(10)
                }
                Text("Displays a subtle warning badge when Today's incomplete tasks exceed your daily threshold.")
                    .font(.caption)
                    .foregroundColor(SlateColors.secondary)
                
                Toggle("Daily Fresh Start Ritual", isOn: $settings.freshStartRitualEnabled)
                Text("Prompts you on the first launch of each day to triage yesterday's unfinished to-dos.")
                    .font(.caption)
                    .foregroundColor(SlateColors.secondary)
                
                Picker("Default Focus Session", selection: $settings.focusDurationMinutes) {
                    Text("15 minutes (Sprint)").tag(15)
                    Text("25 minutes (Pomodoro)").tag(25)
                    Text("45 minutes (Deep Work)").tag(45)
                    Text("60 minutes (Power Hour)").tag(60)
                }
                Text("Length of timed focus sessions launched from to-do rows or the ⌘K command palette.")
                    .font(.caption)
                    .foregroundColor(SlateColors.secondary)
                
                Toggle("Show Today's Calendar Peek", isOn: $settings.showCalendarPeekInToday)
                Text("Displays a non-intrusive strip of today's calendar events above your tasks.")
                    .font(.caption)
                    .foregroundColor(SlateColors.secondary)
            }
            
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                
                Picker("App Icon", selection: $settings.selectedAppIcon) {
                    Text("Slate Dark (Default)").tag("Slate Dark")
                    Text("Slate Light").tag("Slate Light")
                    Text("Slate Minimal").tag("Slate Minimal")
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Sounds Tab
    private var soundsTab: some View {
        Form {
            Section("Sound Feedback") {
                Toggle("Play Sound Effects", isOn: $settings.soundEffectsEnabled)
                Text("Tactile sound effects on task completion, status progress, and deletion.")
                    .font(.caption)
                    .foregroundColor(SlateColors.secondary)
            }
            
            Section("Preview Sounds") {
                HStack(spacing: 12) {
                    Button("Completed") {
                        SoundManager.shared.play(.completed)
                    }
                    Button("In Progress") {
                        SoundManager.shared.play(.inProgress)
                    }
                    Button("Deleted") {
                        SoundManager.shared.play(.deleted)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Quick Add Tab
    private var quickAddTab: some View {
        Form {
            Section("Global Capture") {
                HStack {
                    Text("Global Shortcut")
                    Spacer()
                    Text("⌃⌥Space")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SlateColors.hair)
                        .cornerRadius(6)
                }
                Text("Press anywhere across macOS to summon the Quick-Add HUD.")
                    .font(.caption)
                    .foregroundColor(SlateColors.secondary)
            }
            
            Section("Smart Quick-Add") {
                Toggle("Enable Smart Quick-Add", isOn: $settings.smartQuickAddEnabled)
                Text("Automatically detects dates, times, and lists. E.g. 'dentist Friday 3pm' sets a reminder for Friday 3:00 PM and puts it on Next.")
                    .font(.caption)
                    .foregroundColor(SlateColors.secondary)
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Menu Bar Tab
    private var menuBarTab: some View {
        Form {
            Section("Menu Bar Extra") {
                Toggle("Show Slate in Menu Bar", isOn: $settings.showInMenuBar)
                Text("Keep Today's to-dos accessible right from your Mac's menu bar.")
                    .font(.caption)
                    .foregroundColor(SlateColors.secondary)
            }
            
            Section("Badge Count") {
                Picker("Menu Bar Icon Shows", selection: $settings.menuBarBadge) {
                    Text("Remaining to-dos today").tag("remaining")
                    Text("Total to-dos today").tag("total")
                    Text("Icon only (No count)").tag("none")
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Import Tab
    private var importTab: some View {
        Form {
            Section("Migration & External To-Dos") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Import from Apple Reminders or Things 3")
                        .font(.geist(.medium, size: 13))
                        .foregroundColor(SlateColors.primary)
                    Text("Bring existing incomplete tasks, reminders, and checklists into Slate's Today, Next, or Someday lists.")
                        .font(.caption)
                        .foregroundColor(SlateColors.secondary)
                }
                .padding(.vertical, 4)
                
                Button {
                    showImportSheet = true
                } label: {
                    Label("Open Import Assistant…", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.borderedProminent)
            }
            
            Section("Backup & Export") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Export All To-Dos")
                        .font(.geist(.medium, size: 13))
                        .foregroundColor(SlateColors.primary)
                    Text("Save a complete copy of your to-dos, notes, checklists, and focus history for safekeeping or notes apps.")
                        .font(.caption)
                        .foregroundColor(SlateColors.secondary)
                }
                .padding(.vertical, 4)
                
                HStack(spacing: 12) {
                    Button {
                        ExportService.shared.exportMarkdownToFile()
                    } label: {
                        Label("Export Markdown…", systemImage: "text.alignleft")
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        ExportService.shared.exportJSONToFile()
                    } label: {
                        Label("Export JSON Backup…", systemImage: "doc.badge.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showImportSheet) {
            ImportTasksSheet()
        }
    }
    
    // MARK: - About Tab
    private var aboutTab: some View {
        VStack(spacing: 12) {
            Spacer()
            
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage(named: NSImage.applicationIconName) ?? (Bundle.main.path(forResource: "AppIcon", ofType: "icns").flatMap { NSImage(contentsOfFile: $0) }) ?? NSImage())
                .resizable()
                .frame(width: 64, height: 64)
            
            Text("Slate")
                .font(.geist(.bold, size: 22))
                .foregroundColor(SlateColors.primary)
            
            Text("Version 1.0.0")
                .font(.geist(.regular, size: 12))
                .foregroundColor(SlateColors.secondary)
            
            Text("Clean slate. Quiet focus.")
                .font(.geist(.medium, size: 14))
                .foregroundColor(SlateColors.primary)
            
            Text("Three lists. Zero clutter. Stop drowning in endless lists and know what to do today.")
                .font(.geist(.regular, size: 12))
                .foregroundColor(SlateColors.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
            
            Text("100% Native macOS App")
                .font(.caption2)
                .foregroundColor(SlateColors.secondary.opacity(0.7))
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
