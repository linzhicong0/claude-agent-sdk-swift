// MARK: - Claude SDK Example

import ClaudeAgentSDK
import Foundation

@main
struct ClaudeSDKExample {
    static func main() async {
        print("Claude Agent SDK for Swift - Examples\n")
        print("=====================================\n")

        // Run examples based on command line arguments
        let args = CommandLine.arguments

        if args.count > 1 {
            switch args[1] {
            case "simple":
                await simpleQueryExample()
            case "streaming":
                await streamingClientExample()
            case "mcp":
                await mcpServerExample()
            case "external-mcp":
                await externalMCPExample()
            case "hooks":
                await hooksExample()
            case "permissions":
                await permissionsExample()
            default:
                printUsage()
            }
        } else {
            printUsage()
            print("\nRunning simple example...\n")
            await simpleQueryExample()
        }
    }

    static func printUsage() {
        print(
            """
            Usage: claude-sdk-example <example>

            Available examples:
              simple       - Simple one-shot query
              streaming    - Streaming client with multi-turn
              mcp          - SDK MCP server with custom tools (requires CLI support)
              external-mcp - External MCP servers (stdio and HTTP)
              hooks        - Lifecycle hooks
              permissions  - Tool permission callbacks
            """)
    }
}

// MARK: - Simple Query Example

func simpleQueryExample() async {
    print("📝 Simple Query Example")
    print("-----------------------\n")

    let options = ClaudeAgentOptions(
        cwd: FileManager.default.currentDirectoryPath,
        maxTurns: 1
    )

    do {
        for try await message in query(prompt: "What is 2 + 2? Reply briefly.", options: options) {
            switch message {
            case .assistant(let msg):
                print("Claude: \(msg.textContent)")

            case .result(let result):
                print("\n✅ Done!")
                print("   Turns: \(result.numTurns)")
                print("   Duration: \(result.durationMs)ms")
                if let cost = result.totalCostUSD {
                    print("   Cost: $\(String(format: "%.4f", cost))")
                }

            default:
                break
            }
        }
    } catch {
        print("❌ Error: \(error.localizedDescription)")
    }
}

// MARK: - Streaming Client Example

func streamingClientExample() async {
    print("🔄 Streaming Client Example")
    print("---------------------------\n")

    let options = ClaudeAgentOptions(
        cwd: FileManager.default.currentDirectoryPath,
        maxTurns: 3
    )

    let client = ClaudeSDKClient(options: options)

    do {
        print("Connecting...")
        try await client.connect()
        print("Connected!\n")

        // First turn
        print("You: What's the capital of France?")
        try await client.query(prompt: "What's the capital of France? Be brief.")

        for try await message in client.receiveUntilResult() {
            switch message {
            case .assistant(let msg):
                print("Claude: \(msg.textContent)")
            case .result(let result):
                print("[Turn 1 completed in \(result.numTurns) turn(s)]")
            default:
                continue
            }
        }

        // Second turn
        print("\nYou: What about Germany?")
        try await client.query(prompt: "What about Germany?")

        for try await message in client.receiveUntilResult() {
            switch message {
            case .assistant(let msg):
                print("Claude: \(msg.textContent)")
            case .result(let result):
                print("\n✅ Conversation done!")
                print("   Total turns: \(result.numTurns)")
            default:
                continue
            }
        }

        await client.close()

    } catch {
        print("❌ Error: \(error.localizedDescription)")
        await client.close()
    }
}

// MARK: - MCP Server Example

