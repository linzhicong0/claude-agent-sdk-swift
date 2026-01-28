// MARK: - MCP Server Tests

import XCTest

@testable import ClaudeAgentSDK

final class MCPServerTests: XCTestCase {

    // MARK: - Server Creation Tests

    func testServerCreation() {
        let server = SDKMCPServer(name: "test-server", version: "1.0.0")

        XCTAssertEqual(server.name, "test-server")
        XCTAssertEqual(server.version, "1.0.0")
        XCTAssertTrue(server.tools.isEmpty)
    }

    func testServerWithTools() {
        let tool = mcpTool(
            name: "greet",
            description: "Greet someone",
            parameters: ["name": .string(description: "Name to greet")],
            required: ["name"]
        ) { args in
            let name = args["name"] as? String ?? "World"
            return .text("Hello, \(name)!")
        }

        let server = SDKMCPServer(name: "greeter", version: "1.0.0", tools: [tool])

        XCTAssertEqual(server.tools.count, 1)
        XCTAssertEqual(server.tools[0].name, "greet")
    }

    func testAddTool() {
        let server = SDKMCPServer(name: "test", version: "1.0.0")

        let tool = mcpTool(
            name: "add",
            description: "Add numbers",
            parameters: [:],
            required: []
        ) { _ in .text("0") }

        server.addTool(tool)

        XCTAssertEqual(server.tools.count, 1)
    }

    // MARK: - Initialize Handler Tests

    func testHandleInitialize() async throws {
        let server = SDKMCPServer(name: "test", version: "2.0.0")

        let response = try await server.handleMessage([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
        ])

        let result = response["result"] as? [String: Any]
        XCTAssertNotNil(result)

        let serverInfo = result?["serverInfo"] as? [String: Any]
        XCTAssertEqual(serverInfo?["name"] as? String, "test")
        XCTAssertEqual(serverInfo?["version"] as? String, "2.0.0")

        let protocolVersion = result?["protocolVersion"] as? String
        XCTAssertEqual(protocolVersion, "2024-11-05")
    }

    // MARK: - Tools List Handler Tests

    func testHandleToolsList() async throws {
        let server = SDKMCPServer(
            name: "calc", version: "1.0.0",
            tools: [
                mcpTool(
                    name: "add", description: "Add two numbers",
                    parameters: [
                        "a": .number(description: "First number"),
                        "b": .number(description: "Second number"),
                    ], required: ["a", "b"]
                ) { args in
                    let a = args["a"] as? Double ?? 0
                    let b = args["b"] as? Double ?? 0
                    return .text("\(a + b)")
                },
                mcpTool(
                    name: "multiply", description: "Multiply two numbers",
                    parameters: [
                        "a": .number(description: "First number"),
                        "b": .number(description: "Second number"),
                    ], required: ["a", "b"]
                ) { args in
                    let a = args["a"] as? Double ?? 0
                    let b = args["b"] as? Double ?? 0
                    return .text("\(a * b)")
                },
            ])

        let response = try await server.handleMessage([
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
        ])

        let result = response["result"] as? [String: Any]
        let tools = result?["tools"] as? [[String: Any]]

        XCTAssertEqual(tools?.count, 2)

        let toolNames = tools?.compactMap { $0["name"] as? String }
        XCTAssertTrue(toolNames?.contains("add") ?? false)
        XCTAssertTrue(toolNames?.contains("multiply") ?? false)
    }

    func testHandleToolsListEmpty() async throws {
        let server = SDKMCPServer(name: "empty", version: "1.0.0")

        let response = try await server.handleMessage([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/list",
        ])

        let result = response["result"] as? [String: Any]
        let tools = result?["tools"] as? [[String: Any]]

        XCTAssertEqual(tools?.count, 0)
    }

    // MARK: - Tools Call Handler Tests

    func testHandleToolCallSuccess() async throws {
        let server = SDKMCPServer(
            name: "calc", version: "1.0.0",
            tools: [
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
                "arguments": ["a": 10.0, "b": 5.0],
            ],
        ])

        let result = response["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]
        let isError = result?["isError"] as? Bool

        XCTAssertEqual(content?[0]["text"] as? String, "Result: 15.0")
        XCTAssertEqual(isError, false)
    }

    func testHandleToolCallNotFound() async throws {
        let server = SDKMCPServer(name: "test", version: "1.0.0")

        let response = try await server.handleMessage([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": [
                "name": "nonexistent",
                "arguments": [:],
            ],
        ])

