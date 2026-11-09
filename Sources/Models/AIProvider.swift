import Foundation

public enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case anthropic = "anthropic"
    case openai = "openai"
    case grok = "grok"
    case ollama = "ollama"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)"
        case .openai: return "OpenAI (ChatGPT)"
        case .grok: return "xAI (Grok)"
        case .ollama: return "Local (Ollama)"
        }
    }
    
    public var defaultModels: [String] {
        switch self {
        case .anthropic:
            return ["claude-3-7-sonnet-20250219", "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022"]
        case .openai:
            return ["gpt-4o", "gpt-4o-mini", "o3-mini"]
        case .grok:
            return ["grok-2", "grok-beta"]
        case .ollama:
            return ["llama3.2", "mistral", "qwen2.5", "deepseek-r1"]
        }
    }
    
    public var keychainKey: String {
        switch self {
        case .anthropic: return "anthropic_api_key"
        case .openai: return "openai_api_key"
        case .grok: return "grok_api_key"
        case .ollama: return "ollama_endpoint"
        }
    }
}

