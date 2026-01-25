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
        print("""
        Usage: claude-sdk-example <example>
        
        Available examples:
          simple      - Simple one-shot query
          streaming   - Streaming client with multi-turn
          mcp         - SDK MCP server with custom tools
          hooks       - Lifecycle hooks
          permissions - Tool permission callbacks
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
        
        for try await message in client.receiveMessages() {
            switch message {
            case .assistant(let msg):
                print("Claude: \(msg.textContent)")
            case .result:
                break
            default:
                continue
            }
        }
        
        // Second turn
        print("\nYou: What about Germany?")
        try await client.query(prompt: "What about Germany?")
        
        for try await message in client.receiveMessages() {
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
    let calculator = SDKMCPServer(name: "calculator", version: "1.0.0", tools: [
        mcpTool(
            name: "add",
            description: "Add two numbers together",
            parameters: [
                "a": .number(description: "First number"),
                "b": .number(description: "Second number")
            ],
            required: ["a", "b"]
        ) { args in
            guard let a = args["a"] as? Double,
                  let b = args["b"] as? Double else {
                return .error("Invalid arguments")
            }
            return .text("The result of \(a) + \(b) = \(a + b)")
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
            guard let a = args["a"] as? Double,
                  let b = args["b"] as? Double else {
                return .error("Invalid arguments")
            }
            return .text("The result of \(a) × \(b) = \(a * b)")
        }
    ])
    
    let options = ClaudeAgentOptions(
        allowedTools: ["mcp__calc__add", "mcp__calc__multiply"],
        cwd: FileManager.default.currentDirectoryPath,
        maxTurns: 3,
        mcpServers: ["calc": .sdkServer(calculator)]
    )
    
    print("Calculator tools available:")
    print("  - mcp__calc__add")
    print("  - mcp__calc__multiply\n")
    
    do {
        for try await message in query(
            prompt: "Use the calculator tool to compute 15 + 27 and 6 × 8",
            options: options
        ) {
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
                
            case .result(let result):
                print("\n✅ Done!")
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

// MARK: - Hooks Example

func hooksExample() async {
    print("🪝 Hooks Example")
    print("----------------\n")
    
    let options = ClaudeAgentOptions(
        cwd: FileManager.default.currentDirectoryPath,
        maxTurns: 2,
        hooks: [
            .preToolUse: [
                HookMatcher(matcher: nil, hooks: [{ input, toolUseId, context in
                    print("⚡ PreToolUse hook triggered!")
                    print("   Tool: \(input.toolName ?? "unknown")")
                    print("   Session: \(context.sessionId)")
                    
                    // Allow the tool to proceed
                    return HookOutput(shouldContinue: true)
                }])
            ],
            .postToolUse: [
                HookMatcher(matcher: nil, hooks: [{ input, toolUseId, context in
                    print("✅ PostToolUse hook triggered!")
                    print("   Tool: \(input.toolName ?? "unknown")")
                    
                    return HookOutput(shouldContinue: true)
                }])
            ]
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
                   command.contains("rm") {
                    print("   ❌ DENIED: Dangerous command")
                    return PermissionResult.denyTool(message: "rm commands are not allowed", interrupt: false)
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