        let error = response["error"] as? [String: Any]
        XCTAssertNotNil(error)
        XCTAssertEqual(error?["code"] as? Int, -32602)
        XCTAssertTrue((error?["message"] as? String)?.contains("not found") ?? false)
    }

    func testHandleToolCallMissingParams() async throws {
        let server = SDKMCPServer(
            name: "test", version: "1.0.0",
            tools: [
                mcpTool(name: "test", description: "Test", parameters: [:], required: []) { _ in
                    .text("ok")
                }
            ])

        let response = try await server.handleMessage([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
                // Missing params
        ])

        let error = response["error"] as? [String: Any]
        XCTAssertNotNil(error)
    }

    func testHandleToolCallWithError() async throws {
        let server = SDKMCPServer(
            name: "test", version: "1.0.0",
            tools: [
                mcpTool(name: "failing", description: "Always fails", parameters: [:], required: [])
                { _ in
                    throw NSError(
                        domain: "test", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Tool failed"])
                }
            ])

        let response = try await server.handleMessage([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": [
                "name": "failing",
                "arguments": [:],
            ],
        ])

        let error = response["error"] as? [String: Any]
        XCTAssertNotNil(error)
        XCTAssertEqual(error?["code"] as? Int, -32000)
    }

    // MARK: - Notification Handler Tests

    func testHandleInitializedNotification() async throws {
        let server = SDKMCPServer(name: "test", version: "1.0.0")

        let response = try await server.handleMessage([
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
        ])

        // Notifications don't require a response
        XCTAssertTrue(response.isEmpty)
    }

    // MARK: - Unknown Method Tests

    func testHandleUnknownMethod() async throws {
        let server = SDKMCPServer(name: "test", version: "1.0.0")

        let response = try await server.handleMessage([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "unknown/method",
        ])

        let error = response["error"] as? [String: Any]
        XCTAssertNotNil(error)
        XCTAssertEqual(error?["code"] as? Int, -32601)
        XCTAssertTrue((error?["message"] as? String)?.contains("Method not found") ?? false)
    }

    // MARK: - Tool Result Content Types Tests

    func testToolResultText() async throws {
        let server = SDKMCPServer(
            name: "test", version: "1.0.0",
            tools: [
                mcpTool(name: "text", description: "Return text", parameters: [:], required: []) {
                    _ in
                    .text("Plain text result")
                }
            ])

        let response = try await server.handleMessage([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": ["name": "text", "arguments": [:]],
        ])

        let result = response["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]

        XCTAssertEqual(content?[0]["type"] as? String, "text")
        XCTAssertEqual(content?[0]["text"] as? String, "Plain text result")
    }

    func testToolResultMultipleContent() async throws {
        let server = SDKMCPServer(
            name: "test", version: "1.0.0",
            tools: [
                mcpTool(
                    name: "multi", description: "Return multiple", parameters: [:], required: []
                ) { _ in
                    MCPToolResult(
                        content: [
                            .text("First line"),
                            .text("Second line"),
                        ], isError: false)
                }
            ])

        let response = try await server.handleMessage([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": ["name": "multi", "arguments": [:]],
        ])

        let result = response["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]

        XCTAssertEqual(content?.count, 2)
    }

    func testToolResultError() async throws {
        let server = SDKMCPServer(
            name: "test", version: "1.0.0",
            tools: [
                mcpTool(name: "error", description: "Return error", parameters: [:], required: []) {
                    _ in
                    MCPToolResult(content: [.text("Error message")], isError: true)
                }
            ])

        let response = try await server.handleMessage([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": ["name": "error", "arguments": [:]],
        ])

        let result = response["result"] as? [String: Any]
        let isError = result?["isError"] as? Bool

        XCTAssertEqual(isError, true)
    }

    // MARK: - MCP Tool Builder Tests

    func testMCPToolBuilderAllParameterTypes() {
        let tool = mcpTool(
            name: "comprehensive",
            description: "Test all types",
            parameters: [
                "text": .string(description: "A string"),
                "count": .number(description: "A number"),
                "flag": .boolean(description: "A boolean"),
                "items": .array(items: .string(description: "Item"), description: "An array"),
                "data": .object(
                    properties: [
                        "nested": .string(description: "Nested string")
                    ], description: "An object"),
            ],
            required: ["text", "count"]
        ) { _ in .text("ok") }

        XCTAssertEqual(tool.name, "comprehensive")

        let schema = tool.inputSchema
        let properties = schema["properties"] as? [String: Any]

        let textType: String? = (properties?["text"] as? [String: Any])?["type"] as? String
        let countType: String? = (properties?["count"] as? [String: Any])?["type"] as? String
        let flagType: String? = (properties?["flag"] as? [String: Any])?["type"] as? String
        let itemsType: String? = (properties?["items"] as? [String: Any])?["type"] as? String
        let dataType: String? = (properties?["data"] as? [String: Any])?["type"] as? String

        XCTAssertEqual(textType, "string")
        XCTAssertEqual(countType, "number")
        XCTAssertEqual(flagType, "boolean")
        XCTAssertEqual(itemsType, "array")
        XCTAssertEqual(dataType, "object")
    }

    // MARK: - Configuration Tests

    func testExternalMCPServerConfig() {
        let config = ExternalMCPServerConfig(
            command: "npx",
            args: ["-y", "@anthropic/mcp-server"],
            env: ["NODE_ENV": "production"],
            cwd: "/tmp"
        )

        XCTAssertEqual(config.type, .stdio)
        XCTAssertEqual(config.command, "npx")
        XCTAssertEqual(config.args, ["-y", "@anthropic/mcp-server"])
        XCTAssertEqual(config.env?["NODE_ENV"], "production")
        XCTAssertEqual(config.cwd, "/tmp")
        XCTAssertNil(config.url)
        XCTAssertNil(config.headers)
    }

    func testMCPServerConfigVariants() {
        let externalConfig: MCPServerConfig = .external(ExternalMCPServerConfig(command: "test"))
        let sdkConfig: MCPServerConfig = .sdkServer(SDKMCPServer(name: "sdk", version: "1.0.0"))

        if case .external(let config) = externalConfig {
            XCTAssertEqual(config.command, "test")
        } else {
            XCTFail("Expected external config")
        }

        if case .sdkServer(let server) = sdkConfig {
            XCTAssertEqual(server.name, "sdk")
        } else {
            XCTFail("Expected SDK server")
        }
    }

    // MARK: - HTTP Transport Tests

    func testHTTPMCPServerConfig() {
        let config = ExternalMCPServerConfig(
            type: .http,
            url: "https://mcp.notion.com/mcp",
            headers: ["Authorization": "Bearer token123"]
        )

        XCTAssertEqual(config.type, .http)
        XCTAssertEqual(config.url, "https://mcp.notion.com/mcp")
        XCTAssertEqual(config.headers?["Authorization"], "Bearer token123")
        XCTAssertNil(config.command)
        XCTAssertNil(config.args)
        XCTAssertNil(config.env)
        XCTAssertNil(config.cwd)
    }

    func testSSEMCPServerConfig() {
        let config = ExternalMCPServerConfig(
            type: .sse,
            url: "https://api.example.com/sse",
            headers: nil
        )

        XCTAssertEqual(config.type, .sse)
        XCTAssertEqual(config.url, "https://api.example.com/sse")
        XCTAssertNil(config.headers)
    }

    // MARK: - Factory Method Tests

    func testStdioFactoryMethod() {
        let config = MCPServerConfig.stdio(
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
            env: ["DEBUG": "true"],
            cwd: "/home/user"
        )

        if case .external(let external) = config {
            XCTAssertEqual(external.type, .stdio)
            XCTAssertEqual(external.command, "npx")
            XCTAssertEqual(
                external.args, ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"])
            XCTAssertEqual(external.env?["DEBUG"], "true")
            XCTAssertEqual(external.cwd, "/home/user")
        } else {
            XCTFail("Expected external config")
        }
    }

    func testHTTPFactoryMethod() {
        let config = MCPServerConfig.http(
            url: "https://mcp.notion.com/mcp",
            headers: ["X-API-Key": "secret"]
        )

        if case .external(let external) = config {
            XCTAssertEqual(external.type, .http)
            XCTAssertEqual(external.url, "https://mcp.notion.com/mcp")
            XCTAssertEqual(external.headers?["X-API-Key"], "secret")
        } else {
            XCTFail("Expected external config")
        }
    }

    func testHTTPFactoryMethodNoHeaders() {
        let config = MCPServerConfig.http(url: "https://api.example.com/mcp")

        if case .external(let external) = config {
            XCTAssertEqual(external.type, .http)
            XCTAssertEqual(external.url, "https://api.example.com/mcp")
            XCTAssertNil(external.headers)
        } else {
            XCTFail("Expected external config")
        }
    }

    func testSSEFactoryMethod() {
        let config = MCPServerConfig.sse(
            url: "https://mcp.asana.com/sse",
            headers: ["Authorization": "Bearer abc"]
        )

        if case .external(let external) = config {
            XCTAssertEqual(external.type, .sse)
            XCTAssertEqual(external.url, "https://mcp.asana.com/sse")
            XCTAssertEqual(external.headers?["Authorization"], "Bearer abc")
        } else {
            XCTFail("Expected external config")
        }
    }

    // MARK: - Transport Type Tests

    func testMCPTransportTypeRawValues() {
        XCTAssertEqual(MCPTransportType.stdio.rawValue, "stdio")
        XCTAssertEqual(MCPTransportType.http.rawValue, "http")
        XCTAssertEqual(MCPTransportType.sse.rawValue, "sse")
    }
}
