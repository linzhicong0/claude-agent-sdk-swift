// MARK: - E2E Integration Tests

import XCTest
@testable import ClaudeAgentSDK

/// Integration tests that test the SDK components working together
/// These tests don't require a real CLI but test the full message flow
final class E2EIntegrationTests: XCTestCase {
    
    // MARK: - Message Flow Tests
    
    func testFullMessageParsingFlow() throws {
        // Simulate a complete conversation
        let messages = TestFixture.standardConversation()
        
        var parsedMessages: [Message] = []
        for data in messages {
            let message = try MessageParser.parse(data)
            parsedMessages.append(message)
        }
        
        XCTAssertEqual(parsedMessages.count, 3)
        
        // Verify system message
        if case .system(let systemMsg) = parsedMessages[0] {
            XCTAssertEqual(systemMsg.subtype, "init")
        } else {
            XCTFail("Expected system message")
        }
        
        // Verify assistant message
        if case .assistant(let assistantMsg) = parsedMessages[1] {
            XCTAssertTrue(assistantMsg.textContent.contains("Hello"))
        } else {
            XCTFail("Expected assistant message")
        }
        
        // Verify result message
        if case .result(let resultMsg) = parsedMessages[2] {
            XCTAssertEqual(resultMsg.subtype, .done)
        } else {
            XCTFail("Expected result message")
        }
    }
    
    func testToolUseConversationFlow() throws {
        let messages = TestFixture.toolUseConversation()
        
        var toolUseSeen = false
        var toolResultSeen = false
        
        for data in messages {
            let message = try MessageParser.parse(data)
            
            if case .assistant(let assistantMsg) = message {
                if !assistantMsg.toolUses.isEmpty {
                    toolUseSeen = true
                    XCTAssertEqual(assistantMsg.toolUses[0].name, "Read")
                }
            }
            
            if case .user(let userMsg) = message {
                if userMsg.parentToolUseId != nil {
                    toolResultSeen = true
                }
            }
        }
        
        XCTAssertTrue(toolUseSeen, "Should have seen tool use")
        XCTAssertTrue(toolResultSeen, "Should have seen tool result")
    }
    
    func testStreamingConversationFlow() throws {
        let messages = TestFixture.streamingConversation()
        
        var streamEventCount = 0
        var textDeltas: [String] = []
        
        for data in messages {
            let message = try MessageParser.parse(data)
            
            if case .streamEvent(let event) = message {
                streamEventCount += 1
                
                if event.event["type"]?.stringValue == "content_block_delta" {
                    if let delta = event.event["delta"]?.dictionaryValue,
                       let text = delta["text"] as? String {
                        textDeltas.append(text)
                    }
                }
            }
        }
        
        XCTAssertEqual(streamEventCount, 6)
        XCTAssertEqual(textDeltas.joined(), "Hello World")
    }
    
    // MARK: - MCP Server Integration Tests
    
    func testMCPServerFullFlow() async throws {
        // Create a server with multiple tools
        let server = SDKMCPServer(name: "calculator", version: "1.0.0", tools: [
            mcpTool(
                name: "add",
                description: "Add two numbers",
                parameters: [
                    "a": .number(description: "First number"),
                    "b": .number(description: "Second number")
                ],
                required: ["a", "b"]
            ) { args in
                let a = args["a"] as? Double ?? 0
                let b = args["b"] as? Double ?? 0
                return .text(String(a + b))
            },
            mcpTool(
                name: "multiply",
                description: "Multiply two numbers",
                parameters: [
                    "a": .number(description: "First number"),
                    "b": .number(description: "Second number")
                ],
                required: ["a", "b"]
            ) { args in
                let a = args["a"] as? Double ?? 0
                let b = args["b"] as? Double ?? 0
                return .text(String(a * b))
            }
        ])
        
        // Test initialize
        let initResponse = try await server.handleMessage([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize"
        ])
        
        XCTAssertNotNil(initResponse["result"])
        
        // Test tools/list
        let listResponse = try await server.handleMessage([
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list"
        ])
        
        let tools = (listResponse["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, 2)
        
        // Test tools/call - add
        let addResponse = try await server.handleMessage([
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": [
                "name": "add",
                "arguments": ["a": 10.0, "b": 20.0]
            ]
        ])
        
        let addResult = (addResponse["result"] as? [String: Any])?["content"] as? [[String: Any]]
        XCTAssertEqual(addResult?[0]["text"] as? String, "30.0")
        
        // Test tools/call - multiply
        let mulResponse = try await server.handleMessage([
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": [
                "name": "multiply",
                "arguments": ["a": 5.0, "b": 6.0]
            ]
        ])
        
        let mulResult = (mulResponse["result"] as? [String: Any])?["content"] as? [[String: Any]]
        XCTAssertEqual(mulResult?[0]["text"] as? String, "30.0")
    }
    
    // MARK: - Options Configuration Tests
    
