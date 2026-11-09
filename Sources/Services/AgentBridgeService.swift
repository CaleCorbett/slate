import Foundation
import Network
import Combine

/// AgentBridgeService is a zero-idle-CPU loopback HTTP service providing external AI agents
/// (Claude, ChatGPT, Grok, Cursor, CLI scripts) secure local access to inspect and mutate Slate tasks.
public final class AgentBridgeService: @unchecked Sendable {
    public static let shared = AgentBridgeService()
    
    public static let defaultPort: UInt16 = 23119
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.cale.Slate.AgentBridge", qos: .userInitiated)
    
    public private(set) var isRunning: Bool = false
    public private(set) var currentPort: UInt16 = defaultPort
    public private(set) var authToken: String = ""
    
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private init() {
        self.authToken = Self.loadOrCreateAuthToken()
    }
    
    // MARK: - Lifecycle
    
    public func start(port: UInt16 = defaultPort) {
        guard !isRunning else { return }
        
        // Environment override if present
        let targetPort: UInt16
        if let envPortStr = ProcessInfo.processInfo.environment["SLATE_BRIDGE_PORT"],
           let envPort = UInt16(envPortStr) {
            targetPort = envPort
        } else {
            targetPort = port
        }
        
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredInterfaceType = .loopback
            
            let nwListener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: targetPort)!)
            
            nwListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.isRunning = true
                    self.currentPort = targetPort
                    self.saveBridgeMetadata(port: targetPort)
                case .failed(let error):
                    self.isRunning = false
                    print("[AgentBridgeService] Listener failed: \(error)")
                case .cancelled:
                    self.isRunning = false
                default:
                    break
                }
            }
            
            nwListener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }
            
            nwListener.start(queue: queue)
            self.listener = nwListener
        } catch {
            print("[AgentBridgeService] Could not start listener on port \(targetPort): \(error)")
        }
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }
    
    // MARK: - Token & Metadata Management
    
    private static func slateConfigDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let slateDir = home.appendingPathComponent(".slate", isDirectory: true)
        if !FileManager.default.fileExists(atPath: slateDir.path) {
            try? FileManager.default.createDirectory(at: slateDir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }
        return slateDir
    }
    
    private static func loadOrCreateAuthToken() -> String {
        let dir = slateConfigDirectory()
        let tokenFile = dir.appendingPathComponent("bridge.token")
        
        if let existing = try? String(contentsOf: tokenFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }
        
        // Generate secure 32-byte hex token
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let generated = bytes.map { String(format: "%02x", $0) }.joined()
        
        try? generated.write(to: tokenFile, atomically: true, encoding: .utf8)
        _ = chmod(tokenFile.path, 0o600)
        return generated
    }
    
    private func saveBridgeMetadata(port: UInt16) {
        let dir = Self.slateConfigDirectory()
        let metaFile = dir.appendingPathComponent("bridge.json")
        let dict: [String: Any] = [
            "port": port,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "version": "1.0.0",
            "active": true
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) {
            try? data.write(to: metaFile, options: .atomic)
            _ = chmod(metaFile.path, 0o600)
        }
    }
    
    // MARK: - Connection Handling
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(from: connection, accumulated: Data())
    }
    
    private func readRequest(from connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            
            var buffer = accumulated
            if let data = content {
                buffer.append(data)
            }
            
            if error != nil {
                connection.cancel()
                return
            }
            
            // Check if full HTTP headers are received (\r\n\r\n)
            if let headerEndRange = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: 0..<headerEndRange.lowerBound)
                guard let headerString = String(data: headerData, encoding: .utf8) else {
                    self.sendResponse(connection, status: 400, body: ["error": "Malformed HTTP headers"])
                    return
                }
                
                let lines = headerString.components(separatedBy: "\r\n")
                guard let requestLine = lines.first else {
                    self.sendResponse(connection, status: 400, body: ["error": "Empty request line"])
                    return
                }
                
                let parts = requestLine.components(separatedBy: " ")
                guard parts.count >= 2 else {
                    self.sendResponse(connection, status: 400, body: ["error": "Invalid request line format"])
                    return
                }
                
                let method = parts[0].uppercased()
                let fullPath = parts[1]
                
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    let headerParts = line.split(separator: ":", maxSplits: 1).map(String.init)
                    if headerParts.count == 2 {
                        headers[headerParts[0].trimmingCharacters(in: .whitespaces).lowercased()] =
                            headerParts[1].trimmingCharacters(in: .whitespaces)
                    }
                }
                
                // Parse Content-Length to determine if body is complete
                let contentLength = Int(headers["content-length"] ?? "0") ?? 0
                let bodyStart = headerEndRange.upperBound
                let currentBodyLength = buffer.count - bodyStart
                
                if currentBodyLength < contentLength {
                    // Need more body bytes
                    self.readRequest(from: connection, accumulated: buffer)
                    return
                }
                
                let bodyData = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))
                
                // Process HTTP request
                Task {
                    await self.processRequest(
                        connection: connection,
                        method: method,
                        fullPath: fullPath,
                        headers: headers,
                        bodyData: bodyData
                    )
                }
            } else if isComplete {
                connection.cancel()
            } else {
                // Continue reading header
                self.readRequest(from: connection, accumulated: buffer)
            }
        }
    }
    
    // MARK: - Request Routing & Security
    
    private func processRequest(
        connection: NWConnection,
        method: String,
        fullPath: String,
        headers: [String: String],
        bodyData: Data
    ) async {
        // Red Team Gate 1: Check Origin / Referer against Web CSRF / DNS Rebinding
        if let origin = headers["origin"], !origin.isEmpty, origin != "null" {
            // Reject any web origin from browsers (e.g. http://localhost:8080, http://evil.com)
            self.sendResponse(connection, status: 403, body: ["error": "Forbidden: Cross-Origin Web Browser requests are blocked."])
            return
        }
        
        // Split path and query parameters
        let components = URLComponents(string: fullPath)
        let path = components?.path ?? fullPath
        let queryItems = components?.queryItems ?? []
        
        // Handle CORS Preflight / OPTIONS
        if method == "OPTIONS" {
            sendRawResponse(connection, status: 204, statusText: "No Content", headers: [
                "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
                "Access-Control-Allow-Headers": "Authorization, Content-Type, X-Slate-Token"
            ], bodyData: Data())
            return
        }
        
        // Extract token from Header or Query Param
        var clientToken = ""
        if let authHeader = headers["authorization"] {
            if authHeader.lowercased().hasPrefix("bearer ") {
                clientToken = String(authHeader.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
        } else if let customToken = headers["x-slate-token"] {
            clientToken = customToken
        } else if let queryToken = queryItems.first(where: { $0.name == "token" })?.value {
            clientToken = queryToken
        }
        
        // Red Team Gate 2: Mandatory Bearer Token Verification
        guard !clientToken.isEmpty, clientToken == self.authToken else {
            self.sendResponse(connection, status: 401, body: [
                "error": "Unauthorized: Missing or invalid authentication token. Pass 'Authorization: Bearer <token>' matching ~/.slate/bridge.token"
            ])
            return
        }
        
        // Route endpoints
        switch (method, path) {
        case ("GET", "/v1/ping"):
            self.sendResponse(connection, status: 200, body: [
                "status": "ok",
                "app": "Slate",
                "version": "1.0.0",
                "port": self.currentPort
            ])
            
        case ("GET", "/v1/plan"):
            await handleGetPlan(connection: connection)
            
        case ("GET", "/v1/tasks"):
            await handleGetTasks(connection: connection, queryItems: queryItems)
            
        case ("POST", "/v1/tasks"):
            await handleCreateTask(connection: connection, bodyData: bodyData)
            
        default:
            // Match parameter routes like /v1/tasks/:id or /v1/tasks/:id/toggle
            let segments = path.split(separator: "/").map(String.init)
            if segments.count == 3 && segments[0] == "v1" && segments[1] == "tasks" {
                let taskIdStr = segments[2]
                guard let taskId = UUID(uuidString: taskIdStr) else {
                    self.sendResponse(connection, status: 400, body: ["error": "Invalid task UUID"])
                    return
                }
                
                if method == "PATCH" {
                    await handlePatchTask(connection: connection, taskId: taskId, bodyData: bodyData)
                } else if method == "DELETE" {
                    await handleDeleteTask(connection: connection, taskId: taskId)
                } else {
                    self.sendResponse(connection, status: 405, body: ["error": "Method Not Allowed"])
                }
            } else if segments.count == 4 && segments[0] == "v1" && segments[1] == "tasks" && segments[3] == "toggle" {
                let taskIdStr = segments[2]
                guard let taskId = UUID(uuidString: taskIdStr) else {
                    self.sendResponse(connection, status: 400, body: ["error": "Invalid task UUID"])
                    return
                }
                
                if method == "POST" {
                    await handleToggleTask(connection: connection, taskId: taskId)
                } else {
                    self.sendResponse(connection, status: 405, body: ["error": "Method Not Allowed"])
                }
            } else {
                self.sendResponse(connection, status: 404, body: ["error": "Not Found: Unknown endpoint \(path)"])
            }
        }
    }
    
    // MARK: - Handlers (Executed on MainActor)
    
    private func handleGetPlan(connection: NWConnection) async {
        let (todayRemaining, todayTotal, streak, timerRunning, timerFormatted, tasksDTO) = await MainActor.run {
            let store = DataStore.shared
            let remaining = store.todayRemainingCount
            let total = store.todayTotalCount
            let streak = AppSettings.shared.activeStreak
            let timer = FocusTimerService.shared
            let dtos = store.todayTasks.map { TaskDTO(from: $0) }
            return (remaining, total, streak, timer.isRunning, timer.formattedRemainingTime, dtos)
        }
        
        let planDict: [String: Any] = [
            "todayRemaining": todayRemaining,
            "todayTotal": todayTotal,
            "activeStreak": streak,
            "focusTimer": [
                "isRunning": timerRunning,
                "remainingTime": timerFormatted
            ],
            "tasks": tasksDTO.map { $0.toDictionary() }
        ]
        self.sendResponse(connection, status: 200, body: planDict)
    }
    
    private func handleGetTasks(connection: NWConnection, queryItems: [URLQueryItem]) async {
        let listFilter = queryItems.first(where: { $0.name == "list" })?.value?.lowercased() ?? "today"
        let statusFilter = queryItems.first(where: { $0.name == "status" })?.value?.lowercased() ?? "all"
        
        let tasksDTO: [TaskDTO] = await MainActor.run {
            let store = DataStore.shared
            var baseTasks: [TodoTask] = []
            
            switch listFilter {
            case "today":
                baseTasks = store.todayTasks
            case "next":
                baseTasks = store.nextTasks
            case "someday":
                baseTasks = store.somedayTasks
            case "archived":
                baseTasks = store.archivedTasks
            case "all":
                baseTasks = store.todayTasks + store.nextTasks + store.somedayTasks
            default:
                baseTasks = store.todayTasks
            }
            
            // Apply status filter
            if statusFilter == "incomplete" {
                baseTasks = baseTasks.filter { $0.status == .incomplete }
            } else if statusFilter == "completed" {
                baseTasks = baseTasks.filter { $0.status == .completed }
            } else if statusFilter == "in_progress" {
                baseTasks = baseTasks.filter { $0.status == .inProgress }
            }
            
            return baseTasks.map { TaskDTO(from: $0) }
        }
        
        let responseArray = tasksDTO.map { $0.toDictionary() }
        self.sendResponse(connection, status: 200, arrayBody: responseArray)
    }
    
    private func handleCreateTask(connection: NWConnection, bodyData: Data) async {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let title = json["title"] as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.sendResponse(connection, status: 400, body: ["error": "Missing or empty 'title' in JSON body"])
            return
        }
        
        let listStr = (json["list"] as? String)?.lowercased() ?? "today"
        let targetList = TaskListType(rawValue: listStr) ?? .today
        let notes = json["notes"] as? String
        let isEvening = (json["isEvening"] as? Bool) ?? false
        let recurrence = json["recurrenceRule"] as? String
        let reminderStr = json["reminderDate"] as? String
        let finalReminderDate: Date? = reminderStr.flatMap { isoFormatter.date(from: $0) }
        
        let finalChecklistJSON: String?
        if let rawChecklist = json["checklist"] as? [String], !rawChecklist.isEmpty {
            let items = rawChecklist.map { ChecklistItem(title: $0) }
            if let data = try? JSONEncoder().encode(items) {
                finalChecklistJSON = String(data: data, encoding: .utf8)
            } else {
                finalChecklistJSON = nil
            }
        } else {
            finalChecklistJSON = nil
        }
        
        let createdTaskDTO = await MainActor.run { () -> TaskDTO? in
            let store = DataStore.shared
            guard let task = store.addTask(
                title: title,
                to: targetList,
                notes: notes,
                reminderDate: finalReminderDate,
                isEvening: isEvening,
                recurrenceRule: recurrence,
                checklistJSON: finalChecklistJSON
            ) else {
                return nil
            }
            return TaskDTO(from: task)
        }
        
        if let dto = createdTaskDTO {
            self.sendResponse(connection, status: 201, body: dto.toDictionary())
        } else {
            self.sendResponse(connection, status: 500, body: ["error": "Failed to create task in DataStore"])
        }
    }
    
    private func handleToggleTask(connection: NWConnection, taskId: UUID) async {
        let updatedDTO = await MainActor.run { () -> TaskDTO? in
            let store = DataStore.shared
            guard let task = store.task(with: taskId) else { return nil }
            store.toggleTaskStatus(task)
            return TaskDTO(from: task)
        }
        
        if let dto = updatedDTO {
            self.sendResponse(connection, status: 200, body: dto.toDictionary())
        } else {
            self.sendResponse(connection, status: 404, body: ["error": "Task not found with ID \(taskId.uuidString)"])
        }
    }
    
    private func handlePatchTask(connection: NWConnection, taskId: UUID, bodyData: Data) async {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            self.sendResponse(connection, status: 400, body: ["error": "Malformed JSON payload"])
            return
        }
        
        let updatedDTO = await MainActor.run { () -> TaskDTO? in
            let store = DataStore.shared
            guard let task = store.task(with: taskId) else { return nil }
            
            if let newTitle = json["title"] as? String, !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                task.title = newTitle.trimmingCharacters(in: .whitespaces)
            }
            if let newNotes = json["notes"] as? String {
                task.notes = newNotes.isEmpty ? nil : newNotes
            }
            if let newEvening = json["isEvening"] as? Bool {
                task.isEvening = newEvening
            }
            if let newListStr = json["list"] as? String, let targetList = TaskListType(rawValue: newListStr.lowercased()) {
                if task.list != targetList {
                    store.moveTask(task, to: targetList)
                }
            }
            if let rawChecklist = json["checklist"] as? [String] {
                let items = rawChecklist.map { ChecklistItem(title: $0) }
                task.checklist = items
            }
            
            task.lastTouchedDate = Date()
            try? store.context.save()
            store.reloadAll()
            return TaskDTO(from: task)
        }
        
        if let dto = updatedDTO {
            self.sendResponse(connection, status: 200, body: dto.toDictionary())
        } else {
            self.sendResponse(connection, status: 404, body: ["error": "Task not found with ID \(taskId.uuidString)"])
        }
    }
    
    private func handleDeleteTask(connection: NWConnection, taskId: UUID) async {
        let deleted = await MainActor.run { () -> Bool in
            let store = DataStore.shared
            guard let task = store.task(with: taskId) else { return false }
            store.deleteTask(task)
            return true
        }
        
        if deleted {
            self.sendResponse(connection, status: 200, body: [
                "deleted": true,
                "id": taskId.uuidString
            ])
        } else {
            self.sendResponse(connection, status: 404, body: ["error": "Task not found with ID \(taskId.uuidString)"])
        }
    }
    
    // MARK: - HTTP Response Writing
    
    private func sendResponse(_ connection: NWConnection, status: Int, body: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        sendRawResponse(connection, status: status, statusText: httpStatusText(status), headers: [
            "Content-Type": "application/json; charset=utf-8"
        ], bodyData: data)
    }
    
    private func sendResponse(_ connection: NWConnection, status: Int, arrayBody: [[String: Any]]) {
        let data = (try? JSONSerialization.data(withJSONObject: arrayBody, options: [.prettyPrinted])) ?? Data()
        sendRawResponse(connection, status: status, statusText: httpStatusText(status), headers: [
            "Content-Type": "application/json; charset=utf-8"
        ], bodyData: data)
    }
    
    private func sendRawResponse(
        _ connection: NWConnection,
        status: Int,
        statusText: String,
        headers: [String: String],
        bodyData: Data
    ) {
        var responseString = "HTTP/1.1 \(status) \(statusText)\r\n"
        responseString += "Content-Length: \(bodyData.count)\r\n"
        responseString += "Connection: close\r\n"
        for (k, v) in headers {
            responseString += "\(k): \(v)\r\n"
        }
        responseString += "\r\n"
        
        var packet = Data(responseString.utf8)
        packet.append(bodyData)
        
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func httpStatusText(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        default: return "Internal Server Error"
        }
    }
}

