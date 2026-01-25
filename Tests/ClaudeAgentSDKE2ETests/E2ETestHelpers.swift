// MARK: - E2E Test Helpers

import Foundation
@testable import ClaudeAgentSDK

/// Mock CLI transport for E2E testing without real CLI
actor MockCLITransport {
    private var responses: [[String: Any]] = []
    private var responseIndex = 0
    private var writtenMessages: [String] = []
    
    func addResponse(_ response: [String: Any]) {
        responses.append(response)
    }
    
    func addResponses(_ newResponses: [[String: Any]]) {
        responses.append(contentsOf: newResponses)
    }
    
    func write(_ message: String) {
        writtenMessages.append(message)
    }
    
    func nextResponse() -> [String: Any]? {
        guard responseIndex < responses.count else { return nil }
        let response = responses[responseIndex]
        responseIndex += 1
        return response
    }
    
    func getWrittenMessages() -> [String] {
        return writtenMessages
    }
    
    func reset() {
        responses.removeAll()
        responseIndex = 0
        writtenMessages.removeAll()
    }
}

/// Standard mock responses for testing
struct MockResponses {
    
    /// Simple assistant response
    static func assistantMessage(text: String, model: String = "claude-sonnet-4-20250514") -> [String: Any] {
        [
            "type": "assistant",
            "message": [
                "role": "assistant",
                "content": [
                    ["type": "text", "text": text]
                ]
            ],
            "model": model
        ]
    }
    
    /// Tool use response
    static func toolUseMessage(id: String, name: String, input: [String: Any], model: String = "claude-sonnet-4-20250514") -> [String: Any] {
        [
            "type": "assistant",
            "message": [
                "role": "assistant",
                "content": [
                    [
                        "type": "tool_use",
                        "id": id,
                        "name": name,
                        "input": input
                    ]
                ]
            ],
            "model": model
        ]
    }
    
    /// User message (tool result)
    static func userMessage(content: String, parentToolUseId: String? = nil) -> [String: Any] {
        var msg: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": content
            ]
        ]
        if let id = parentToolUseId {
            msg["parent_tool_use_id"] = id
        }
        return msg
    }
    
    /// Success result
    static func resultMessage(
        subtype: String = "done",
        durationMs: Int = 1000,
        numTurns: Int = 1,
        sessionId: String = "mock-session",
        costUSD: Double? = 0.01
    ) -> [String: Any] {
        var result: [String: Any] = [
            "type": "result",
            "subtype": subtype,
            "duration_ms": durationMs,
            "duration_api_ms": Int(Double(durationMs) * 0.8),
            "is_error": subtype == "error",
            "num_turns": numTurns,
            "session_id": sessionId
        ]
        if let cost = costUSD {
            result["total_cost_usd"] = cost
        }
        return result
    }
    
    /// System init message
    static func systemInitMessage(sessionId: String = "mock-session") -> [String: Any] {
        [
            "type": "system",
            "subtype": "init",
            "session_id": sessionId,
            "cwd": "/tmp"
        ]
    }
    
    /// Stream event
    static func streamEvent(uuid: String, eventType: String, data: [String: Any] = [:], sessionId: String = "mock-session") -> [String: Any] {
        [
            "type": "stream_event",
            "uuid": uuid,
            "session_id": sessionId,
            "event": ["type": eventType].merging(data) { _, new in new }
        ]
    }
    
    /// Control response (success)
    static func controlResponse(requestId: String, data: [String: Any] = [:]) -> [String: Any] {
        [
            "type": "control_response",
            "response": ["request_id": requestId, "subtype": "success"].merging(data) { _, new in new }
        ]
    }
    
    /// Control request (can_use_tool)
    static func canUseToolRequest(requestId: String, toolName: String, toolInput: [String: Any], sessionId: String = "mock-session") -> [String: Any] {
        [
            "type": "control_request",
            "request_id": requestId,
            "request": [
                "subtype": "can_use_tool",
                "tool_name": toolName,
                "tool_input": toolInput,
                "session_id": sessionId
            ]
        ]
    }
    
    /// Control request (hook_callback)
    static func hookCallbackRequest(
        requestId: String,
        hookEvent: String,
        toolName: String? = nil,
        toolInput: [String: Any]? = nil,
        sessionId: String = "mock-session"
    ) -> [String: Any] {
        var request: [String: Any] = [
            "subtype": "hook_callback",
            "hook_event": hookEvent,
            "session_id": sessionId
        ]
        if let name = toolName {
            request["tool_name"] = name
        }
        if let input = toolInput {
            request["tool_input"] = input
        }
        
        return [
            "type": "control_request",
            "request_id": requestId,
            "request": request
        ]
    }
    
    /// Control request (mcp_message)
    static func mcpMessageRequest(requestId: String, serverName: String, message: [String: Any]) -> [String: Any] {
        [
            "type": "control_request",
            "request_id": requestId,
            "request": [
                "subtype": "mcp_message",
                "server_name": serverName,
                "message": message
            ]
        ]
    }
}

/// Test fixture for common test scenarios
class TestFixture {
    
    /// Create options with common test settings
    static func testOptions(
        model: String = "claude-sonnet-4-20250514",
        maxTurns: Int = 5,
        permissionMode: PermissionMode = .default
    ) -> ClaudeAgentOptions {
        ClaudeAgentOptions(
            cwd: "/tmp",
            permissionMode: permissionMode,
            maxTurns: maxTurns,
            model: model
        )
    }
    
    /// Create a standard conversation flow
    static func standardConversation() -> [[String: Any]] {
        [
            MockResponses.systemInitMessage(),
            MockResponses.assistantMessage(text: "Hello! How can I help you today?"),
            MockResponses.resultMessage()
        ]
    }
    
    /// Create a tool use conversation flow
    static func toolUseConversation() -> [[String: Any]] {
        [
            MockResponses.systemInitMessage(),
            MockResponses.toolUseMessage(id: "tool-1", name: "Read", input: ["file_path": "/tmp/test.txt"]),
            MockResponses.userMessage(content: "File contents here", parentToolUseId: "tool-1"),
            MockResponses.assistantMessage(text: "I've read the file. Here's what I found..."),
            MockResponses.resultMessage(numTurns: 2)
        ]
    }
    
    /// Create a streaming conversation with partial messages
    static func streamingConversation() -> [[String: Any]] {
        [
            MockResponses.systemInitMessage(),
            MockResponses.streamEvent(uuid: "e1", eventType: "message_start"),
            MockResponses.streamEvent(uuid: "e2", eventType: "content_block_start", data: ["index": 0]),
            MockResponses.streamEvent(uuid: "e3", eventType: "content_block_delta", data: ["delta": ["text": "Hello"]]),
            MockResponses.streamEvent(uuid: "e4", eventType: "content_block_delta", data: ["delta": ["text": " World"]]),
            MockResponses.streamEvent(uuid: "e5", eventType: "content_block_stop"),
            MockResponses.streamEvent(uuid: "e6", eventType: "message_stop"),
            MockResponses.assistantMessage(text: "Hello World"),
            MockResponses.resultMessage()
        ]
    }
}
