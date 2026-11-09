import Foundation

public enum AIError: LocalizedError, Sendable {
    case missingAPIKey(String)
    case invalidResponse(String)
    case networkError(String)
    case parsingError(String)
    
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "No API key configured for \(provider). Please set it in Slate Settings > AI."
        case .invalidResponse(let msg):
            return "AI service error: \(msg)"
        case .networkError(let msg):
            return "Network connection failed: \(msg)"
        case .parsingError(let msg):
            return "Could not parse AI response: \(msg)"
        }
    }
}

/// AIService provides unified multi-model client capabilities (Anthropic, OpenAI, xAI Grok, Ollama)
/// for in-app features: 1-click task decomposition into checklists and Smart Day Planning.
public final class AIService: @unchecked Sendable {
    public static let shared = AIService()
    
    private init() {}
    
    // MARK: - Core Multi-Provider Request
    
    public func completePrompt(
        systemPrompt: String,
        userPrompt: String,
        overrideProvider: AIProvider? = nil,
        overrideKey: String? = nil
    ) async throws -> String {
        let providerRaw = AppSettings.shared.aiProvider
        let provider = overrideProvider ?? (AIProvider(rawValue: providerRaw) ?? .anthropic)
        
        let apiKey: String
        if let key = overrideKey {
            apiKey = key
        } else if provider == .ollama {
            apiKey = ""
        } else if let savedKey = KeychainService.shared.load(key: provider.keychainKey), !savedKey.isEmpty {
            apiKey = savedKey
        } else {
            throw AIError.missingAPIKey(provider.displayName)
        }
        
        switch provider {
        case .anthropic:
            return try await completeAnthropic(systemPrompt: systemPrompt, userPrompt: userPrompt, apiKey: apiKey)
        case .openai:
            return try await completeOpenAI(systemPrompt: systemPrompt, userPrompt: userPrompt, apiKey: apiKey)
        case .grok:
            return try await completeGrok(systemPrompt: systemPrompt, userPrompt: userPrompt, apiKey: apiKey)
        case .ollama:
            return try await completeOllama(systemPrompt: systemPrompt, userPrompt: userPrompt)
        }
    }
    
    // MARK: - Anthropic Claude Implementation
    
    private func completeAnthropic(systemPrompt: String, userPrompt: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIError.networkError("Invalid URL")
        }
        
