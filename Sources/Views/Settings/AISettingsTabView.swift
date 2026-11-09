import SwiftUI

public struct AISettingsTabView: View {
    @ObservedObject private var settings = AppSettings.shared
    
    @State private var apiKeyInput: String = ""
    @State private var isRevealed: Bool = false
    @State private var hasStoredKey: Bool = false
    @State private var testStatus: String? = nil
    @State private var isTesting: Bool = false
    @State private var copyFeedback: Bool = false
    
    public init() {}
    
    private var currentProvider: AIProvider {
        AIProvider(rawValue: settings.aiProvider) ?? .anthropic
    }
    
    public var body: some View {
        Form {
            // MARK: - External Agents (80%)
            Section("External Agent Connectivity (MCP & CLI)") {
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Agent Bridge Active on 127.0.0.1:23119")
                        .font(.subheadline)
                        .foregroundColor(SlateColors.primary)
                    Spacer()
                    Button(copyFeedback ? "Copied!" : "Copy Claude/Cursor MCP Config") {
                        copyMCPConfigToClipboard()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Text("Allows Claude Desktop, Cursor, and ChatGPT Desktop to inspect and manage your Slate tasks directly via Model Context Protocol.")
                    .font(.caption)
                    .foregroundColor(SlateColors.secondary)
            }
            
            // MARK: - In-App AI Provider (20%)
            Section("In-App AI Intelligence") {
                Picker("Active Provider", selection: Binding(
                    get: { settings.aiProvider },
                    set: { newProvider in
                        settings.aiProvider = newProvider
                        if let p = AIProvider(rawValue: newProvider) {
                            settings.aiModel = p.defaultModels.first ?? ""
                        }
                        refreshKeyStatus()
                    }
                )) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                
                Picker("Model", selection: $settings.aiModel) {
                    ForEach(currentProvider.defaultModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                
                if currentProvider == .ollama {
                    TextField("Ollama Base URL", text: $settings.ollamaEndpoint)
                        .textFieldStyle(.roundedBorder)
                    Text("Default: http://localhost:11434")
                        .font(.caption)
                        .foregroundColor(SlateColors.secondary)
                } else {
                    HStack {
                        if isRevealed {
                            TextField("API Key", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField(hasStoredKey ? "••••••••••••••••••••••••" : "Paste API Key", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Button {
                            isRevealed.toggle()
                        } label: {
                            Image(systemName: isRevealed ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .help(isRevealed ? "Hide key" : "Show key")
                        
                        Button("Save") {
                            saveKey()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    
                    HStack {
                        if hasStoredKey {
                            Label("Saved securely in macOS Keychain", systemImage: "checkmark.shield.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            Spacer()
                            
                            Button("Clear Key") {
                                clearKey()
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.red)
                        } else {
                            Text("API keys are never stored in plaintext and never leave your Mac.")
                                .font(.caption)
                                .foregroundColor(SlateColors.secondary)
                        }
                    }
                }
                
                HStack {
                    Button(isTesting ? "Testing..." : "Test Connection") {
                        testConnection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isTesting || (!hasStoredKey && currentProvider != .ollama))
                    
                    if let status = testStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(status.contains("✓") ? .green : .red)
                    }
                }
                .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshKeyStatus()
        }
    }
    
    private func refreshKeyStatus() {
        if currentProvider == .ollama {
            hasStoredKey = true
        } else {
            let key = KeychainService.shared.load(key: currentProvider.keychainKey)
            hasStoredKey = (key != nil && !key!.isEmpty)
        }
        apiKeyInput = ""
        testStatus = nil
    }
    
    private func saveKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        KeychainService.shared.save(key: currentProvider.keychainKey, value: trimmed)
        apiKeyInput = ""
        refreshKeyStatus()
        testStatus = "✓ Key saved to Keychain"
    }
    
    private func clearKey() {
        KeychainService.shared.delete(key: currentProvider.keychainKey)
        refreshKeyStatus()
        testStatus = "Key removed"
    }
    
    private func testConnection() {
        isTesting = true
        testStatus = "Contacting \(currentProvider.displayName)..."
        
        Task {
            do {
                let savedKey = KeychainService.shared.load(key: currentProvider.keychainKey) ?? ""
                let ok = try await AIService.shared.testConnection(provider: currentProvider, key: savedKey)
                await MainActor.run {
                    isTesting = false
                    testStatus = ok ? "✓ Connection successful!" : "Failed to connect"
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testStatus = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func copyMCPConfigToClipboard() {
        let path = "/Users/cale/.local/bin/slate"
        let snippet = """
{
  "mcpServers": {
    "slate": {
      "command": "\(path)",
      "args": ["mcp"]
    }
  }
}
"""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet, forType: .string)
        copyFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            copyFeedback = false
        }
    }
}