// MARK: - Data Transfer Objects

public struct TaskDTO: Sendable {
    public let id: String
    public let title: String
    public let list: String
    public let status: String
    public let notes: String?
    public let isEvening: Bool
    public let orderIndex: Int
    public let recurrenceRule: String?
    public let checklist: [ChecklistItemDTO]
    public let reminderDate: String?
    public let creationDate: String
    public let completionDate: String?
    
    public init(from task: TodoTask) {
        let iso = ISO8601DateFormatter()
        self.id = task.id.uuidString
        self.title = task.title
        self.list = task.list.rawValue
        self.status = task.status == .completed ? "completed" : (task.status == .inProgress ? "in_progress" : "incomplete")
        self.notes = task.notes
        self.isEvening = task.isEvening
        self.orderIndex = task.orderIndex
        self.recurrenceRule = task.recurrenceRule
        self.checklist = task.checklist.map { ChecklistItemDTO(id: $0.id.uuidString, title: $0.title, isCompleted: $0.isCompleted) }
        self.reminderDate = task.reminderDate.map { iso.string(from: $0) }
        self.creationDate = iso.string(from: task.creationDate)
        self.completionDate = task.completionDate.map { iso.string(from: $0) }
    }
    
    public func toDictionary() -> [String: Any] {
        var d: [String: Any] = [
            "id": id,
            "title": title,
            "list": list,
            "status": status,
            "isEvening": isEvening,
            "orderIndex": orderIndex,
            "creationDate": creationDate,
            "checklist": checklist.map { ["id": $0.id, "title": $0.title, "isCompleted": $0.isCompleted] }
        ]
        if let notes = notes { d["notes"] = notes }
        if let recurrenceRule = recurrenceRule { d["recurrenceRule"] = recurrenceRule }
        if let reminderDate = reminderDate { d["reminderDate"] = reminderDate }
        if let completionDate = completionDate { d["completionDate"] = completionDate }
        return d
    }
}

public struct ChecklistItemDTO: Sendable {
    public let id: String
    public let title: String
    public let isCompleted: Bool
}
