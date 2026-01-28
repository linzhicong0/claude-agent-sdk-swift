// MARK: - Types Tests

import XCTest

@testable import ClaudeAgentSDK

final class TypesTests: XCTestCase {

    // MARK: - Permission Mode Tests

    func testPermissionModeRawValues() {
        XCTAssertEqual(PermissionMode.default.rawValue, "default")
        XCTAssertEqual(PermissionMode.acceptEdits.rawValue, "acceptEdits")
        XCTAssertEqual(PermissionMode.plan.rawValue, "plan")
        XCTAssertEqual(PermissionMode.bypassPermissions.rawValue, "bypassPermissions")
    }

    func testPermissionModeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let mode = PermissionMode.acceptEdits
        let data = try encoder.encode(mode)
        let decoded = try decoder.decode(PermissionMode.self, from: data)

        XCTAssertEqual(decoded, mode)
    }

    // MARK: - Hook Event Tests

    func testHookEventRawValues() {
        XCTAssertEqual(HookEvent.preToolUse.rawValue, "PreToolUse")
        XCTAssertEqual(HookEvent.postToolUse.rawValue, "PostToolUse")
        XCTAssertEqual(HookEvent.userPromptSubmit.rawValue, "UserPromptSubmit")
        XCTAssertEqual(HookEvent.stop.rawValue, "Stop")
        XCTAssertEqual(HookEvent.subagentStop.rawValue, "SubagentStop")
        XCTAssertEqual(HookEvent.preCompact.rawValue, "PreCompact")
    }

    func testHookEventCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for event in [
            HookEvent.preToolUse, .postToolUse, .userPromptSubmit, .stop, .subagentStop,
            .preCompact,
        ] {
            let data = try encoder.encode(event)
            let decoded = try decoder.decode(HookEvent.self, from: data)
            XCTAssertEqual(decoded, event)
        }
    }

    // MARK: - SDK Beta Tests

    func testSdkBetaRawValues() {
        XCTAssertEqual(SdkBeta.interleaved_thinking.rawValue, "interleaved_thinking")
        XCTAssertEqual(SdkBeta.output_schema.rawValue, "output_schema")
        XCTAssertEqual(SdkBeta.context_1m_2025_08_07.rawValue, "context-1m-2025-08-07")
    }

    func testSdkBetaCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for beta in [SdkBeta.interleaved_thinking, .output_schema, .context_1m_2025_08_07] {
            let data = try encoder.encode(beta)
            let decoded = try decoder.decode(SdkBeta.self, from: data)
            XCTAssertEqual(decoded, beta)
        }
    }

    // MARK: - Result Subtype Tests

    func testResultSubtypeRawValues() {
        XCTAssertEqual(ResultSubtype.done.rawValue, "done")
        XCTAssertEqual(ResultSubtype.error.rawValue, "error")
        XCTAssertEqual(ResultSubtype.interrupted.rawValue, "interrupted")
    }

    // MARK: - Agent Definition Tests

    func testAgentDefinitionBasic() {
        let agent = AgentDefinition(
            model: "claude-sonnet-4-20250514",
            systemPrompt: "You are a helpful assistant"
        )

        XCTAssertEqual(agent.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(agent.systemPrompt, "You are a helpful assistant")
        XCTAssertNil(agent.tools)
        XCTAssertNil(agent.maxTurns)
    }

    func testAgentDefinitionFull() {
        let agent = AgentDefinition(
            model: "claude-opus-4-20250514",
            systemPrompt: "Expert coder",
            tools: ["Read", "Write", "Bash"],
            allowedTools: ["Read"],
            disallowedTools: ["WebSearch"],
            maxTurns: 10
        )

        XCTAssertEqual(agent.model, "claude-opus-4-20250514")
        XCTAssertEqual(agent.tools, ["Read", "Write", "Bash"])
        XCTAssertEqual(agent.allowedTools, ["Read"])
        XCTAssertEqual(agent.disallowedTools, ["WebSearch"])
        XCTAssertEqual(agent.maxTurns, 10)
    }

    func testAgentDefinitionCodable() throws {
        // AgentDefinition has custom CodingKeys with snake_case already defined,
        // so we don't need automatic conversion strategies
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let agent = AgentDefinition(
            model: "claude-sonnet-4-20250514",
            systemPrompt: "Test prompt",
            maxTurns: 5
        )

        let data = try encoder.encode(agent)
        let decoded = try decoder.decode(AgentDefinition.self, from: data)

        XCTAssertEqual(decoded.model, agent.model)
        XCTAssertEqual(decoded.systemPrompt, agent.systemPrompt)
        XCTAssertEqual(decoded.maxTurns, agent.maxTurns)
    }

    // MARK: - Sandbox Settings Tests

    func testSandboxSettingsDocker() {
        let sandbox = SandboxSettings(type: .docker, options: nil)

        XCTAssertEqual(sandbox.type, .docker)
        XCTAssertNil(sandbox.options)
    }

    func testSandboxSettingsNone() {
        let sandbox = SandboxSettings(type: .none, options: nil)

        XCTAssertEqual(sandbox.type, .none)
    }

    func testSandboxSettingsWithOptions() {
        let sandbox = SandboxSettings(
            type: .docker,
            options: ["container": AnyCodable("my-container")]
        )

        XCTAssertEqual(sandbox.options?["container"]?.stringValue, "my-container")
    }

    // MARK: - Tools Config Tests

    func testToolsConfigPreset() {
        let config = ToolsConfig.preset(.default)

        if case .preset(let preset) = config {
            XCTAssertEqual(preset, .default)
        } else {
            XCTFail("Expected preset config")
        }
    }

    func testToolsConfigList() {
        let config = ToolsConfig.list(["Read", "Write", "Bash"])

        if case .list(let tools) = config {
            XCTAssertEqual(tools, ["Read", "Write", "Bash"])
        } else {
            XCTFail("Expected list config")
        }
    }

    // MARK: - System Prompt Config Tests

    func testSystemPromptConfigPreset() {
        let config = SystemPromptConfig.preset(.default)

        if case .preset(let preset) = config {
            XCTAssertEqual(preset, .default)
        } else {
            XCTFail("Expected preset config")
        }
    }

    func testSystemPromptConfigCustom() {
        let config = SystemPromptConfig.custom("You are a specialized assistant")

        if case .custom(let prompt) = config {
            XCTAssertEqual(prompt, "You are a specialized assistant")
        } else {
            XCTFail("Expected custom config")
        }
    }

    // MARK: - Message Type Tests

    func testMessageTypeUser() {
        let userMsg = UserMessage(content: .text("Hello"))
        let message = Message.user(userMsg)

        if case .user(let msg) = message {
            XCTAssertEqual(msg.content.text, "Hello")
        } else {
            XCTFail("Expected user message")
        }
    }

    func testMessageTypeAssistant() {
        let assistantMsg = AssistantMessage(
            content: [.text(TextBlock(text: "Response"))],
            model: "claude"
        )
        let message = Message.assistant(assistantMsg)

        if case .assistant(let msg) = message {
            XCTAssertEqual(msg.textContent, "Response")
        } else {
            XCTFail("Expected assistant message")
        }
    }

    func testMessageTypeResult() {
        let resultMsg = ResultMessage(
            subtype: .done,
            durationMs: 1000,
            durationApiMs: 800,
            isError: false,
            numTurns: 1,
            sessionId: "session",
            totalCostUSD: 0.01,
            usage: nil
        )
        let message = Message.result(resultMsg)

        if case .result(let msg) = message {
            XCTAssertEqual(msg.subtype, .done)
        } else {
            XCTFail("Expected result message")
        }
    }

    // MARK: - User Content Tests

    func testUserContentText() {
        let content = UserContent.text("Simple text")

        XCTAssertEqual(content.text, "Simple text")
    }

    func testUserContentBlocks() {
        let blocks: [ContentBlock] = [
            .text(TextBlock(text: "Block 1")),
            .text(TextBlock(text: "Block 2")),
        ]
        let content = UserContent.blocks(blocks)

        if case .blocks(let b) = content {
            XCTAssertEqual(b.count, 2)
        } else {
            XCTFail("Expected blocks content")
        }

        // Text should concatenate blocks
        XCTAssertEqual(content.text, "Block 1Block 2")
    }

    // MARK: - Assistant Message Helper Tests

    func testAssistantMessageTextContent() {
        let message = AssistantMessage(
            content: [
                .text(TextBlock(text: "Part 1 ")),
                .thinking(ThinkingBlock(thinking: "thinking...", signature: "sig")),
                .text(TextBlock(text: "Part 2")),
            ],
            model: "claude"
        )

        XCTAssertEqual(message.textContent, "Part 1 Part 2")
    }

    func testAssistantMessageToolUses() {
        let message = AssistantMessage(
            content: [
                .text(TextBlock(text: "Let me help")),
                .toolUse(ToolUseBlock(id: "1", name: "Read", input: [:])),
                .toolUse(ToolUseBlock(id: "2", name: "Write", input: [:])),
            ],
            model: "claude"
        )

        XCTAssertEqual(message.toolUses.count, 2)
        XCTAssertEqual(message.toolUses[0].name, "Read")
        XCTAssertEqual(message.toolUses[1].name, "Write")
    }

    // MARK: - Error Type Tests

    func testAssistantMessageErrorTypes() {
        let errorTypes = [
            "authentication_failed",
            "billing_error",
            "rate_limit",
            "invalid_request",
            "server_error",
            "unknown",
        ]

        for errorType in errorTypes {
            let error = AssistantMessageError(type: errorType, message: "Test")
            XCTAssertEqual(error.type, errorType)
        }
    }
}
