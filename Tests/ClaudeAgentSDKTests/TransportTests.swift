// MARK: - Transport Tests

import XCTest

@testable import ClaudeAgentSDK

final class TransportTests: XCTestCase {

    // MARK: - Command Building Tests

    func testBuildArgumentsWithBasicOptions() async throws {
        let options = ClaudeAgentOptions(
            maxTurns: 5,
            model: "claude-sonnet-4-20250514"
        )

        let transport = SubprocessCLITransport(
            prompt: .text("Hello"),
            options: options,
            isStreamingMode: false
        )

        // Verify transport was created (actual command building is internal)
        let isRunning = await transport.isRunning
        XCTAssertFalse(isRunning)
    }

    func testBuildArgumentsWithAllowedTools() async throws {
        let options = ClaudeAgentOptions(
            allowedTools: ["Read", "Write", "Bash"],
            disallowedTools: ["WebSearch"]
        )

        let transport = SubprocessCLITransport(
            prompt: .text("Test"),
            options: options,
            isStreamingMode: false
        )

        let isRunning = await transport.isRunning
        XCTAssertFalse(isRunning)
    }

    func testBuildArgumentsWithPermissionMode() async throws {
        let options = ClaudeAgentOptions(
            permissionMode: .acceptEdits
        )

        let transport = SubprocessCLITransport(
            prompt: .text("Test"),
            options: options,
            isStreamingMode: false
        )

        let isRunning = await transport.isRunning
        XCTAssertFalse(isRunning)
    }

    func testBuildArgumentsWithSessionOptions() async throws {
        let options = ClaudeAgentOptions(
            continueConversation: true,
            resume: "session-123",
            forkSession: true
        )

        let transport = SubprocessCLITransport(
            prompt: .text("Test"),
            options: options,
            isStreamingMode: false
        )

        let isRunning = await transport.isRunning
        XCTAssertFalse(isRunning)
    }

    func testBuildArgumentsWithMCPServers() async throws {
        let options = ClaudeAgentOptions(
            mcpServers: [
                "calculator": .external(
                    ExternalMCPServerConfig(
                        command: "npx",
                        args: ["-y", "@anthropic/mcp-calculator"]
                    ))
            ]
        )

        let transport = SubprocessCLITransport(
            prompt: .text("Test"),
            options: options,
            isStreamingMode: false
        )

        let isRunning = await transport.isRunning
        XCTAssertFalse(isRunning)
    }

    func testBuildArgumentsWithHTTPMCPServers() async throws {
        let options = ClaudeAgentOptions(
            mcpServers: [
                "notion": .http(url: "https://mcp.notion.com/mcp"),
                "api": .http(
                    url: "https://api.example.com/mcp",
                    headers: ["Authorization": "Bearer token123"]
                ),
            ]
        )

        let transport = SubprocessCLITransport(
            prompt: .text("Test"),
            options: options,
            isStreamingMode: false
        )

        let isRunning = await transport.isRunning
        XCTAssertFalse(isRunning)
    }

    func testBuildArgumentsWithMixedMCPServers() async throws {
        let options = ClaudeAgentOptions(
            mcpServers: [
                "filesystem": .stdio(
                    command: "npx",
                    args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
                ),
                "notion": .http(url: "https://mcp.notion.com/mcp"),
                "legacy": .sse(
                    url: "https://mcp.asana.com/sse",
                    headers: ["X-API-Key": "key123"]
                ),
            ]
        )

        let transport = SubprocessCLITransport(
            prompt: .text("Test"),
            options: options,
            isStreamingMode: false
        )

        let isRunning = await transport.isRunning
        XCTAssertFalse(isRunning)
    }

    func testStrictMCPConfigOption() async throws {
        let options = ClaudeAgentOptions(
            mcpServers: [
                "api": .http(url: "https://api.example.com/mcp")
            ],
            strictMcpConfig: true
        )

        let transport = SubprocessCLITransport(
            prompt: .text("Test"),
            options: options,
            isStreamingMode: false
        )

        let isRunning = await transport.isRunning
        XCTAssertFalse(isRunning)
    }

    func testStreamingModeConfiguration() async throws {
        let options = ClaudeAgentOptions()

        let transport = SubprocessCLITransport(
            prompt: nil,
            options: options,
            isStreamingMode: true
        )

        let isRunning = await transport.isRunning
        XCTAssertFalse(isRunning)
    }

    // MARK: - Process Management Tests

    func testCloseWithoutConnect() async throws {
        let transport = SubprocessCLITransport(
            prompt: .text("Test"),
            options: ClaudeAgentOptions(),
            isStreamingMode: false
        )

        // Should not crash when closing without connecting
        await transport.close()

        let isRunning = await transport.isRunning
        XCTAssertFalse(isRunning)
    }

    func testWriteWithoutConnection() async {
        let transport = SubprocessCLITransport(
            prompt: .text("Test"),
            options: ClaudeAgentOptions(),
            isStreamingMode: true
        )

        do {
            try await transport.write("test message")
            XCTFail("Expected write error")
        } catch let error as ClaudeSDKError {
            if case .writeError = error {
                // Expected
            } else {
                XCTFail("Expected writeError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Buffer Handling Tests

    func testMaxBufferSizeConfiguration() async throws {
        let options = ClaudeAgentOptions(
            maxBufferSize: 1024
        )

        let transport = SubprocessCLITransport(
            prompt: .text("Test"),
            options: options,
            isStreamingMode: false
        )

        let isRunning = await transport.isRunning
        XCTAssertFalse(isRunning)
    }

    // MARK: - Environment Configuration Tests

    func testEnvironmentVariables() async throws {
        let options = ClaudeAgentOptions(
            cwd: "/tmp",
            env: ["CUSTOM_VAR": "test_value"]
        )

        let transport = SubprocessCLITransport(
            prompt: .text("Test"),
            options: options,
            isStreamingMode: false
        )

        let isRunning = await transport.isRunning
        XCTAssertFalse(isRunning)
    }

    func testCustomCLIPath() async throws {
        let options = ClaudeAgentOptions(
            cliPath: "/custom/path/to/claude"
        )

        let transport = SubprocessCLITransport(
            prompt: .text("Test"),
            options: options,
            isStreamingMode: false
        )

        let isRunning = await transport.isRunning
        XCTAssertFalse(isRunning)
    }
}
