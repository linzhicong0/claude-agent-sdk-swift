// MARK: - Client Tests

import XCTest

@testable import ClaudeAgentSDK

final class ClientTests: XCTestCase {

    // MARK: - Initialization Tests

    func testClientInitialization() async {
        let options = ClaudeAgentOptions(
            maxTurns: 10,
            model: "claude-sonnet-4-20250514"
        )

        let client = ClaudeSDKClient(options: options)
        let connected = await client.connected

        XCTAssertFalse(connected)
    }

    func testClientDefaultOptions() async {
        let client = ClaudeSDKClient()
        let connected = await client.connected

        XCTAssertFalse(connected)
    }

    // MARK: - Connection State Tests

    func testQueryBeforeConnect() async {
        let client = ClaudeSDKClient()

        do {
            try await client.query(prompt: "Hello")
            XCTFail("Expected error when querying before connect")
        } catch let error as ClaudeSDKError {
            if case .configurationError(let reason) = error {
                XCTAssertTrue(reason.contains("Not connected"))
            } else {
                XCTFail("Expected configurationError")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInterruptBeforeConnect() async {
        let client = ClaudeSDKClient()

        do {
            try await client.interrupt()
            XCTFail("Expected error")
        } catch let error as ClaudeSDKError {
            if case .configurationError = error {
                // Expected
            } else {
                XCTFail("Expected configurationError")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSetModelBeforeConnect() async {
        let client = ClaudeSDKClient()

        do {
            try await client.setModel("claude-opus-4-20250514")
            XCTFail("Expected error")
        } catch let error as ClaudeSDKError {
            if case .configurationError = error {
                // Expected
            } else {
                XCTFail("Expected configurationError")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSetPermissionModeBeforeConnect() async {
        let client = ClaudeSDKClient()

        do {
            try await client.setPermissionMode(.bypassPermissions)
            XCTFail("Expected error")
        } catch let error as ClaudeSDKError {
            if case .configurationError = error {
                // Expected
            } else {
                XCTFail("Expected configurationError")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRewindFilesBeforeConnect() async {
        let client = ClaudeSDKClient()

        do {
            try await client.rewindFiles(to: "checkpoint-123")
            XCTFail("Expected error")
        } catch let error as ClaudeSDKError {
            if case .configurationError = error {
                // Expected
            } else {
                XCTFail("Expected configurationError")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Close Tests

    func testCloseWithoutConnect() async {
        let client = ClaudeSDKClient()

        // Should not crash
        await client.close()

        let connected = await client.connected
        XCTAssertFalse(connected)
    }

    func testMultipleClose() async {
        let client = ClaudeSDKClient()

        // Should handle multiple close calls gracefully
        await client.close()
        await client.close()
        await client.close()

        let connected = await client.connected
        XCTAssertFalse(connected)
    }

    // MARK: - Options Configuration Tests

    func testClientWithToolPermissionCallback() async {
        let options = ClaudeAgentOptions(
            canUseTool: { toolName, input, context in
                return .allowTool()
            }
        )

        let client = ClaudeSDKClient(options: options)
        let connected = await client.connected

        XCTAssertFalse(connected)
    }

    func testClientWithHooks() async {
        let options = ClaudeAgentOptions(
            hooks: [
                .preToolUse: [
                    HookMatcher(
                        matcher: "Bash",
                        hooks: [
                            { input, toolUseId, context in
                                HookOutput(shouldContinue: true)
                            }
                        ])
                ]
            ]
        )

        let client = ClaudeSDKClient(options: options)
        let connected = await client.connected

        XCTAssertFalse(connected)
    }

    func testClientWithMCPServers() async {
        let server = SDKMCPServer(
            name: "test", version: "1.0.0",
            tools: [
                mcpTool(name: "hello", description: "Say hello", parameters: [:], required: []) {
                    _ in
                    .text("Hello!")
                }
            ])

        let options = ClaudeAgentOptions(
            mcpServers: ["test": .sdkServer(server)]
        )

        let client = ClaudeSDKClient(options: options)
        let connected = await client.connected

        XCTAssertFalse(connected)
    }

    // MARK: - MCP Status Tests

    func testGetMcpStatusBeforeConnect() async {
        let client = ClaudeSDKClient()

        do {
            _ = try await client.getMcpStatus()
            XCTFail("Expected error")
        } catch let error as ClaudeSDKError {
            if case .configurationError = error {
                // Expected
            } else {
                XCTFail("Expected configurationError")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGetServerInfoBeforeConnect() async {
        let client = ClaudeSDKClient()
        let serverInfo = await client.getServerInfo()

        XCTAssertNil(serverInfo)
    }
}