    func testOptionsWithAllFeatures() {
        let server = SDKMCPServer(name: "test", version: "1.0.0")
        
        let options = ClaudeAgentOptions(
            tools: .list(["Read", "Write"]),
            allowedTools: ["Bash"],
            disallowedTools: ["WebSearch"],
            systemPrompt: .custom("You are a test assistant"),
            cwd: "/tmp/test",
            env: ["TEST_VAR": "test_value"],
            permissionMode: .acceptEdits,
            canUseTool: { toolName, input, context in
                return .allowTool()
            },
            continueConversation: false,
            maxTurns: 10,
            maxBudgetUSD: 1.0,
            model: "claude-sonnet-4-20250514",
            fallbackModel: "claude-haiku-3-5-20241022",
            betas: [.interleaved_thinking],
            mcpServers: ["test": .sdkServer(server)],
            hooks: [
                .preToolUse: [
                    HookMatcher(matcher: "Bash", hooks: [
                        { input, toolUseId, context in
                            HookOutput(shouldContinue: true)
                        }
                    ])
                ]
            ],
            includePartialMessages: true,
            agents: [
                "coder": AgentDefinition(
                    model: "claude-sonnet-4-20250514",
                    systemPrompt: "You are a coding assistant"
                )
            ],
            outputFormat: ["type": AnyCodable("object")],
            enableFileCheckpointing: true,
            maxThinkingTokens: 1000,
            maxBufferSize: 2_000_000,
            additionalDirectories: ["/home/user/project"]
        )
        
        XCTAssertNotNil(options.tools)
        XCTAssertEqual(options.allowedTools, ["Bash"])
        XCTAssertEqual(options.disallowedTools, ["WebSearch"])
        XCTAssertEqual(options.cwd, "/tmp/test")
        XCTAssertEqual(options.permissionMode, .acceptEdits)
        XCTAssertNotNil(options.canUseTool)
        XCTAssertEqual(options.maxTurns, 10)
        XCTAssertEqual(options.maxBudgetUSD, 1.0)
        XCTAssertEqual(options.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(options.fallbackModel, "claude-haiku-3-5-20241022")
        XCTAssertEqual(options.betas, [.interleaved_thinking])
        XCTAssertEqual(options.mcpServers.count, 1)
        XCTAssertNotNil(options.hooks)
        XCTAssertTrue(options.includePartialMessages)
        XCTAssertEqual(options.agents?.count, 1)
        XCTAssertNotNil(options.outputFormat)
        XCTAssertTrue(options.enableFileCheckpointing)
        XCTAssertEqual(options.maxThinkingTokens, 1000)
        XCTAssertEqual(options.maxBufferSize, 2_000_000)
        XCTAssertEqual(options.additionalDirectories, ["/home/user/project"])
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorMessageHandling() throws {
        let errorData: [String: Any] = [
            "type": "assistant",
            "message": [
                "role": "assistant",
                "content": []
            ],
            "model": "claude-sonnet-4-20250514",
            "error": [
                "type": "rate_limit",
                "message": "Rate limit exceeded. Please retry after 60 seconds."
            ]
        ]
        
        let message = try MessageParser.parse(errorData)
        
        if case .assistant(let assistantMsg) = message {
            XCTAssertNotNil(assistantMsg.error)
            XCTAssertEqual(assistantMsg.error?.type, "rate_limit")
            XCTAssertTrue(assistantMsg.error?.message.contains("Rate limit") ?? false)
        } else {
            XCTFail("Expected assistant message")
        }
    }
    
    func testResultErrorHandling() throws {
        let errorResult: [String: Any] = [
            "type": "result",
            "subtype": "error",
            "duration_ms": 100,
            "duration_api_ms": 0,
            "is_error": true,
            "num_turns": 0,
            "session_id": "error-session"
        ]
        
        let message = try MessageParser.parse(errorResult)
        
        if case .result(let resultMsg) = message {
            XCTAssertEqual(resultMsg.subtype, .error)
            XCTAssertTrue(resultMsg.isError)
        } else {
            XCTFail("Expected result message")
        }
    }
    
    // MARK: - Content Block Variety Tests
    
    func testAllContentBlockTypes() throws {
        let data: [String: Any] = [
            "type": "assistant",
            "message": [
                "role": "assistant",
                "content": [
                    ["type": "text", "text": "Let me help you."],
                    ["type": "thinking", "thinking": "Analyzing the request...", "signature": "sig123"],
                    ["type": "tool_use", "id": "tool-1", "name": "Read", "input": ["file_path": "/tmp/test.txt"]],
                    ["type": "tool_result", "tool_use_id": "tool-1", "content": "File contents", "is_error": false]
                ]
            ],
            "model": "claude-sonnet-4-20250514"
        ]
        
        let message = try MessageParser.parse(data)
        
        if case .assistant(let assistantMsg) = message {
            XCTAssertEqual(assistantMsg.content.count, 4)
            
            // Check text
            if case .text(let textBlock) = assistantMsg.content[0] {
                XCTAssertEqual(textBlock.text, "Let me help you.")
            } else {
                XCTFail("Expected text block")
            }
            
            // Check thinking
            if case .thinking(let thinkingBlock) = assistantMsg.content[1] {
                XCTAssertEqual(thinkingBlock.thinking, "Analyzing the request...")
                XCTAssertEqual(thinkingBlock.signature, "sig123")
            } else {
                XCTFail("Expected thinking block")
            }
            
            // Check tool use
            if case .toolUse(let toolUseBlock) = assistantMsg.content[2] {
                XCTAssertEqual(toolUseBlock.name, "Read")
            } else {
                XCTFail("Expected tool use block")
            }
            
            // Check tool result
            if case .toolResult(let toolResultBlock) = assistantMsg.content[3] {
                XCTAssertEqual(toolResultBlock.toolUseId, "tool-1")
                XCTAssertEqual(toolResultBlock.isError, false)
            } else {
                XCTFail("Expected tool result block")
            }
        } else {
            XCTFail("Expected assistant message")
        }
    }
}
