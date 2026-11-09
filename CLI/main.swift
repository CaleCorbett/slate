import Foundation

// MARK: - Slate Unified CLI & MCP Server
// Supports both interactive terminal commands and stdio MCP server for Claude/ChatGPT/Grok.

struct SlateCLI {
    static let defaultPort: UInt16 = 23119
    
    static func getBridgeConfig() -> (token: String, port: UInt16) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let slateDir = home.appendingPathComponent(".slate", isDirectory: true)
        let tokenFile = slateDir.appendingPathComponent("bridge.token")
        let metaFile = slateDir.appendingPathComponent("bridge.json")
        
        var token = (try? String(contentsOf: tokenFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var port = defaultPort
        
        if let metaData = try? Data(contentsOf: metaFile),
           let json = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
           let p = json["port"] as? UInt16 {
            port = p
        }
        
        if token.isEmpty {
            token = ProcessInfo.processInfo.environment["SLATE_TOKEN"] ?? ""
        }
        
        return (token, port)
    }
    
    // MARK: - Asynchronous Native Bridge API Request
    static func apiRequest(
        method: String,
        path: String,
        body: [String: Any]? = nil
    ) async -> (status: Int, data: Data?, error: String?) {
        let (token, port) = getBridgeConfig()
        guard !token.isEmpty else {
            return (0, nil, "Error: Slate authentication token not found. Is Slate.app running?")
        }
        
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else {
            return (0, nil, "Error: Invalid URL path \(path)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5.0
        
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (statusCode, data, nil)
        } catch {
            return (0, nil, "Connection failed: \(error.localizedDescription). Make sure Slate.app is running.")
        }
    }
    
    // MARK: - Commands
    
    static func run(args: [String]) async {
        guard let command = args.first else {
            printHelp()
            return
        }
        
        switch command.lowercased() {
        case "list", "ls":
            await handleList(args: Array(args.dropFirst()))
        case "add":
            await handleAdd(args: Array(args.dropFirst()))
        case "done", "check", "complete":
            await handleDone(args: Array(args.dropFirst()))
        case "plan", "today":
            await handlePlan()
        case "token":
            print(getBridgeConfig().token)
        case "mcp":
            await runMCPServer()
        case "config-mcp":
            handleConfigMCP()
        case "help", "-h", "--help":
            printHelp()
        default:
            print("Unknown command: '\(command)'")
            printHelp()
            exit(1)
        }
    }
    
    static func handleList(args: [String]) async {
        var list = "today"
        var asJSON = false
        
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--json" {
                asJSON = true
            } else if !arg.hasPrefix("-") {
                list = arg.lowercased()
            }
            i += 1
        }
        
        let (status, data, error) = await apiRequest(method: "GET", path: "/v1/tasks?list=\(list)")
        guard error == nil, status == 200, let data = data else {
            print(error ?? "Failed to fetch tasks (HTTP \(status))")
            exit(1)
        }
        
        if asJSON {
            if let str = String(data: data, encoding: .utf8) {
                print(str)
            }
            return
        }
        
        guard let tasks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("No tasks found.")
            return
        }
        
        if tasks.isEmpty {
            print("No tasks in \(list.capitalized).")
            return
        }
        