func mcpServerExample() async {
    print("🔧 SDK MCP Server Example")
    print("-------------------------\n")

    // Create an in-process MCP server with custom tools
    let calculator = SDKMCPServer(
        name: "calculator", version: "1.0.0",
        tools: [
            mcpTool(
                name: "add",
                description: "Add two numbers together",
                parameters: [
                    "a": .number(description: "First number"),
                    "b": .number(description: "Second number"),
                ],
                required: ["a", "b"]
            ) { args in
                guard let a = args["a"] as? Double,
                    let b = args["b"] as? Double
                else {
                    return .error("Invalid arguments")
                }
                return .text("The result of \(a) + \(b) = \(a + b)")
            },

            mcpTool(
                name: "multiply",
                description: "Multiply two numbers",
                parameters: [
                    "a": .number(description: "First number"),
                    "b": .number(description: "Second number"),
                ],
                required: ["a", "b"]
            ) { args in
                guard let a = args["a"] as? Double,
                    let b = args["b"] as? Double
                else {
                    return .error("Invalid arguments")
                }
                return .text("The result of \(a) × \(b) = \(a * b)")
            },
        ])

    // SDK MCP servers require streaming mode (ClaudeSDKClient) because they
    // are registered via the control protocol during initialization
    let options = ClaudeAgentOptions(
        allowedTools: ["mcp__calc__add", "mcp__calc__multiply"],
        cwd: FileManager.default.currentDirectoryPath,
        maxTurns: 3,
        mcpServers: ["calc": .sdkServer(calculator)]
    )

    print("Calculator tools available:")
    print("  - mcp__calc__add")
    print("  - mcp__calc__multiply")
    print("")
    print("⚠️  Note: SDK MCP servers require CLI support for the control protocol's")
    print("   'sdkMcpServers' capability. If the tools are not available, your CLI")
    print("   version may not support this feature yet.\n")

    // Use ClaudeSDKClient (streaming mode) for SDK MCP servers
    let client = ClaudeSDKClient(options: options)

    do {
        print("Connecting...")
        try await client.connect()
        print("Connected!\n")

        try await client.query(prompt: "Use the calculator tool to compute 15 + 27 and 6 × 8")

        for try await message in client.receiveUntilResult() {
            switch message {
            case .assistant(let msg):
                // Show tool calls
                for block in msg.content {
                    if case .toolUse(let tool) = block {
                        print("🔧 Tool call: \(tool.name)")
                        print("   Input: \(tool.input)")
                    } else if case .text(let text) = block {
                        print("Claude: \(text.text)")
                    }
                }

            case .user(let msg):
                // Show tool results
                if msg.parentToolUseId != nil {
                    print("   ↳ Tool result received")
                }

            case .result(let result):
                print("\n✅ Done!")
                if let cost = result.totalCostUSD {
                    print("   Cost: $\(String(format: "%.4f", cost))")
                }

            default:
                break
            }
        }

        await client.close()
    } catch {
        print("❌ Error: \(error.localizedDescription)")
        await client.close()
    }
}

// MARK: - External MCP Server Example

func externalMCPExample() async {
    print("🌐 External MCP Server Example")
    print("------------------------------\n")

    print("This example demonstrates configuring external MCP servers using")
    print("the Python FastMCP calculator server included in examples/\n")

    // Get the path to the calculator server
    let cwd = FileManager.default.currentDirectoryPath
    let calculatorPath = "\(cwd)/examples/calculator_mcp_server.py"

    // Check if the calculator server exists
    guard FileManager.default.fileExists(atPath: calculatorPath) else {
        print("❌ Calculator server not found at: \(calculatorPath)")
        print("   Make sure you're running from the project root directory.")
        return
    }

    print("Using Python FastMCP calculator server:")
    print("  Path: \(calculatorPath)")
    print("")

    // Configure the SDK with the Python MCP server
    // Note: Use the correct Python path that has fastmcp installed
    let options = ClaudeAgentOptions(
        cwd: cwd,
        permissionMode: .bypassPermissions,
        maxTurns: 5,
        mcpServers: [
            // Python MCP calculator server using FastMCP
            // Uses python3.11 which has fastmcp installed
            "calc": .stdio(
                command: "/opt/local/bin/python3.11",
                args: [calculatorPath]
            )
        ]
    )

    print("MCP server configured:")
    print("  - calc (stdio): python3 calculator_server.py")
    print(
        "  - Tools available: mcp__calc__add, mcp__calc__subtract, mcp__calc__multiply, mcp__calc__divide"
    )
    print("")

    do {
        print("Asking Claude to perform calculations using the MCP tools...\n")

        for try await message in query(
            prompt:
                "Use the calculator MCP tools to compute: 15 + 27, and then multiply the result by 2. Show your work.",
            options: options
        ) {
            switch message {
            case .assistant(let msg):
                // Show tool calls and text
                for block in msg.content {
                    if case .toolUse(let tool) = block {
                        print("🔧 Tool call: \(tool.name)")
                        // Convert AnyCodable input to JSON-serializable format
                        let serializableInput = tool.input.mapValues { $0.value }
                        if JSONSerialization.isValidJSONObject(serializableInput),
                            let input = try? JSONSerialization.data(
                                withJSONObject: serializableInput),
                            let inputStr = String(data: input, encoding: .utf8)
                        {
                            print("   Input: \(inputStr)")
                        } else {
                            print("   Input: \(tool.input)")
                        }
                    } else if case .text(let text) = block {
                        print("Claude: \(text.text)")
                    }
                }

            case .user(let msg):
                // Show tool results
                if msg.parentToolUseId != nil {
                    switch msg.content {
                    case .blocks(let blocks):
                        for block in blocks {
                            if case .toolResult(let result) = block {
                                if let content = result.content {
                                    switch content {
                                    case .text(let text):
                                        print("   ↳ Result: \(text)")
                                    case .structured(let data):
                                        print("   ↳ Result: \(data)")
                                    }
                                }
                            }
                        }
                    case .text(let text):
                        print("   ↳ Result: \(text)")
                    }
                }

            case .result(let result):
                print("\n✅ Calculation completed!")
                print("   Turns: \(result.numTurns)")
                if let cost = result.totalCostUSD {
                    print("   Cost: $\(String(format: "%.4f", cost))")
                }

            default:
                break
            }
        }
    } catch {
        print("❌ Error: \(error.localizedDescription)")
        print("")
        print("Common issues:")
        print("  - Python3 not installed or not in PATH")
        print("  - Calculator server has syntax errors")
        print("  - MCP server initialization timeout")
    }

    print("")
    print("📚 How to configure MCP servers in your code:")
    print("")
    print("// Python MCP server (stdio)")
    print("MCPServerConfig.stdio(")
    print("    command: \"python3\",")
    print("    args: [\"/path/to/server.py\"]")
    print(")")
    print("")
    print("// HTTP MCP server")
    print("MCPServerConfig.http(url: \"https://mcp.example.com/mcp\")")
    print("")
    print("// HTTP with authentication")
    print("MCPServerConfig.http(")
    print("    url: \"https://api.example.com/mcp\",")
    print("    headers: [\"Authorization\": \"Bearer token\"]")
    print(")")
}