        let model = AppSettings.shared.aiModel.isEmpty ? "claude-3-7-sonnet-20250219" : AppSettings.shared.aiModel
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 30.0
        
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.networkError("No response from Anthropic")
        }
        
        guard http.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AIError.invalidResponse(errorText)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw AIError.parsingError("Invalid Anthropic JSON structure")
        }
        
        return text
    }
    
    // MARK: - OpenAI ChatGPT Implementation
    
    private func completeOpenAI(systemPrompt: String, userPrompt: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AIError.networkError("Invalid URL")
        }
        
        let model = AppSettings.shared.aiModel.isEmpty ? "gpt-4o" : AppSettings.shared.aiModel
        return try await completeOpenAICompatible(
            url: url,
            model: model,
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )
    }
    
    // MARK: - xAI Grok Implementation
    
    private func completeGrok(systemPrompt: String, userPrompt: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.x.ai/v1/chat/completions") else {
            throw AIError.networkError("Invalid URL")
        }
        
        let model = AppSettings.shared.aiModel.isEmpty ? "grok-2" : AppSettings.shared.aiModel
        return try await completeOpenAICompatible(
            url: url,
            model: model,
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )
    }
    
    private func completeOpenAICompatible(
        url: URL,
        model: String,
        apiKey: String,
        systemPrompt: String,
        userPrompt: String
    ) async throws -> String {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 30.0
        
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.networkError("No response from AI service")
        }
        
        guard http.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AIError.invalidResponse(errorText)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw AIError.parsingError("Invalid OpenAI-compatible JSON structure")
        }
        
        return text
    }
    
    // MARK: - Ollama Local Implementation
    
    private func completeOllama(systemPrompt: String, userPrompt: String) async throws -> String {
        let base = AppSettings.shared.ollamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "\(base)/api/chat") else {
            throw AIError.networkError("Invalid Ollama URL")
        }
        
        let model = AppSettings.shared.aiModel.isEmpty ? "llama3.2" : AppSettings.shared.aiModel
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 45.0
        
        let payload: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.networkError("No response from Ollama")
        }
        
        guard http.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AIError.invalidResponse(errorText)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw AIError.parsingError("Invalid Ollama JSON structure")
        }
        
        return text
    }
    
    // MARK: - In-App Features
    
    /// Breaks down a task into 3-6 atomic, actionable checklist subtasks.
    public func breakdownTask(title: String, notes: String?) async throws -> [String] {
        let systemPrompt = """
You are Slate AI, a task breakdown specialist. Break down the user's task into 3 to 6 atomic, actionable, sequential checklist items.
Rules:
1. Each item must start with an action verb (e.g., Draft, Review, Email, Research).
2. Keep each item concise (under 12 words).
3. Output MUST be ONLY a valid JSON array of strings, with no surrounding markdown or explanation:
["Step 1", "Step 2", "Step 3"]
"""
        var userText = "Task: \(title)"
        if let notes = notes, !notes.isEmpty {
            userText += "\nContext: \(notes)"
        }
        
        let rawResponse = try await completePrompt(systemPrompt: systemPrompt, userPrompt: userText)
        return Self.parseStringArray(from: rawResponse)
    }
    
    /// Suggests which tasks from Next to pull into Today based on current capacity and calendar.
    public func planDay(
        nextTasks: [(title: String, notes: String?)],
        calendarEvents: [String],
        remainingSlots: Int
    ) async throws -> [String] {
        guard !nextTasks.isEmpty else { return [] }
        
        let systemPrompt = """
You are Slate AI, a daily focus strategist. Analyze the user's backlog and calendar events to select the most impactful tasks for Today.
Rules:
1. Select at most \(max(1, remainingSlots)) tasks.
2. Prioritize high-impact, realistic items that fit around calendar commitments.
3. Output MUST be ONLY a valid JSON array of the exact task titles chosen from the backlog:
["Title 1", "Title 2"]
"""
        var userText = "Backlog (Next tasks):\n"
        for (i, t) in nextTasks.enumerated() {
            userText += "- \(t.title)\(t.notes.map { " (\($0))" } ?? "")\n"
            if i >= 20 { break }
        }
        
        if !calendarEvents.isEmpty {
            userText += "\nToday's Calendar Commitments:\n"
            for ev in calendarEvents {
                userText += "- \(ev)\n"
            }
        }
        
        let rawResponse = try await completePrompt(systemPrompt: systemPrompt, userPrompt: userText)
        return Self.parseStringArray(from: rawResponse)
    }
    
    /// Test API connection and key validity
    public func testConnection(provider: AIProvider, key: String) async throws -> Bool {
        let system = "Respond with 'OK' only."
        let user = "Ping"
        let response = try await completePrompt(
            systemPrompt: system,
            userPrompt: user,
            overrideProvider: provider,
            overrideKey: key
        )
        return !response.isEmpty
    }
    
    // MARK: - Helpers
    
    public static func parseStringArray(from raw: String) -> [String] {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip markdown code fences if present
        if clean.hasPrefix("```") {
            let lines = clean.components(separatedBy: "\n")
            let filtered = lines.filter { !$0.hasPrefix("```") }
            clean = filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Find JSON array bounds '[' and ']'
        if let start = clean.firstIndex(of: "["),
           let end = clean.lastIndex(of: "]") {
            let sub = String(clean[start...end])
            if let data = sub.data(using: .utf8),
               let arr = try? JSONDecoder().decode([String].self, from: data) {
                return arr.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
        }
        
        // Fallback: line-by-line bullet parsing
        return clean.components(separatedBy: "\n")
            .map { line -> String in
                var l = line.trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("- ") || l.hasPrefix("* ") {
                    l = String(l.dropFirst(2))
                } else if let dot = l.firstIndex(of: "."), Int(l[..<dot]) != nil {
                    l = String(l[l.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
                }
                return l.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }
}

