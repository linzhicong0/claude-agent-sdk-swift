// MARK: - Message Parser Tests

import XCTest

@testable import ClaudeAgentSDK

final class MessageParserTests: XCTestCase {

    // MARK: - User Message Parsing

    func testParseUserMessageWithTextContent() throws {
        let data: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": "Hello Claude!",
            ],
            "uuid": "user-msg-123",
        ]

        let message = try MessageParser.parse(data)

        guard case .user(let userMsg) = message else {
            XCTFail("Expected user message")
            return
        }

        XCTAssertEqual(userMsg.content.text, "Hello Claude!")
        XCTAssertEqual(userMsg.uuid, "user-msg-123")
        XCTAssertNil(userMsg.parentToolUseId)
    }

    func testParseUserMessageWithParentToolUseId() throws {
        let data: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": "Tool result content",
            ],
            "parent_tool_use_id": "tool-use-456",
        ]

        let message = try MessageParser.parse(data)

        guard case .user(let userMsg) = message else {
            XCTFail("Expected user message")
            return
        }

        XCTAssertEqual(userMsg.parentToolUseId, "tool-use-456")
    }

    func testParseUserMessageWithBlockContent() throws {
        let data: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [
                    ["type": "text", "text": "First block"],
                    ["type": "text", "text": "Second block"],
                ],
            ],
        ]

        let message = try MessageParser.parse(data)

        guard case .user(let userMsg) = message else {
            XCTFail("Expected user message")
            return
        }

        if case .blocks(let blocks) = userMsg.content {
            XCTAssertEqual(blocks.count, 2)
        } else {
            XCTFail("Expected block content")
        }
    }

    // MARK: - Assistant Message Parsing

    func testParseAssistantMessageWithText() throws {
        let data: [String: Any] = [
            "type": "assistant",
            "message": [
                "role": "assistant",
                "content": [
                    ["type": "text", "text": "Hello! How can I help you today?"]
                ],
            ],
            "model": "claude-sonnet-4-20250514",
        ]

        let message = try MessageParser.parse(data)

        guard case .assistant(let assistantMsg) = message else {
            XCTFail("Expected assistant message")
            return
        }

        XCTAssertEqual(assistantMsg.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(assistantMsg.textContent, "Hello! How can I help you today?")
        XCTAssertNil(assistantMsg.error)
    }

    func testParseAssistantMessageWithThinking() throws {
        let data: [String: Any] = [
            "type": "assistant",
            "message": [
                "role": "assistant",
                "content": [
                    [
                        "type": "thinking",
                        "thinking": "Let me analyze this request...",
                        "signature": "sig-abc123",
                    ],
                    ["type": "text", "text": "Here's my response."],
                ],
            ],
            "model": "claude-sonnet-4-20250514",
        ]

        let message = try MessageParser.parse(data)

        guard case .assistant(let assistantMsg) = message else {
            XCTFail("Expected assistant message")
            return
        }

        XCTAssertEqual(assistantMsg.content.count, 2)

        if case .thinking(let thinking) = assistantMsg.content[0] {
            XCTAssertEqual(thinking.thinking, "Let me analyze this request...")
            XCTAssertEqual(thinking.signature, "sig-abc123")
        } else {
            XCTFail("Expected thinking block")
        }
    }

    func testParseAssistantMessageWithToolUse() throws {
        let data: [String: Any] = [
            "type": "assistant",
            "message": [
                "role": "assistant",
                "content": [
                    [
                        "type": "tool_use",
                        "id": "tool-789",
                        "name": "Bash",
                        "input": [
                            "command": "ls -la /tmp"
                        ],
                    ]
                ],
            ],
            "model": "claude-sonnet-4-20250514",
        ]

        let message = try MessageParser.parse(data)

        guard case .assistant(let assistantMsg) = message else {
            XCTFail("Expected assistant message")
            return
        }

        XCTAssertEqual(assistantMsg.toolUses.count, 1)
        XCTAssertEqual(assistantMsg.toolUses[0].id, "tool-789")
        XCTAssertEqual(assistantMsg.toolUses[0].name, "Bash")
        XCTAssertEqual(assistantMsg.toolUses[0].input["command"]?.stringValue, "ls -la /tmp")
    }

    func testParseAssistantMessageWithError() throws {
        let data: [String: Any] = [
            "type": "assistant",
            "message": [
                "role": "assistant",
                "content": [],
            ],
            "model": "claude-sonnet-4-20250514",
            "error": [
                "type": "rate_limit",
                "message": "Rate limit exceeded",
            ],
        ]

        let message = try MessageParser.parse(data)

        guard case .assistant(let assistantMsg) = message else {
            XCTFail("Expected assistant message")
            return
        }

        XCTAssertNotNil(assistantMsg.error)
        XCTAssertEqual(assistantMsg.error?.type, "rate_limit")
        XCTAssertEqual(assistantMsg.error?.message, "Rate limit exceeded")
    }

    // MARK: - System Message Parsing

    func testParseSystemMessage() throws {
        let data: [String: Any] = [
            "type": "system",
            "subtype": "init",
            "session_id": "session-123",
            "cwd": "/home/user/project",
        ]

        let message = try MessageParser.parse(data)

        guard case .system(let systemMsg) = message else {
            XCTFail("Expected system message")
            return
        }

        XCTAssertEqual(systemMsg.subtype, "init")
    }

    // MARK: - Result Message Parsing

    func testParseResultMessageSuccess() throws {
        let data: [String: Any] = [
            "type": "result",
            "subtype": "done",
            "duration_ms": 2500,
            "duration_api_ms": 2000,
            "is_error": false,
            "num_turns": 3,
            "session_id": "session-789",
            "total_cost_usd": 0.0250,
        ]

        let message = try MessageParser.parse(data)

        guard case .result(let resultMsg) = message else {
            XCTFail("Expected result message")
            return
        }

        XCTAssertEqual(resultMsg.subtype, .done)
        XCTAssertEqual(resultMsg.durationMs, 2500)
        XCTAssertEqual(resultMsg.durationApiMs, 2000)
        XCTAssertFalse(resultMsg.isError)
        XCTAssertEqual(resultMsg.numTurns, 3)
        XCTAssertEqual(resultMsg.sessionId, "session-789")
        XCTAssertEqual(resultMsg.totalCostUSD, 0.0250)
    }

    func testParseResultMessageError() throws {
        let data: [String: Any] = [
            "type": "result",
            "subtype": "error",
            "duration_ms": 500,
            "duration_api_ms": 0,
            "is_error": true,
            "num_turns": 1,
            "session_id": "session-error",
        ]

        let message = try MessageParser.parse(data)

        guard case .result(let resultMsg) = message else {
            XCTFail("Expected result message")
            return
        }

        XCTAssertEqual(resultMsg.subtype, .error)
        XCTAssertTrue(resultMsg.isError)
    }

    func testParseResultMessageInterrupted() throws {
        let data: [String: Any] = [
            "type": "result",
            "subtype": "interrupted",
            "duration_ms": 1000,
            "duration_api_ms": 800,
            "is_error": false,
            "num_turns": 2,
            "session_id": "session-interrupted",
        ]

        let message = try MessageParser.parse(data)

        guard case .result(let resultMsg) = message else {
            XCTFail("Expected result message")
            return
        }

        XCTAssertEqual(resultMsg.subtype, .interrupted)
    }

    func testParseResultMessageWithUsage() throws {
        let data: [String: Any] = [
            "type": "result",
            "subtype": "done",
            "duration_ms": 1500,
            "duration_api_ms": 1200,
            "is_error": false,
            "num_turns": 2,
            "session_id": "session-usage",
            "usage": [
                "input_tokens": 100,
                "output_tokens": 500,
                "cache_creation_input_tokens": 0,
                "cache_read_input_tokens": 50,
            ],
        ]

        let message = try MessageParser.parse(data)

        guard case .result(let resultMsg) = message else {
            XCTFail("Expected result message")
            return
        }

        XCTAssertNotNil(resultMsg.usage)
        XCTAssertEqual(resultMsg.usage?["input_tokens"]?.intValue, 100)
        XCTAssertEqual(resultMsg.usage?["output_tokens"]?.intValue, 500)
    }

    func testParseResultMessageWithStructuredOutput() throws {
        let data: [String: Any] = [
            "type": "result",
            "subtype": "done",
            "duration_ms": 1500,
            "duration_api_ms": 1200,
            "is_error": false,
            "num_turns": 1,
            "session_id": "session-structured",
            "structured_output": [
                "name": "Test",
                "count": 42,
            ],
        ]

        let message = try MessageParser.parse(data)

        guard case .result(let resultMsg) = message else {
            XCTFail("Expected result message")
            return
        }

        XCTAssertNotNil(resultMsg.structuredOutput)
    }

    // MARK: - Stream Event Parsing

    func testParseStreamEventContentBlockStart() throws {
        let data: [String: Any] = [
            "type": "stream_event",
            "uuid": "event-001",
            "session_id": "session-stream",
            "event": [
                "type": "content_block_start",
                "index": 0,
                "content_block": [
                    "type": "text",
                    "text": "",
                ],
            ],
        ]

        let message = try MessageParser.parse(data)

        guard case .streamEvent(let event) = message else {
            XCTFail("Expected stream event")
            return
        }

        XCTAssertEqual(event.uuid, "event-001")
        XCTAssertEqual(event.sessionId, "session-stream")
        XCTAssertEqual(event.event["type"]?.stringValue, "content_block_start")
    }

    func testParseStreamEventContentBlockDelta() throws {
        let data: [String: Any] = [
            "type": "stream_event",
            "uuid": "event-002",
            "session_id": "session-stream",
            "event": [
                "type": "content_block_delta",
                "index": 0,
                "delta": [
                    "type": "text_delta",
                    "text": "Hello",
                ],
            ],
        ]

        let message = try MessageParser.parse(data)

        guard case .streamEvent(let event) = message else {
            XCTFail("Expected stream event")
            return
        }

        XCTAssertEqual(event.event["type"]?.stringValue, "content_block_delta")
    }

    func testParseStreamEventWithParentToolUseId() throws {
        let data: [String: Any] = [
            "type": "stream_event",
            "uuid": "event-003",
            "session_id": "session-stream",
            "event": [
                "type": "content_block_start"
            ],
            "parent_tool_use_id": "tool-parent-123",
        ]

        let message = try MessageParser.parse(data)

        guard case .streamEvent(let event) = message else {
            XCTFail("Expected stream event")
            return
        }

        XCTAssertEqual(event.parentToolUseId, "tool-parent-123")
    }

    // MARK: - Error Cases

    func testParseMissingTypeField() {
        let data: [String: Any] = [
            "content": "No type field"
        ]

        XCTAssertThrowsError(try MessageParser.parse(data)) { error in
            guard case ClaudeSDKError.messageParseError(_, let reason) = error else {
                XCTFail("Expected messageParseError")
                return
            }
            XCTAssertTrue(reason.contains("type"))
        }
    }

    func testParseInvalidMessageType() {
        let data: [String: Any] = [
            "type": "invalid_type"
        ]

        XCTAssertThrowsError(try MessageParser.parse(data)) { error in
            guard case ClaudeSDKError.messageParseError(_, let reason) = error else {
                XCTFail("Expected messageParseError")
                return
            }
            XCTAssertTrue(reason.contains("Unknown message type"))
        }
    }

    func testParseMissingMessageField() {
        let data: [String: Any] = [
            "type": "user"
                // Missing "message" field
        ]

        XCTAssertThrowsError(try MessageParser.parse(data)) { error in
            guard case ClaudeSDKError.messageParseError = error else {
                XCTFail("Expected messageParseError")
                return
            }
        }
    }

    func testParseMissingModelField() {
        // Model field is now optional and defaults to "unknown"
        let data: [String: Any] = [
            "type": "assistant",
            "message": [
                "id": "msg_test",
                "role": "assistant",
                "content": [
                    ["type": "text", "text": "Hello"]
                ],
            ],
            // Missing "model" field - should use default "unknown"
        ]

        let message = try? MessageParser.parse(data)
        XCTAssertNotNil(message)

        if case .assistant(let msg) = message {
            XCTAssertEqual(msg.model, "unknown")
        } else {
            XCTFail("Expected assistant message")
        }
    }

    func testParseResultMessageMissingSubtype() {
        let data: [String: Any] = [
            "type": "result",
            // Missing "subtype" field
            "duration_ms": 1000,
            "duration_api_ms": 800,
            "is_error": false,
            "num_turns": 1,
            "session_id": "session-123",
        ]

        XCTAssertThrowsError(try MessageParser.parse(data)) { error in
            guard case ClaudeSDKError.messageParseError(_, let reason) = error else {
                XCTFail("Expected messageParseError")
                return
            }
            XCTAssertTrue(reason.contains("Missing 'subtype' field"))
        }
    }

    func testParseResultMessageInvalidSubtype() {
        let data: [String: Any] = [
            "type": "result",
            "subtype": "unknown_subtype",  // Invalid subtype value
            "duration_ms": 1000,
            "duration_api_ms": 800,
            "is_error": false,
            "num_turns": 1,
            "session_id": "session-123",
        ]

        XCTAssertThrowsError(try MessageParser.parse(data)) { error in
            guard case ClaudeSDKError.messageParseError(_, let reason) = error else {
                XCTFail("Expected messageParseError")
                return
            }
            XCTAssertTrue(reason.contains("Invalid 'subtype' value 'unknown_subtype'"))
        }
    }

    func testParseResultMessageSuccessSubtype() throws {
        // Test the "success" subtype (API variant)
        let data: [String: Any] = [
            "type": "result",
            "subtype": "success",
            "duration_ms": 2500,
            "duration_api_ms": 2000,
            "is_error": false,
            "num_turns": 3,
            "session_id": "session-789",
            "total_cost_usd": 0.0250,
        ]

        let message = try MessageParser.parse(data)

        guard case .result(let resultMsg) = message else {
            XCTFail("Expected result message")
            return
        }

        XCTAssertEqual(resultMsg.subtype, .success)
        XCTAssertEqual(resultMsg.numTurns, 3)
    }
}