// MARK: - Hooks Example

func hooksExample() async {
    print("🪝 Hooks Example")
    print("----------------\n")

    let options = ClaudeAgentOptions(
        cwd: FileManager.default.currentDirectoryPath,
        maxTurns: 2,
        hooks: [
            .preToolUse: [
                HookMatcher(
                    matcher: nil,
                    hooks: [
                        { input, toolUseId, context in
                            print("⚡ PreToolUse hook triggered!")
                            print("   Tool: \(input.toolName ?? "unknown")")
                            print("   Session: \(context.sessionId)")

                            // Allow the tool to proceed
                            return HookOutput(shouldContinue: true)
                        }
                    ])
            ],
            .postToolUse: [
                HookMatcher(
                    matcher: nil,
                    hooks: [
                        { input, toolUseId, context in
                            print("✅ PostToolUse hook triggered!")
                            print("   Tool: \(input.toolName ?? "unknown")")

                            return HookOutput(shouldContinue: true)
                        }
                    ])
            ],
        ]
    )

    do {
        for try await message in query(
            prompt: "List the files in the current directory",
            options: options
        ) {
            switch message {
            case .assistant(let msg):
                print("\nClaude: \(msg.textContent.prefix(200))...")
            case .result:
                print("\n✅ Done!")
            default:
                break
            }
        }
    } catch {
        print("❌ Error: \(error.localizedDescription)")
    }
}

// MARK: - Permissions Example

func permissionsExample() async {
    print("🔐 Tool Permissions Example")
    print("---------------------------\n")

    // Note: canUseTool requires streaming mode
    let options = ClaudeAgentOptions(
        cwd: FileManager.default.currentDirectoryPath,
        canUseTool: { toolName, input, context in
            print("🔐 Permission check for: \(toolName)")

            // Block any bash commands with 'rm'
            if toolName == "Bash" {
                if let command = input["command"] as? String,
                    command.contains("rm")
                {
                    print("   ❌ DENIED: Dangerous command")
                    return PermissionResult.denyTool(
                        message: "rm commands are not allowed", interrupt: false)
                }
            }

            print("   ✅ ALLOWED")
            return PermissionResult.allowTool()
        },
        maxTurns: 2
    )

    let client = ClaudeSDKClient(options: options)

    do {
        try await client.connect()

        try await client.query(prompt: "Try to list files with 'ls' command")

        for try await message in client.receiveMessages() {
            switch message {
            case .assistant(let msg):
                print("\nClaude: \(msg.textContent.prefix(200))...")
            case .result:
                print("\n✅ Done!")
            default:
                break
            }
        }

        await client.close()

    } catch {
        print("❌ Error: \(error.localizedDescription)")
        await client.close()
    }
}
