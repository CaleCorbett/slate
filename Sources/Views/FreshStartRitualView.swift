import SwiftUI

public struct FreshStartRitualView: View {
    @ObservedObject private var store = DataStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isAIPlanning = false
    @State private var aiStatusMessage: String? = nil
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                HStack(spacing: 10) {
                    Image(systemName: "sun.and.horizon.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Fresh Start Ritual")
                            .font(.geist(.bold, size: 16))
                            .foregroundColor(SlateColors.primary)
                        
                        Text("Unfinished to-dos from previous days. Triage or keep intentionally.")
                            .font(.geist(.regular, size: 12))
                            .foregroundColor(SlateColors.secondary)
                    }
                }
                
                Spacer()
                
                Button("Begin Today") {
                    dismissRitual()
                }
                .font(.geist(.semiBold, size: 13))
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(SlateColors.primary)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 14)
            
            Divider()
                .background(SlateColors.hair)
            
            let carryovers = store.carryoverTodayTasks
            
            if carryovers.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 34))
                        .foregroundColor(.green)
                    Text("Today is clear and focused.")
                        .font(.geist(.semiBold, size: 15))
                        .foregroundColor(SlateColors.primary)
                    Text("No unfinished tasks carried over. You have a clean slate.")
                        .font(.geist(.regular, size: 13))
                        .foregroundColor(SlateColors.secondary)
                    
                    Button("Start Day") {
                        dismissRitual()
                    }
                    .padding(.top, 8)
                    .buttonStyle(.borderedProminent)
                    .tint(SlateColors.primary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            } else {
                // Batch Actions Toolbar
                HStack(spacing: 10) {
                    Text("\(carryovers.count) to-do\(carryovers.count == 1 ? "" : "s") remaining")
                        .font(.geist(.mono, size: 11.5))
                        .foregroundColor(SlateColors.secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(SlateTheme.easeSpring) {
                            store.keepTasksInToday(carryovers)
                        }
                    }) {
                        Label("Keep All in Today", systemImage: "sun.max")
                            .font(.geist(.medium, size: 11.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SlateColors.hair)
                    .cornerRadius(6)
                    
                    Button(action: {
                        planDayWithAI(carryovers: carryovers)
                    }) {
                        HStack(spacing: 4) {
                            if isAIPlanning {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                            Text(isAIPlanning ? "Strategizing..." : "AI Suggest Focus")
                                .font(.geist(.medium, size: 11.5))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SlateColors.hair)
                    .cornerRadius(6)
                    .disabled(isAIPlanning)
                    
                    Button(action: {
                        withAnimation(SlateTheme.easeSpring) {
                            store.moveTasks(carryovers, to: .next)
                        }
                    }) {
                        Label("Move All to Next", systemImage: "calendar.badge.clock")
                            .font(.geist(.medium, size: 11.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SlateColors.hair)
                    .cornerRadius(6)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(SlateColors.hair.opacity(0.2))
                
                Divider()
                    .background(SlateColors.hair)
                
                // Task List
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(carryovers) { task in
                            carryoverRow(for: task)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 580, height: 460)
        .background(SlateColors.bg)
    }
    
    private func carryoverRow(for task: TodoTask) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.geist(.medium, size: 14))
                    .foregroundColor(SlateColors.primary)
                    .lineLimit(1)
                
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.geist(.regular, size: 11.5))
                        .foregroundColor(SlateColors.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 6) {
                Button(action: {
                    withAnimation(SlateTheme.easeSpring) {
                        store.keepTasksInToday([task])
                    }
                }) {
                    Text("Keep")
                        .font(.geist(.medium, size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(SlateColors.hair)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Keep in Today for today's session")
                
                Button(action: {
                    withAnimation(SlateTheme.easeSpring) {
                        store.moveTask(task, to: .next)
                    }
                }) {
                    Text("Next")
                        .font(.geist(.medium, size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(SlateColors.hair)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Move to Next")
                
                Button(action: {
                    withAnimation(SlateTheme.easeSpring) {
                        store.moveTask(task, to: .someday)
                    }
                }) {
                    Text("Someday")
                        .font(.geist(.medium, size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(SlateColors.hair)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Move to Someday")
                
                Button(action: {
                    withAnimation(SlateTheme.easeSpring) {
                        store.setStatus(.completed, for: [task])
                    }
                }) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                        .frame(width: 22, height: 22)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Mark as Completed")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(SlateColors.cardToday)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(SlateColors.hair, lineWidth: 1)
        )
    }
    
    private func planDayWithAI(carryovers: [TodoTask]) {
        guard !isAIPlanning else { return }
        isAIPlanning = true
        aiStatusMessage = nil
        
        let candidates = carryovers.map { (title: $0.title, notes: $0.notes) }
        let events = CalendarPeekService.shared.todayEvents.map { "\($0.title) (\($0.formattedTime))" }
        let cap = AppSettings.shared.todayCapLimit
        
        Task {
            do {
                let chosenTitles = try await AIService.shared.planDay(
                    nextTasks: candidates,
                    calendarEvents: events,
                    remainingSlots: cap
                )
                await MainActor.run {
                    var kept: [TodoTask] = []
                    var movedToNext: [TodoTask] = []
                    
                    for task in carryovers {
                        if chosenTitles.contains(where: { $0.lowercased() == task.title.lowercased() }) {
                            kept.append(task)
                        } else {
                            movedToNext.append(task)
                        }
                    }
                    
                    withAnimation(SlateTheme.easeSpring) {
                        if !kept.isEmpty {
                            store.keepTasksInToday(kept)
                        }
                        if !movedToNext.isEmpty {
                            store.moveTasks(movedToNext, to: .next)
                        }
                    }
                    SoundManager.shared.play(.button)
                    isAIPlanning = false
                }
            } catch {
                await MainActor.run {
                    isAIPlanning = false
                    aiStatusMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func dismissRitual() {
        AppSettings.shared.lastFreshStartDateString = AppSettings.streakDateFormatter.string(from: Date())
        dismiss()
    }
}
