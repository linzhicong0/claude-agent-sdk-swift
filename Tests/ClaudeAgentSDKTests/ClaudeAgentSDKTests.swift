// MARK: - Claude Agent SDK Tests

import XCTest
@testable import ClaudeAgentSDK

final class ClaudeAgentSDKTests: XCTestCase {
    
    // MARK: - Message Parser Tests
    
    func testParseUserMessage() throws {
        let data: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": "Hello Claude!"
            ],
            "uuid": "test-uuid-123"
        ]
        
        let message = try MessageParser.parse(data)
        
        guard case .user(let userMsg) = message else {
            XCTFail("Expected user message")
            return
        }
        
        XCTAssertEqual(userMsg.content.text, "Hello Claude!")
        XCTAssertEqual(userMsg.uuid, "test-uuid-123")
    }
    
    func testParseAssistantMessage() throws {
        let data: [String: Any] = [
            "type": "assistant",
            "message": [
                "role": "assistant",
                "content": [
                    ["type": "text", "text": "Hello! How can I help?"]
                ]
            ],
            "model": "claude-sonnet-4-20250514"
        ]
        
        let message = try MessageParser.parse(data)
        
        guard case .assistant(let assistantMsg) = message else {
            XCTFail("Expected assistant message")
            return
        }
        
        XCTAssertEqual(assistantMsg.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(assistantMsg.textContent, "Hello! How can I help?")
    }
    
    func testParseToolUseBlock() throws {
        let data: [String: Any] = [
            "type": "assistant",
            "message": [
                "role": "assistant",
                "content": [
                    [
                        "type": "tool_use",
                        "id": "tool-123",
                        "name": "Bash",
                        "input": ["command": "ls -la"]
                    ]
                ]
            ],
            "model": "claude-sonnet-4-20250514"
        ]
        
        let message = try MessageParser.parse(data)
        
        guard case .assistant(let assistantMsg) = message else {
            XCTFail("Expected assistant message")
            return
        }
        
        XCTAssertEqual(assistantMsg.toolUses.count, 1)
        XCTAssertEqual(assistantMsg.toolUses[0].name, "Bash")
        XCTAssertEqual(assistantMsg.toolUses[0].id, "tool-123")
    }
    
    func testParseResultMessage() throws {
        let data: [String: Any] = [
            "type": "result",
            "subtype": "done",
            "duration_ms": 1500,
            "duration_api_ms": 1200,
            "is_error": false,
            "num_turns": 2,
            "session_id": "session-456",
            "total_cost_usd": 0.0125
        ]
        
        let message = try MessageParser.parse(data)
        
        guard case .result(let resultMsg) = message else {
            XCTFail("Expected result message")
            return
        }
        
        XCTAssertEqual(resultMsg.subtype, .done)
        XCTAssertEqual(resultMsg.durationMs, 1500)
        XCTAssertEqual(resultMsg.numTurns, 2)
        XCTAssertEqual(resultMsg.totalCostUSD, 0.0125)
    }
    
    func testParseStreamEvent() throws {
        let data: [String: Any] = [
            "type": "stream_event",
            "uuid": "event-789",
            "session_id": "session-123",
            "event": [
                "type": "content_block_delta",
                "delta": ["text": "Hello"]
            ]
        ]
        
        let message = try MessageParser.parse(data)
        
        guard case .streamEvent(let event) = message else {
            XCTFail("Expected stream event")
            return
        }
        
        XCTAssertEqual(event.uuid, "event-789")
        XCTAssertEqual(event.sessionId, "session-123")
    }
    
    func testParseUnknownTypeThrows() {
        let data: [String: Any] = [
            "type": "unknown_type",
            "data": "test"
        ]
        
        XCTAssertThrowsError(try MessageParser.parse(data)) { error in
            guard case ClaudeSDKError.messageParseError(_, let reason) = error else {
                XCTFail("Expected messageParseError")
                return
            }
            XCTAssertTrue(reason.contains("Unknown message type"))
        }
    }
    
    // MARK: - Content Block Tests
    
    func testTextBlock() {
        let block = TextBlock(text: "Hello world")
        XCTAssertEqual(block.text, "Hello world")
    }
    
    func testThinkingBlock() {
        let block = ThinkingBlock(thinking: "Let me think...", signature: "sig123")
        XCTAssertEqual(block.thinking, "Let me think...")
        XCTAssertEqual(block.signature, "sig123")
    }
    
    func testToolUseBlock() {
        let input: [String: AnyCodable] = ["command": AnyCodable("ls")]
        let block = ToolUseBlock(id: "tool1", name: "Bash", input: input)
        
        XCTAssertEqual(block.id, "tool1")
        XCTAssertEqual(block.name, "Bash")
        XCTAssertEqual(block.input["command"]?.stringValue, "ls")
    }
    
    // MARK: - AnyCodable Tests
    
    func testAnyCodableString() {
        let value = AnyCodable("hello")
        XCTAssertEqual(value.stringValue, "hello")
    }
    
    func testAnyCodableInt() {
        let value = AnyCodable(42)
        XCTAssertEqual(value.intValue, 42)
    }
    
    func testAnyCodableDouble() {
        let value = AnyCodable(3.14)
        XCTAssertEqual(value.doubleValue, 3.14)
    }
    
    func testAnyCodableBool() {
        let value = AnyCodable(true)
        XCTAssertEqual(value.boolValue, true)
    }
    
    func testAnyCodableEquality() {
        XCTAssertEqual(AnyCodable("test"), AnyCodable("test"))
        XCTAssertEqual(AnyCodable(42), AnyCodable(42))
        XCTAssertNotEqual(AnyCodable("test"), AnyCodable(42))
    }
    
    // MARK: - Options Tests
    
    func testDefaultOptions() {
        let options = ClaudeAgentOptions()
        
        XCTAssertNil(options.cwd)
        XCTAssertNil(options.model)
        XCTAssertFalse(options.continueConversation)
        XCTAssertTrue(options.allowedTools.isEmpty)
        XCTAssertTrue(options.disallowedTools.isEmpty)
    }
    
    func testOptionsWithValues() {
        let options = ClaudeAgentOptions(
            allowedTools: ["Read", "Write"],
            cwd: "/tmp",
            permissionMode: .acceptEdits,
            maxTurns: 5,
            model: "claude-sonnet-4-20250514"
        )
        
        XCTAssertEqual(options.cwd, "/tmp")
        XCTAssertEqual(options.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(options.permissionMode, .acceptEdits)
        XCTAssertEqual(options.maxTurns, 5)
        XCTAssertEqual(options.allowedTools, ["Read", "Write"])
    }
    
    // MARK: - MCP Server Tests
    
    func testMCPServerCreation() {
        let server = SDKMCPServer(name: "test", version: "1.0.0")
        
        XCTAssertEqual(server.name, "test")
        XCTAssertEqual(server.version, "1.0.0")
        XCTAssertTrue(server.tools.isEmpty)
    }
    
    func testMCPToolCreation() {
        let tool = mcpTool(
            name: "add",
            description: "Add numbers",
            parameters: [
                "a": .number(description: "First number"),
                "b": .number(description: "Second number")
            ],
            required: ["a", "b"]
        ) { args in
            .text("result")
        }
        
        XCTAssertEqual(tool.name, "add")
        XCTAssertEqual(tool.description, "Add numbers")
    }
    
    func testMCPServerHandleToolsList() async throws {
        let server = SDKMCPServer(name: "calc", version: "1.0.0", tools: [
            mcpTool(name: "add", description: "Add", parameters: [:], required: []) { _ in .text("") }
        ])
        
        let response = try await server.handleMessage([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/list"
        ])
        
        let result = response["result"] as? [String: Any]
        let tools = result?["tools"] as? [[String: Any]]
        
        XCTAssertEqual(tools?.count, 1)
        XCTAssertEqual(tools?[0]["name"] as? String, "add")
    }
    
    func testMCPServerHandleToolCall() async throws {
        let server = SDKMCPServer(name: "calc", version: "1.0.0", tools: [
            mcpTool(name: "add", description: "Add", parameters: [:], required: []) { args in
                let a = args["a"] as? Double ?? 0
                let b = args["b"] as? Double ?? 0
                return .text("Result: \(a + b)")
            }
        ])
        
        let response = try await server.handleMessage([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": [
                "name": "add",
                "arguments": ["a": 5.0, "b": 3.0]
            ]
        ])
        
        let result = response["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]
        
        XCTAssertEqual(content?[0]["text"] as? String, "Result: 8.0")
    }
    
    // MARK: - Error Tests
    
    func testCLINotFoundError() {
        let error = ClaudeSDKError.cliNotFound(searchedPaths: ["/usr/bin/claude", "/usr/local/bin/claude"])
        
        XCTAssertTrue(error.localizedDescription.contains("Claude Code CLI not found"))
        XCTAssertTrue(error.localizedDescription.contains("/usr/bin/claude"))
    }
    
    func testProcessError() {
        let error = ClaudeSDKError.processError(exitCode: 1, stderr: "Something went wrong")
        
        XCTAssertTrue(error.localizedDescription.contains("exit"))
        XCTAssertTrue(error.localizedDescription.contains("1"))
        XCTAssertTrue(error.localizedDescription.contains("Something went wrong"))
    }
    
    func testTimeoutError() {
        let error = ClaudeSDKError.timeout(operation: "control_request", duration: 60.0)
        
        XCTAssertTrue(error.localizedDescription.contains("timed out"))
        XCTAssertTrue(error.localizedDescription.contains("60"))
    }
    
    // MARK: - Hook Output Tests
    
    func testHookOutputDefaults() {
        let output = HookOutput()
        
        XCTAssertTrue(output.shouldContinue)
        XCTAssertFalse(output.suppressOutput)
        XCTAssertNil(output.stopReason)
        XCTAssertNil(output.decision)
    }
    
    func testHookOutputBlock() {
        let output = HookOutput(
            shouldContinue: false,
            decision: .block,
            reason: "Not allowed"
        )
        
        XCTAssertFalse(output.shouldContinue)
        XCTAssertEqual(output.decision, .block)
        XCTAssertEqual(output.reason, "Not allowed")
    }
    
    // MARK: - Permission Result Tests
    
    func testPermissionResultAllow() {
        let result = PermissionResult.allowTool()
        
        if case .allow(let input, let permissions) = result {
            XCTAssertNil(input)
            XCTAssertNil(permissions)
        } else {
            XCTFail("Expected allow result")
        }
    }
    
    func testPermissionResultDeny() {
        let result = PermissionResult.denyTool(message: "Not permitted", interrupt: true)
        
        if case .deny(let message, let interrupt) = result {
            XCTAssertEqual(message, "Not permitted")
            XCTAssertTrue(interrupt)
        } else {
            XCTFail("Expected deny result")
        }
    }
}
