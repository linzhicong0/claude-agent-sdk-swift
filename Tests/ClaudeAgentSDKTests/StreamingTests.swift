// MARK: - Streaming Tests

import XCTest
@testable import ClaudeAgentSDK

final class StreamingTests: XCTestCase {
    
    // MARK: - Stream Event Tests
    
    func testStreamEventConstruction() {
        let event = StreamEvent(
            uuid: "event-123",
            sessionId: "session-456",
            event: [
                "type": AnyCodable("content_block_delta"),
                "delta": AnyCodable(["text": "Hello"])
            ],
            parentToolUseId: nil
        )
        
        XCTAssertEqual(event.uuid, "event-123")
        XCTAssertEqual(event.sessionId, "session-456")
        XCTAssertEqual(event.event["type"]?.stringValue, "content_block_delta")
    }
    
    func testStreamEventWithParentToolUseId() {
        let event = StreamEvent(
            uuid: "event-789",
            sessionId: "session-123",
            event: ["type": AnyCodable("message_start")],
            parentToolUseId: "tool-use-abc"
        )
        
        XCTAssertEqual(event.parentToolUseId, "tool-use-abc")
    }
    
    func testStreamEventEquality() {
        let event1 = StreamEvent(
            uuid: "event-1",
            sessionId: "session-1",
            event: ["type": AnyCodable("test")],
            parentToolUseId: nil
        )
        
        let event2 = StreamEvent(
            uuid: "event-1",
            sessionId: "session-1",
            event: ["type": AnyCodable("test")],
            parentToolUseId: nil
        )
        
        XCTAssertEqual(event1, event2)
    }
    
    // MARK: - Async Stream Tests
    
    func testAsyncThrowingStreamBasics() async throws {
        let stream = AsyncThrowingStream<Int, Error> { continuation in
            continuation.yield(1)
            continuation.yield(2)
            continuation.yield(3)
            continuation.finish()
        }
        
        var values: [Int] = []
        for try await value in stream {
            values.append(value)
        }
        
        XCTAssertEqual(values, [1, 2, 3])
    }
    
    func testAsyncThrowingStreamWithError() async {
        let stream = AsyncThrowingStream<Int, Error> { continuation in
            continuation.yield(1)
            continuation.finish(throwing: ClaudeSDKError.timeout(operation: "test", duration: 1.0))
        }
        
        var values: [Int] = []
        do {
            for try await value in stream {
                values.append(value)
            }
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(values, [1])
        }
    }
    
    // MARK: - Message Filtering Tests
    
    func testFilterMessagesForResults() async throws {
        let messages: [Message] = [
            .user(UserMessage(content: .text("Hello"))),
            .assistant(AssistantMessage(content: [.text(TextBlock(text: "Hi!"))], model: "claude")),
            .result(ResultMessage(
                subtype: .done,
                durationMs: 1000,
                durationApiMs: 800,
                isError: false,
                numTurns: 1,
                sessionId: "test",
                totalCostUSD: 0.01,
                usage: nil
            ))
        ]
        
        let resultMessages = messages.filter { message in
            if case .result = message { return true }
            return false
        }
        
        XCTAssertEqual(resultMessages.count, 1)
    }
    
    func testFilterMessagesForAssistant() async throws {
        let messages: [Message] = [
            .user(UserMessage(content: .text("Hello"))),
            .assistant(AssistantMessage(content: [.text(TextBlock(text: "Response 1"))], model: "claude")),
            .assistant(AssistantMessage(content: [.text(TextBlock(text: "Response 2"))], model: "claude")),
            .result(ResultMessage(
                subtype: .done,
                durationMs: 1000,
                durationApiMs: 800,
                isError: false,
                numTurns: 1,
                sessionId: "test",
                totalCostUSD: nil,
                usage: nil
            ))
        ]
        
        let assistantMessages = messages.compactMap { message -> AssistantMessage? in
            if case .assistant(let msg) = message { return msg }
            return nil
        }
        
        XCTAssertEqual(assistantMessages.count, 2)
        XCTAssertEqual(assistantMessages[0].textContent, "Response 1")
        XCTAssertEqual(assistantMessages[1].textContent, "Response 2")
    }
    
    // MARK: - Include Partial Messages Tests
    
    func testOptionsIncludePartialMessages() {
        let optionsWithPartial = ClaudeAgentOptions(includePartialMessages: true)
        let optionsWithoutPartial = ClaudeAgentOptions(includePartialMessages: false)
        
        XCTAssertTrue(optionsWithPartial.includePartialMessages)
        XCTAssertFalse(optionsWithoutPartial.includePartialMessages)
    }
    
    // MARK: - Stream Event Types Tests
    
    func testStreamEventTypes() {
        // Verify we can handle different event types
        let eventTypes = [
            "message_start",
            "content_block_start",
            "content_block_delta",
            "content_block_stop",
            "message_stop"
        ]
        
        for eventType in eventTypes {
            let event = StreamEvent(
                uuid: "test-\(eventType)",
                sessionId: "session",
                event: ["type": AnyCodable(eventType)],
                parentToolUseId: nil
            )
            
            XCTAssertEqual(event.event["type"]?.stringValue, eventType)
        }
    }
    
    // MARK: - Prompt Input Tests
    
    func testPromptInputText() {
        let input = PromptInput.text("Hello Claude!")
        
        if case .text(let text) = input {
            XCTAssertEqual(text, "Hello Claude!")
        } else {
            XCTFail("Expected text input")
        }
    }
    
    func testPromptInputStream() async {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        let input = PromptInput.stream(stream)
        
        continuation.yield("Hello")
        continuation.yield(" World")
        continuation.finish()
        
        if case .stream(let asyncStream) = input {
            var collected = ""
            for await chunk in asyncStream {
                collected += chunk
            }
            XCTAssertEqual(collected, "Hello World")
        } else {
            XCTFail("Expected stream input")
        }
    }
}
