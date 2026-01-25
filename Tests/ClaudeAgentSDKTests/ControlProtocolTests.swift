// MARK: - Control Protocol Tests

import XCTest
@testable import ClaudeAgentSDK

final class ControlProtocolTests: XCTestCase {
    
    // MARK: - Hook Input Tests
    
    func testHookInputConstruction() {
        let input = HookInput(
            hookEventName: .preToolUse,
            toolName: "Bash",
            toolInput: ["command": AnyCodable("ls -la")],
            toolOutput: nil,
            prompt: nil,
            stopReason: nil
        )
        
        XCTAssertEqual(input.hookEventName, .preToolUse)
        XCTAssertEqual(input.toolName, "Bash")
        XCTAssertEqual(input.toolInput?["command"]?.stringValue, "ls -la")
    }
    
    func testHookInputPostToolUse() {
        let input = HookInput(
            hookEventName: .postToolUse,
            toolName: "Read",
            toolInput: ["file_path": AnyCodable("/tmp/test.txt")],
            toolOutput: AnyCodable("File contents here"),
            prompt: nil,
            stopReason: nil
        )
        
        XCTAssertEqual(input.hookEventName, .postToolUse)
        XCTAssertEqual(input.toolOutput?.stringValue, "File contents here")
    }
    
    func testHookInputUserPromptSubmit() {
        let input = HookInput(
            hookEventName: .userPromptSubmit,
            toolName: nil,
            toolInput: nil,
            toolOutput: nil,
            prompt: "Hello Claude!",
            stopReason: nil
        )
        
        XCTAssertEqual(input.hookEventName, .userPromptSubmit)
        XCTAssertEqual(input.prompt, "Hello Claude!")
    }
    
    func testHookInputStop() {
        let input = HookInput(
            hookEventName: .stop,
            toolName: nil,
            toolInput: nil,
            toolOutput: nil,
            prompt: nil,
            stopReason: "end_turn"
        )
        
        XCTAssertEqual(input.hookEventName, .stop)
        XCTAssertEqual(input.stopReason, "end_turn")
    }
    
    // MARK: - Hook Context Tests
    
    func testHookContextConstruction() {
        let abortController = AbortController()
        let context = HookContext(sessionId: "session-123", abortController: abortController)
        
        XCTAssertEqual(context.sessionId, "session-123")
        XCTAssertNotNil(context.abortController)
        XCTAssertFalse(context.abortController?.isAborted ?? true)
    }
    
    func testAbortController() {
        let abortController = AbortController()
        
        XCTAssertFalse(abortController.isAborted)
        
        abortController.abort()
        
        XCTAssertTrue(abortController.isAborted)
    }
    
    // MARK: - Hook Output Tests
    
    func testHookOutputContinue() {
        let output = HookOutput(shouldContinue: true)
        
        XCTAssertTrue(output.shouldContinue)
        XCTAssertFalse(output.suppressOutput)
    }
    
    func testHookOutputBlock() {
        let output = HookOutput(
            shouldContinue: false,
            decision: .block,
            reason: "Tool not allowed"
        )
        
        XCTAssertFalse(output.shouldContinue)
        XCTAssertEqual(output.decision, .block)
        XCTAssertEqual(output.reason, "Tool not allowed")
    }
    
    func testHookOutputSuppressOutput() {
        let output = HookOutput(
            shouldContinue: true,
            suppressOutput: true
        )
        
        XCTAssertTrue(output.shouldContinue)
        XCTAssertTrue(output.suppressOutput)
    }
    
    func testHookOutputWithSpecific() {
        let specificOutput = HookSpecificOutput(
            hookEventName: .preToolUse,
            permissionDecision: "allow",
            permissionDecisionReason: "Safe operation"
        )
        
        let output = HookOutput(
            shouldContinue: true,
            hookSpecificOutput: specificOutput
        )
        
        XCTAssertEqual(output.hookSpecificOutput?.permissionDecision, "allow")
        XCTAssertEqual(output.hookSpecificOutput?.permissionDecisionReason, "Safe operation")
    }
    
    // MARK: - Hook Matcher Tests
    
    func testHookMatcherWithPattern() {
        let matcher = HookMatcher(
            matcher: "Bash|Write",
            hooks: [
                { _, _, _ in HookOutput(shouldContinue: true) }
            ],
            timeout: 30.0
        )
        
        XCTAssertEqual(matcher.matcher, "Bash|Write")
        XCTAssertEqual(matcher.hooks.count, 1)
        XCTAssertEqual(matcher.timeout, 30.0)
    }
    
    func testHookMatcherWithoutPattern() {
        let matcher = HookMatcher(
            hooks: [
                { _, _, _ in HookOutput(shouldContinue: true) },
                { _, _, _ in HookOutput(shouldContinue: false, decision: .block) }
            ]
        )
        
        XCTAssertNil(matcher.matcher)
        XCTAssertEqual(matcher.hooks.count, 2)
        XCTAssertNil(matcher.timeout)
    }
    
    // MARK: - Hook Event Tests
    
    func testAllHookEventTypes() {
        let events: [HookEvent] = [
            .preToolUse,
            .postToolUse,
            .userPromptSubmit,
            .stop,
            .subagentStop,
            .preCompact
        ]
        
        XCTAssertEqual(events.count, 6)
        
        // Verify raw values
        XCTAssertEqual(HookEvent.preToolUse.rawValue, "PreToolUse")
        XCTAssertEqual(HookEvent.postToolUse.rawValue, "PostToolUse")
        XCTAssertEqual(HookEvent.userPromptSubmit.rawValue, "UserPromptSubmit")
        XCTAssertEqual(HookEvent.stop.rawValue, "Stop")
        XCTAssertEqual(HookEvent.subagentStop.rawValue, "SubagentStop")
        XCTAssertEqual(HookEvent.preCompact.rawValue, "PreCompact")
    }
    
    // MARK: - Permission Context Tests
    
    func testToolPermissionContext() {
        let context = ToolPermissionContext(
            sessionId: "session-456",
            abortController: AbortController(),
            readFileTimestamps: ["/tmp/test.txt": Date()]
        )
        
        XCTAssertEqual(context.sessionId, "session-456")
        XCTAssertNotNil(context.abortController)
        XCTAssertEqual(context.readFileTimestamps?.count, 1)
    }
    
    // MARK: - Permission Result Tests
    
    func testPermissionResultAllowWithUpdatedInput() {
        let result = PermissionResult.allowTool(
            updatedInput: ["sanitized_command": "ls"],
            updatedPermissions: [PermissionUpdate(toolName: "Bash", permission: "allow")]
        )
        
        if case .allow(let input, let permissions) = result {
            XCTAssertEqual(input?["sanitized_command"] as? String, "ls")
            XCTAssertEqual(permissions?.count, 1)
            XCTAssertEqual(permissions?[0].toolName, "Bash")
        } else {
            XCTFail("Expected allow result")
        }
    }
    
    func testPermissionResultDenyWithInterrupt() {
        let result = PermissionResult.denyTool(
            message: "Dangerous operation not allowed",
            interrupt: true
        )
        
        if case .deny(let message, let interrupt) = result {
            XCTAssertEqual(message, "Dangerous operation not allowed")
            XCTAssertTrue(interrupt)
        } else {
            XCTFail("Expected deny result")
        }
    }
    
    // MARK: - Permission Update Tests
    
    func testPermissionUpdate() {
        let update = PermissionUpdate(toolName: "Write", permission: "ask")
        
        XCTAssertEqual(update.toolName, "Write")
        XCTAssertEqual(update.permission, "ask")
    }
}
