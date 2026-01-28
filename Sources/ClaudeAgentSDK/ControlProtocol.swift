// MARK: - Control Protocol

import Foundation

/// Default timeout for control protocol requests (60 seconds)
let defaultControlTimeout: TimeInterval = 60.0

/// Actor managing the control protocol for bidirectional communication
public actor ControlProtocol {

    // MARK: - Types

    /// Pending request state
    private struct PendingRequest {
        let continuation: CheckedContinuation<[String: Any], Error>
        let timestamp: Date
    }

    // MARK: - Properties

    private var requestCounter = 0
    private var pendingRequests: [String: PendingRequest] = [:]

    private let transport: SubprocessCLITransport
    private let options: ClaudeAgentOptions
    private let sdkMCPServers: [String: SDKMCPServer]

    /// Messages buffered during control request processing that should be forwarded to user
    private var bufferedMessages: [[String: Any]] = []

    // MARK: - Initialization

    public init(transport: SubprocessCLITransport, options: ClaudeAgentOptions) {
        self.transport = transport
        self.options = options

        // Extract SDK MCP servers
        var servers: [String: SDKMCPServer] = [:]
        for (name, config) in options.mcpServers {
            if case .sdkServer(let server) = config {
                servers[name] = server
            }
        }
        self.sdkMCPServers = servers
    }

    // MARK: - Buffered Messages

    /// Get and clear any messages that were buffered during control request processing
    public func drainBufferedMessages() -> [[String: Any]] {
        let messages = bufferedMessages
        bufferedMessages = []
        return messages
    }

    // MARK: - Request ID Generation

    /// Generate a unique request ID
    private func generateRequestId() -> String {
        requestCounter += 1
        let randomHex = String(format: "%08x", arc4random())
        return "req_\(requestCounter)_\(randomHex)"
    }

    // MARK: - SDK-Initiated Control Requests

    /// Send an initialize request to establish control protocol
    public func initialize() async throws -> [String: Any] {
        var request: [String: Any] = [
            "subtype": "initialize",
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "textEditor": true,
                "checkpoints": options.enableFileCheckpointing,
                "sdkMcpServers": !sdkMCPServers.isEmpty,
            ],
        ]

        // Include hooks info
        if let hooks = options.hooks, !hooks.isEmpty {
            var hooksConfig: [[String: Any]] = []
            for (event, matchers) in hooks {
                for matcher in matchers {
                    var hookDef: [String: Any] = [
                        "type": "sdk",
                        "event": event.rawValue,
                    ]
                    if let pattern = matcher.matcher {
                        hookDef["matcher"] = pattern
                    }
                    hooksConfig.append(hookDef)
                }
            }
            request["hooks"] = hooksConfig
        }

        // Include SDK MCP servers info
        if !sdkMCPServers.isEmpty {
            request["sdkMcpServers"] = Array(sdkMCPServers.keys)
        }

        return try await sendControlRequestWithReader(request, timeout: defaultControlTimeout)
    }

    /// Send an interrupt request to cancel ongoing operation
    public func interrupt() async throws {
        let request: [String: Any] = ["subtype": "interrupt"]
        _ = try await sendControlRequestWithReader(request, timeout: 5.0)
    }

    /// Change the model mid-conversation
    public func setModel(_ model: String) async throws {
        let request: [String: Any] = [
            "subtype": "set_model",
            "model": model,
        ]
        _ = try await sendControlRequestWithReader(request, timeout: 10.0)
    }

    /// Change permission mode dynamically
    public func setPermissionMode(_ mode: PermissionMode) async throws {
        let request: [String: Any] = [
            "subtype": "set_permission_mode",
            "permission_mode": mode.rawValue,
        ]
        _ = try await sendControlRequestWithReader(request, timeout: 10.0)
    }

    /// Rewind files to a checkpoint
    public func rewindFiles(to checkpointId: String) async throws {
        let request: [String: Any] = [
            "subtype": "rewind_files",
            "checkpoint_id": checkpointId,
        ]
        _ = try await sendControlRequestWithReader(request, timeout: 30.0)
    }

    /// Get MCP server connection status
    public func getMcpStatus() async throws -> [String: Any] {
        let request: [String: Any] = ["subtype": "mcp_status"]
        return try await sendControlRequestWithReader(request, timeout: 10.0)
    }

    // MARK: - Control Request Sending

    /// Send a control request and wait for response (with its own message reader)
    /// This method handles its own message reading and should only be used during initialization
    /// or when no other message reader is active.
    private func sendControlRequestWithReader(_ request: [String: Any], timeout: TimeInterval)
        async throws
        -> [String: Any]
    {
        let requestId = generateRequestId()

        let controlRequest: [String: Any] = [
            "type": "control_request",
            "request_id": requestId,
            "request": request,
        ]

        // Serialize to JSON
        let jsonData = try JSONSerialization.data(withJSONObject: controlRequest)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ClaudeSDKError.controlProtocolError(reason: "Failed to serialize control request")
        }

        // Send the request first
        try await transport.write(jsonString)

        // Read messages with a cancellable task to get our response
        // Use withThrowingTaskGroup so we can properly cancel reading when done
        return try await withThrowingTaskGroup(of: [String: Any]?.self) { group in
            // Reader task
            group.addTask { [self] in
                for try await data in await self.transport.readMessages() {
                    // Check for cancellation
                    try Task.checkCancellation()

                    guard let type = data["type"] as? String else {
                        // Non-typed message, buffer it for later
                        await self.appendBufferedMessage(data)
                        continue
                    }

                    // Check if this is our control response
                    if type == "control_response" {
                        if let response = data["response"] as? [String: Any],
                            let responseId = response["request_id"] as? String,
                            responseId == requestId
                        {
                            // This is our response - return it
                            return response
                        }
                    }

                    // Handle control_request from CLI
                    if type == "control_request" {
                        try await self.handleControlRequest(data)
                        continue
                    }

                    // Buffer any other messages (assistant, result, etc.) for later
                    await self.appendBufferedMessage(data)
                }
                return nil  // Stream ended without response
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ClaudeSDKError.timeout(operation: "control_request", duration: timeout)
            }

            // Wait for first result
            while let result = try await group.next() {
                if let response = result {
                    // Got our response, cancel other tasks
                    group.cancelAll()

                    // Check for error in response
                    if let error = response["error"] as? String {
                        throw ClaudeSDKError.controlProtocolError(reason: error)
                    }
                    return response
                }
            }

            throw ClaudeSDKError.connectionFailed(
                reason: "Transport closed before receiving response")
        }
    }

    /// Helper to append to buffered messages (for use from within task group)
    private func appendBufferedMessage(_ data: [String: Any]) {
        bufferedMessages.append(data)
    }

    /// Register a pending request
    private func registerPendingRequest(
        requestId: String, continuation: CheckedContinuation<[String: Any], Error>
    ) {
        pendingRequests[requestId] = PendingRequest(
            continuation: continuation,
            timestamp: Date()
        )
    }

    /// Remove a pending request
    private func removePendingRequest(requestId: String) {
        pendingRequests.removeValue(forKey: requestId)
    }

    // MARK: - CLI-Initiated Request Handling

    /// Handle an incoming control request from CLI
    public func handleControlRequest(_ data: [String: Any]) async throws {
        guard let requestId = data["request_id"] as? String,
            let request = data["request"] as? [String: Any],
            let subtype = request["subtype"] as? String
        else {
            return
        }

        var response: [String: Any]

        do {
            switch subtype {
            case "can_use_tool":
                response = try await handleCanUseTool(request)
            case "hook_callback":
                response = try await handleHookCallback(request)
            case "mcp_message":
                response = try await handleMCPMessage(request)
            default:
                response = [
                    "subtype": "error",
                    "request_id": requestId,
                    "error": "Unknown control request subtype: \(subtype)",
                ]
            }
        } catch {
            response = [
                "subtype": "error",
                "request_id": requestId,
                "error": error.localizedDescription,
            ]
        }

        // Send response
        let controlResponse: [String: Any] = [
            "type": "control_response",
            "response": response.merging(["request_id": requestId]) { _, new in new },
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: controlResponse)
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            try await transport.write(jsonString)
        }
    }

    /// Handle a control response from CLI
    public func handleControlResponse(_ data: [String: Any]) {
        guard let response = data["response"] as? [String: Any],
            let requestId = response["request_id"] as? String,
            let pending = pendingRequests.removeValue(forKey: requestId)
        else {
            return
        }

        if let error = response["error"] as? String {
            pending.continuation.resume(
                throwing: ClaudeSDKError.controlProtocolError(reason: error))
        } else {
            pending.continuation.resume(returning: response)
        }
    }

    // MARK: - Tool Permission Handling

    /// Handle can_use_tool request
    private func handleCanUseTool(_ request: [String: Any]) async throws -> [String: Any] {
        guard let callback = options.canUseTool else {
            return ["subtype": "success", "behavior": "allow"]
        }

        guard let toolName = request["tool_name"] as? String,
            let toolInput = request["tool_input"] as? [String: Any]
        else {
            throw ClaudeSDKError.controlProtocolError(reason: "Invalid can_use_tool request")
        }

        let sessionId = request["session_id"] as? String ?? "default"
        let context = ToolPermissionContext(sessionId: sessionId)

        let result = try await callback(toolName, toolInput, context)

        switch result {
        case .allow(let updatedInput, let updatedPermissions):
            var response: [String: Any] = [
                "subtype": "success",
                "behavior": "allow",
            ]
            if let input = updatedInput {
                response["updated_input"] = input
            }
            if let permissions = updatedPermissions {
                response["updated_permissions"] = permissions.map { perm in
                    ["tool_name": perm.toolName, "permission": perm.permission]
                }
            }
            return response

        case .deny(let message, let interrupt):
            return [
                "subtype": "success",
                "behavior": "deny",
                "message": message,
                "interrupt": interrupt,
            ]
        }
    }

    // MARK: - Hook Handling

    /// Handle hook_callback request
    private func handleHookCallback(_ request: [String: Any]) async throws -> [String: Any] {
        guard let eventStr = request["hook_event"] as? String,
            let event = HookEvent(rawValue: eventStr)
        else {
            throw ClaudeSDKError.controlProtocolError(reason: "Invalid hook event")
        }

        guard let matchers = options.hooks?[event] else {
            return ["subtype": "success", "continue": true]
        }

        let toolName = request["tool_name"] as? String
        let toolUseId = request["tool_use_id"] as? String
        let sessionId = request["session_id"] as? String ?? "default"

        // Build hook input
        var toolInput: [String: AnyCodable]?
        if let input = request["tool_input"] as? [String: Any] {
            toolInput = input.mapValues { AnyCodable($0) }
        }

        var toolOutput: AnyCodable?
        if let output = request["tool_output"] {
            toolOutput = AnyCodable(output)
        }

        let hookInput = HookInput(
            hookEventName: event,
            toolName: toolName,
            toolInput: toolInput,
            toolOutput: toolOutput,
            prompt: request["prompt"] as? String,
            stopReason: request["stop_reason"] as? String
        )

        let context = HookContext(sessionId: sessionId)

        // Find matching hooks
        for matcher in matchers {
            // Check if matcher applies
            if let pattern = matcher.matcher, let toolName = toolName {
                // Simple pattern matching (could be regex in full impl)
                if !toolName.contains(pattern) && pattern != toolName {
                    continue
                }
            }

            // Execute all hooks in this matcher
            for hook in matcher.hooks {
                let timeout = matcher.timeout ?? 30.0

                let output: HookOutput
                do {
                    output = try await withThrowingTaskGroup(of: HookOutput.self) { group in
                        group.addTask {
                            try await hook(hookInput, toolUseId, context)
                        }
                        group.addTask {
                            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                            throw ClaudeSDKError.timeout(
                                operation: "hook_callback", duration: timeout)
                        }

                        let result = try await group.next()!
                        group.cancelAll()
                        return result
                    }
                } catch {
                    return [
                        "subtype": "error",
                        "error": error.localizedDescription,
                    ]
                }

                // Build response (convert Swift keywords back)
                var response: [String: Any] = [
                    "subtype": "success",
                    "continue": output.shouldContinue,  // Note: "continue" is reserved in Swift
                ]

                if output.suppressOutput {
                    response["suppressOutput"] = true
                }
                if let stopReason = output.stopReason {
                    response["stopReason"] = stopReason
                }
                if let decision = output.decision {
                    response["decision"] = decision.rawValue
                }
                if let systemMessage = output.systemMessage {
                    response["systemMessage"] = systemMessage
                }
                if let reason = output.reason {
                    response["reason"] = reason
                }
                if let specific = output.hookSpecificOutput {
                    var specificOutput: [String: Any] = [
                        "hookEventName": specific.hookEventName.rawValue
                    ]
                    if let permissionDecision = specific.permissionDecision {
                        specificOutput["permissionDecision"] = permissionDecision
                    }
                    if let permissionDecisionReason = specific.permissionDecisionReason {
                        specificOutput["permissionDecisionReason"] = permissionDecisionReason
                    }
                    if let additionalContext = specific.additionalContext {
                        specificOutput["additionalContext"] = additionalContext
                    }
                    if let updatedInput = specific.updatedInput {
                        specificOutput["updatedInput"] = updatedInput
                    }
                    response["hookSpecificOutput"] = specificOutput
                }

                // If hook blocked, return immediately
                if output.decision == .block || output.decision == .deny || !output.shouldContinue {
                    return response
                }
            }
        }

        return ["subtype": "success", "continue": true]
    }

    // MARK: - MCP Server Message Handling

    /// Handle mcp_message request (route to SDK MCP server)
    private func handleMCPMessage(_ request: [String: Any]) async throws -> [String: Any] {
        guard let serverName = request["server_name"] as? String,
            let message = request["message"] as? [String: Any]
        else {
            throw ClaudeSDKError.controlProtocolError(reason: "Invalid mcp_message request")
        }

        guard let server = sdkMCPServers[serverName] else {
            return [
                "subtype": "success",
                "result": [
                    "jsonrpc": "2.0",
                    "error": ["code": -32601, "message": "Server not found: \(serverName)"],
                ],
            ]
        }

        // Route to SDK MCP server
        let result = try await server.handleMessage(message)

        return [
            "subtype": "success",
            "result": result,
        ]
    }

    // MARK: - Message Routing

    /// Route an incoming message - returns nil for control messages (handled internally)
    public func routeMessage(_ data: [String: Any]) async throws -> [String: Any]? {
        guard let type = data["type"] as? String else {
            return data
        }

        switch type {
        case "control_request":
            try await handleControlRequest(data)
            return nil

        case "control_response":
            handleControlResponse(data)
            return nil

        default:
            return data
        }
    }
}