        print("\n=== Slate: \(list.capitalized) (\(tasks.count) tasks) ===")
        for t in tasks {
            let id = (t["id"] as? String ?? "").prefix(8)
            let title = t["title"] as? String ?? "Untitled"
            let status = t["status"] as? String ?? "incomplete"
            let mark = (status == "completed") ? "[✓]" : ((status == "in_progress") ? "[◐]" : "[ ]")
            let evening = (t["isEvening"] as? Bool == true) ? " (🌙)" : ""
            print("\(mark) \(id)  \(title)\(evening)")
            if let notes = t["notes"] as? String, !notes.isEmpty {
                print("       ↳ Notes: \(notes)")
            }
            if let checklist = t["checklist"] as? [[String: Any]], !checklist.isEmpty {
                for item in checklist {
                    let done = item["isCompleted"] as? Bool == true ? "✓" : " "
                    let ititle = item["title"] as? String ?? ""
                    print("       • [\(done)] \(ititle)")
                }
            }
        }
        print()
    }
    
    static func handleAdd(args: [String]) async {
        guard !args.isEmpty else {
            print("Usage: slate add \"<task title>\" [--list today|next|someday] [--notes \"...\"] [--evening]")
            exit(1)
        }
        
        var title = ""
        var list = "today"
        var notes: String? = nil
        var isEvening = false
        var checklist: [String] = []
        
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--list" && i + 1 < args.count {
                list = args[i + 1].lowercased()
                i += 1
            } else if arg == "--notes" && i + 1 < args.count {
                notes = args[i + 1]
                i += 1
            } else if arg == "--evening" {
                isEvening = true
            } else if arg == "--checklist" && i + 1 < args.count {
                checklist = args[i + 1].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                i += 1
            } else if !arg.hasPrefix("-") && title.isEmpty {
                title = arg
            }
            i += 1
        }
        
        guard !title.isEmpty else {
            print("Error: Task title cannot be empty.")
            exit(1)
        }
        
        var payload: [String: Any] = [
            "title": title,
            "list": list,
            "isEvening": isEvening
        ]
        if let notes = notes { payload["notes"] = notes }
        if !checklist.isEmpty { payload["checklist"] = checklist }
        
        let (status, data, error) = await apiRequest(method: "POST", path: "/v1/tasks", body: payload)
        guard error == nil, status == 201, let data = data else {
            print(error ?? "Failed to create task (HTTP \(status))")
            exit(1)
        }
        
        if let created = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = created["id"] as? String {
            print("✓ Added to \(list.capitalized): \"\(title)\" (ID: \(id.prefix(8)))")
        } else {
            print("✓ Added to \(list.capitalized): \"\(title)\"")
        }
    }
    
    static func handleDone(args: [String]) async {
        guard let query = args.first else {
            print("Usage: slate done <task-id-or-title>")
            exit(1)
        }
        
        let (_, data, error) = await apiRequest(method: "GET", path: "/v1/tasks?list=all")
        guard error == nil, let data = data,
              let tasks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print(error ?? "Failed to search tasks.")
            exit(1)
        }
        
        let target = tasks.first { t in
            let id = (t["id"] as? String ?? "").lowercased()
            let title = (t["title"] as? String ?? "").lowercased()
            let q = query.lowercased()
            return id.hasPrefix(q) || title.contains(q)
        }
        
        guard let found = target, let targetId = found["id"] as? String else {
            print("No matching active task found for '\(query)'.")
            exit(1)
        }
        
        let (status, _, toggleErr) = await apiRequest(method: "POST", path: "/v1/tasks/\(targetId)/toggle")
        if status == 200 {
            let title = found["title"] as? String ?? "Task"
            print("✓ Updated: \"\(title)\"")
        } else {
            print(toggleErr ?? "Failed to toggle task status.")
            exit(1)
        }
    }
    
    static func handlePlan() async {
        let (status, data, error) = await apiRequest(method: "GET", path: "/v1/plan")
        guard error == nil, status == 200, let data = data,
              let plan = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print(error ?? "Failed to fetch plan.")
            exit(1)
        }
        
        let remaining = plan["todayRemaining"] as? Int ?? 0
        let total = plan["todayTotal"] as? Int ?? 0
        let streak = plan["activeStreak"] as? Int ?? 0
        let timer = plan["focusTimer"] as? [String: Any]
        let timerRunning = timer?["isRunning"] as? Bool ?? false
        let timerLeft = timer?["remainingTime"] as? String ?? "25:00"
        let tasks = plan["tasks"] as? [[String: Any]] ?? []
        
        print("\n==========================================")
        print("          SLATE DAILY DOCKET              ")
        print("==========================================")
        print("🔥 Streak: \(streak) days  |  📋 Remaining: \(remaining)/\(total)")
        if timerRunning {
            print("⏱️ Focus Timer: RUNNING (\(timerLeft) left)")
        }
        print("------------------------------------------")
        if tasks.isEmpty {
            print("All clear! No tasks remaining on Today.")
        } else {
            for t in tasks {
                let status = t["status"] as? String ?? "incomplete"
                let mark = (status == "completed") ? "[✓]" : ((status == "in_progress") ? "[◐]" : "[ ]")
                let title = t["title"] as? String ?? ""
                let evening = (t["isEvening"] as? Bool == true) ? " (🌙)" : ""
                print("\(mark) \(title)\(evening)")
            }
        }
        print("==========================================\n")
    }
    
    static func handleConfigMCP() {
        let path = CommandLine.arguments[0]
        let binaryPath = (path.hasPrefix("/")) ? path : "/usr/local/bin/slate"
        
        print("\n=== Model Context Protocol (MCP) Configuration ===")
        print("Add this snippet to your Claude Desktop config (~/Library/Application Support/Claude/claude_desktop_config.json):")
        print("""
{
  "mcpServers": {
    "slate": {
      "command": "\(binaryPath)",
      "args": ["mcp"]
    }
  }
}
""")
        print("Also compatible with Cursor, ChatGPT Desktop, and Zed MCP settings.\n")
    }
    
    static func printHelp() {
        print("""
Slate - Native macOS Task Manager Agent CLI & MCP Bridge

USAGE:
  slate <command> [options]

COMMANDS:
  list [today|next|someday|all] [--json]    List tasks in a list
  add "<title>" [options]                  Create a new task
  done <id-or-search>                      Toggle completion status of a task
  plan                                     Display today's focus plan and streak
  mcp                                      Run Model Context Protocol (MCP) stdio server
  config-mcp                               Print MCP config JSON for Claude Desktop / Cursor
  token                                    Print active Slate authentication token
  help                                     Show this help message

OPTIONS (for 'add'):
  --list <name>        Target list: today (default), next, someday
  --notes <text>       Add notes or markdown description
  --evening            Flag task for evening focus
  --checklist "a,b"    Add comma-separated subtask checklist items

EXAMPLES:
  slate list today
  slate add "Prepare Q3 Architecture Deck" --list today --evening
  slate done "Prepare Q3"
  slate plan
""")
    }
    
    // MARK: - Stdio MCP Server (JSON-RPC 2.0)
    
    static func runMCPServer() async {
        let stdin = FileHandle.standardInput
        let stdout = FileHandle.standardOutput
        
        func sendJSON(_ dict: [String: Any]) {
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let str = String(data: data, encoding: .utf8) {
                let msg = "\(str)\n"
                if let d = msg.data(using: .utf8) {
                    stdout.write(d)
                }
            }
        }
        
        // Loop reading line by line
        while true {
            guard let lineData = readStdinLine(stdin),
                  let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty else {
                break
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let method = json["method"] as? String else {
                continue
            }
            
            let id = json["id"]
            
            switch method {
            case "initialize":
                let result: [String: Any] = [
                    "protocolVersion": "2024-11-05",
                    "capabilities": [
                        "tools": [:]
                    ],
                    "serverInfo": [
                        "name": "slate-mcp",
                        "version": "1.0.0"
                    ]
                ]
                sendJSON(["jsonrpc": "2.0", "id": id as Any, "result": result])
                
            case "notifications/initialized":
                break
                
            case "ping":
                sendJSON(["jsonrpc": "2.0", "id": id as Any, "result": [:]])
                
            case "tools/list":
                let tools: [[String: Any]] = [
                    [
                        "name": "slate_list_tasks",
                        "description": "List active tasks from Slate macOS task manager filtered by list (today, next, someday, all) or status (incomplete, completed, all).",
                        "inputSchema": [
                            "type": "object",
                            "properties": [
                                "list": [
                                    "type": "string",
                                    "enum": ["today", "next", "someday", "all"],
                                    "description": "Which list to query. Defaults to 'today'."
                                ],
                                "status": [
                                    "type": "string",
                                    "enum": ["incomplete", "completed", "all"],
                                    "description": "Filter by status. Defaults to 'all'."
                                ]
                            ]
                        ]
                    ],
                    [
                        "name": "slate_add_task",
                        "description": "Create a new to-do task in Slate macOS app. Dispatches live to the user's screen in real time.",
                        "inputSchema": [
                            "type": "object",
                            "required": ["title"],
                            "properties": [
                                "title": [
                                    "type": "string",
                                    "description": "The task title."
                                ],
                                "list": [
                                    "type": "string",
                                    "enum": ["today", "next", "someday"],
                                    "description": "Target list. Defaults to 'today'."
                                ],
                                "notes": [
                                    "type": "string",
                                    "description": "Detailed notes or markdown context for the task."
                                ],
                                "is_evening": [
                                    "type": "boolean",
                                    "description": "Whether this is flagged as an evening task."
                                ],
                                "checklist": [
                                    "type": "array",
                                    "items": ["type": "string"],
                                    "description": "Subtask checklist items."
                                ]
                            ]
                        ]
                    ],
                    [
                        "name": "slate_complete_task",
                        "description": "Mark a task as completed in Slate by ID or fuzzy title search.",
                        "inputSchema": [
                            "type": "object",
                            "required": ["query"],
                            "properties": [
                                "query": [
                                    "type": "string",
                                    "description": "Task UUID or partial title to complete."
                                ]
                            ]
                        ]
                    ],
                    [
                        "name": "slate_get_daily_plan",
                        "description": "Get a summary of the user's today docket, remaining tasks, active streak, and focus timer status in Slate.",
                        "inputSchema": [
                            "type": "object",
                            "properties": [:]
                        ]
                    ]
                ]
                sendJSON(["jsonrpc": "2.0", "id": id as Any, "result": ["tools": tools]])
                
            case "tools/call":
                guard let params = json["params"] as? [String: Any],
                      let toolName = params["name"] as? String else {
                    sendJSON(["jsonrpc": "2.0", "id": id as Any, "error": ["code": -32602, "message": "Invalid params"]])
                    continue
                }
                
                let arguments = (params["arguments"] as? [String: Any]) ?? [:]
                let toolResult = await executeMCPTool(name: toolName, args: arguments)
                sendJSON(["jsonrpc": "2.0", "id": id as Any, "result": toolResult])
                
            default:
                sendJSON(["jsonrpc": "2.0", "id": id as Any, "error": ["code": -32601, "message": "Method not found: \(method)"]])
            }
        }
    }
    
    private static func executeMCPTool(name: String, args: [String: Any]) async -> [String: Any] {
        switch name {
        case "slate_list_tasks":
            let list = (args["list"] as? String) ?? "today"
            let statusFilter = (args["status"] as? String) ?? "all"
            let (status, data, error) = await apiRequest(method: "GET", path: "/v1/tasks?list=\(list)&status=\(statusFilter)")
            if let data = data, let str = String(data: data, encoding: .utf8), status == 200 {
                return ["content": [["type": "text", "text": str]], "isError": false]
            }
            return ["content": [["type": "text", "text": error ?? "Failed to list tasks"]], "isError": true]
            
        case "slate_add_task":
            guard let title = args["title"] as? String, !title.isEmpty else {
                return ["content": [["type": "text", "text": "Error: title is required"]], "isError": true]
            }
            var payload: [String: Any] = [
                "title": title,
                "list": (args["list"] as? String) ?? "today",
                "isEvening": (args["is_evening"] as? Bool) ?? false
            ]
            if let notes = args["notes"] as? String { payload["notes"] = notes }
            if let checklist = args["checklist"] as? [String] { payload["checklist"] = checklist }
            
            let (status, data, error) = await apiRequest(method: "POST", path: "/v1/tasks", body: payload)
            if let data = data, let str = String(data: data, encoding: .utf8), status == 201 {
                return ["content": [["type": "text", "text": "Task created successfully in Slate:\n\(str)"]], "isError": false]
            }
            return ["content": [["type": "text", "text": error ?? "Failed to create task"]], "isError": true]
            
        case "slate_complete_task":
            guard let query = args["query"] as? String, !query.isEmpty else {
                return ["content": [["type": "text", "text": "Error: query is required"]], "isError": true]
            }
            let (_, data, _) = await apiRequest(method: "GET", path: "/v1/tasks?list=all")
            guard let data = data,
                  let tasks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return ["content": [["type": "text", "text": "Failed to read tasks"]], "isError": true]
            }
            let found = tasks.first { t in
                let tid = (t["id"] as? String ?? "").lowercased()
                let ttitle = (t["title"] as? String ?? "").lowercased()
                let q = query.lowercased()
                return tid.hasPrefix(q) || ttitle.contains(q)
            }
            guard let task = found, let taskId = task["id"] as? String else {
                return ["content": [["type": "text", "text": "No matching task found for '\(query)'"]], "isError": true]
            }
            let (status, _, toggleErr) = await apiRequest(method: "POST", path: "/v1/tasks/\(taskId)/toggle")
            if status == 200 {
                let title = task["title"] as? String ?? "Task"
                return ["content": [["type": "text", "text": "Task marked completed in Slate: \"\(title)\" (ID: \(taskId))"]], "isError": false]
            }
            return ["content": [["type": "text", "text": toggleErr ?? "Failed to toggle task"]], "isError": true]
            
        case "slate_get_daily_plan":
            let (status, data, error) = await apiRequest(method: "GET", path: "/v1/plan")
            if let data = data, let str = String(data: data, encoding: .utf8), status == 200 {
                return ["content": [["type": "text", "text": str]], "isError": false]
            }
            return ["content": [["type": "text", "text": error ?? "Failed to get daily plan"]], "isError": true]
            
        default:
            return ["content": [["type": "text", "text": "Unknown tool \(name)"]], "isError": true]
        }
    }
    
    private static func readStdinLine(_ fileHandle: FileHandle) -> Data? {
        var data = Data()
        while true {
            let byte = fileHandle.readData(ofLength: 1)
            if byte.isEmpty {
                return data.isEmpty ? nil : data
            }
            if byte[0] == 0x0A { // \n
                return data
            }
            data.append(byte)
        }
    }
}

// Entrypoint
await SlateCLI.run(args: Array(CommandLine.arguments.dropFirst()))
