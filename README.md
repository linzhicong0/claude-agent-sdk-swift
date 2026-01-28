# Claude Agent SDK for Swift

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/Platform-macOS%20%7C%20iOS%20%7C%20tvOS%20%7C%20watchOS-lightgrey.svg" alt="Platforms">
  <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License MIT">
</p>

A native Swift SDK for building powerful AI agents with Claude. This SDK provides a Swift-idiomatic interface to the Claude Code CLI, enabling seamless integration of Claude's capabilities into your Swift applications with full support for async/await, structured concurrency, and type safety.

## ✨ Features

- 🚀 **Swift Concurrency Native** - Built on `async`/`await` with `AsyncThrowingStream` for streaming responses
- 🎯 **Type-Safe API** - Comprehensive Swift types with enums, protocols, and full `Codable` support
- 🔄 **Bidirectional Streaming** - Interactive conversations with real-time message streaming
- 🛠️ **Tool Control** - Fine-grained control over tool permissions and execution
- 🪝 **Lifecycle Hooks** - Intercept and modify Claude's behavior at key points
- 🔌 **MCP Server Support** - Create in-process Model Context Protocol servers
- 🏗️ **Extensible Transport** - Protocol-based transport layer for custom implementations
- 📦 **Comprehensive Testing** - 148+ unit and E2E tests with 100% pass rate
- 📖 **Full Documentation** - DocC-style documentation for all public APIs

## 📋 Requirements

- **macOS** 13+ / **iOS** 16+ / **tvOS** 16+ / **watchOS** 9+
- **Swift** 5.9 or later
- **Claude Code CLI** (`npm install -g @anthropic-ai/claude-code`)

## 📦 Installation

### Swift Package Manager

Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/anthropics/claude-agent-sdk-swift.git", from: "1.0.0")
]
```

Then add `"ClaudeAgentSDK"` to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: ["ClaudeAgentSDK"]
)
```

### Xcode

1. Open your project in Xcode
2. Go to **File → Add Package Dependencies...**
3. Enter the repository URL: `https://github.com/anthropics/claude-agent-sdk-swift.git`
4. Click **Add Package**

## 🚀 Quick Start

### Simple Query

The simplest way to interact with Claude is using the `query()` function:

```swift
import ClaudeAgentSDK

// Ask Claude a question and process responses
for try await message in query(prompt: "What files are in this directory?") {
    switch message {
    case .assistant(let msg):
        // Process Claude's response
        for block in msg.content {
            if case .text(let text) = block {
                print(text.text)
            }
        }
    case .result(let result):
        // Conversation finished
        print("✅ Done! Cost: $\(result.totalCostUSD ?? 0)")
    default:
        break
    }
}
```

### With Options

Customize Claude's behavior with options:

```swift
let options = ClaudeAgentOptions(
    cwd: "/path/to/project",
    model: "claude-sonnet-4-20250514",
    maxTurns: 10,
    allowedTools: ["Read", "Write", "ListDir"]
)

for try await message in query(prompt: "Analyze this codebase", options: options) {
    print(message)
}
```

## 📚 Usage Examples

### Bidirectional Streaming Client

For interactive conversations, use `ClaudeSDKClient`:

```swift
import ClaudeAgentSDK

// Create a persistent client
let client = ClaudeSDKClient(options: ClaudeAgentOptions(
    cwd: ".",
    model: "claude-sonnet-4-20250514"
))

// Connect to Claude
try await client.connect()
defer { Task { await client.close() } }

// Send a message
try await client.query(prompt: "Hello! Can you help me?")

// Receive responses
for try await message in client.receiveMessages() {
    switch message {
    case .assistant(let msg):
        // Process Claude's response
        for block in msg.content {
            if case .text(let text) = block {
                print("🤖 Claude: \(text.text)")
            }
        }
    case .result(let result):
        print("✅ Conversation finished")
        if let cost = result.totalCostUSD {
            print("💰 Cost: $\(cost)")
        }
        break
    default:
        continue
    }
}
```

### Tool Permission Control

Control which tools Claude can use and intercept tool calls:

```swift
let options = ClaudeAgentOptions(
    cwd: ".",
    permissionMode: .acceptEdits,  // Auto-approve file edits
    canUseTool: { toolName, input, context in
        // Block dangerous commands
        if toolName == "Bash" {
            let command = input["command"] as? String ?? ""
            if command.contains("sudo") || command.contains("rm -rf") {
                return .denyTool(message: "Dangerous command blocked", interrupt: true)
            }
        }
        
        // Allow web searches but log them
        if toolName == "WebSearch" {
            print("🔍 Searching: \(input["query"] ?? "")")
        }
        
        return .allowTool()
    }
)
```

### Lifecycle Hooks

Intercept and modify Claude's behavior at key points:

```swift
let options = ClaudeAgentOptions(
    cwd: ".",
    hooks: [
        // Before tool use
        .preToolUse: [
            HookMatcher(matcher: "Bash", hooks: [{ input, toolUseId, context in
                print("⚙️ About to run command: \(input.toolInput?["command"] ?? "")")
                return HookOutput(shouldContinue: true)
            }])
        ],
        
        // After tool use
        .postToolUse: [
            HookMatcher(hooks: [{ input, toolUseId, context in
                if let output = input.toolOutput {
                    print("✅ Tool completed: \(input.toolName ?? "unknown")")
                }
                return HookOutput(shouldContinue: true)
            }])
        ],
        
        // User prompt submitted
        .userPromptSubmit: [
            HookMatcher(hooks: [{ input, _, context in
                print("💬 User said: \(input.prompt ?? "")")
                return HookOutput(shouldContinue: true)
            }])
        ]
    ]
)
```

### Creating In-Process MCP Servers

Build custom tools that run directly in your Swift process:

```swift
import ClaudeAgentSDK

// Create a calculator MCP server
let calculator = SDKMCPServer(name: "calculator", version: "1.0.0")

// Add an "add" tool using the builder DSL
calculator.addTool(mcpTool(
    name: "add",
    description: "Add two numbers together",
    parameters: [
        "a": .number(description: "First number"),
        "b": .number(description: "Second number")
    ],
    required: ["a", "b"]
) { args in
    let a = args["a"] as? Double ?? 0
    let b = args["b"] as? Double ?? 0
    return .text("The sum is \(a + b)")
})

// Add a "multiply" tool
calculator.addTool(mcpTool(
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
    return .text("The product is \(a * b)")
})

// Use the MCP server
let options = ClaudeAgentOptions(
    cwd: ".",
    mcpServers: ["calc": .sdkServer(calculator)],
    allowedTools: ["mcp__calc__add", "mcp__calc__multiply"]
)

for try await message in query(
    prompt: "What is 15 + 27? Then multiply the result by 3.",
    options: options
) {
    print(message)
}
```

### External MCP Servers

Connect to external MCP servers (like npm packages):

```swift
let options = ClaudeAgentOptions(
    cwd: ".",
    mcpServers: [
        "filesystem": .external(ExternalMCPServerConfig(
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem"],
            env: ["NODE_ENV": "production"],
            cwd: "/path/to/project"
        )),
        "github": .external(ExternalMCPServerConfig(
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"]
        ))
    ]
)
```

### Configuration Options

The SDK provides extensive configuration options:

```swift
let options = ClaudeAgentOptions(
    // Tools
    tools: .preset(.default),           // or .list(["Read", "Write"])
    allowedTools: ["Read", "Write"],
    disallowedTools: ["WebSearch"],
    
    // System Prompt
    systemPrompt: .preset(.default),    // or .custom("You are...")
    
    // Working Directory & Environment
    cwd: "/path/to/project",
    env: ["API_KEY": "secret"],
    
    // Permissions
    permissionMode: .acceptEdits,       // .default, .plan, .bypassPermissions
    canUseTool: { toolName, input, context in
        // Custom permission logic
        return .allowTool()
    },
    
    // Conversation
    continueConversation: false,
    maxTurns: 20,
    maxBudgetUSD: 5.0,
    
    // Model
    model: "claude-sonnet-4-20250514",
    fallbackModel: "claude-3-5-sonnet-20241022",
    betas: [.interleaved_thinking],
    
    // Advanced
    includePartialMessages: false,
    enableFileCheckpointing: true,
    maxThinkingTokens: 10000,
    
    // Plugins
    plugins: [PluginConfig(path: "./my-plugin")],
    
    // Sandbox
    sandbox: SandboxSettings(type: .docker),
    sandboxPermissions: NetworkPermissions(
        allowLocalhostBinding: true,
        outboundHosts: ["api.example.com"]
    ),
    
    // Debugging
    stderrCallback: { stderr in
        print("stderr: \(stderr)")
    }
)
```

## 🎨 Message Types

The SDK provides type-safe message handling:

```swift
for try await message in query(prompt: "Hello") {
    switch message {
    case .user(let msg):
        // User message (rarely seen in responses)
        print("User: \(msg.content)")
        
    case .assistant(let msg):
        // Claude's response
        for block in msg.content {
            switch block {
            case .text(let text):
                print("Text: \(text.text)")
            case .thinking(let thinking):
                print("Thinking: \(thinking.thinking)")
            case .toolUse(let tool):
                print("Using tool: \(tool.name)")
            }
        }
        
    case .system(let msg):
        // System messages
        print("System: \(msg.content)")
        
    case .result(let result):
        // Final result with metadata
        print("Status: \(result.subtype)")
        print("Turns: \(result.numConversationTurns ?? 0)")
        print("Cost: $\(result.totalCostUSD ?? 0)")
        
        if let output = result.structuredOutput {
            print("Structured output: \(output)")
        }
        
    case .streamEvent(let event):
        // Streaming events (when includePartialMessages: true)
        switch event.event {
        case .contentBlockDelta:
            print("Streaming content...")
        default:
            break
        }
    }
}
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Application Layer                        │
│              (query() / ClaudeSDKClient)                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Internal Client Layer                      │
│            (Query + InternalClient + ControlProtocol)       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Transport Layer                          │
│          (TransportProtocol / SubprocessCLITransport)       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  Claude Code CLI Process                     │
│                     (Node.js binary)                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Anthropic Claude API                       │
│                        (HTTPS)                              │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

- **Application Layer**: High-level API (`query()` function and `ClaudeSDKClient` actor)
- **Internal Client**: Message parsing, control protocol handling, session management
- **Transport Layer**: Abstraction for CLI communication (subprocess, remote, mock)
- **CLI Process**: Official Claude Code CLI (Node.js)
- **API**: Anthropic's Claude API

## 🔌 Custom Transport

Implement your own transport for custom scenarios:

```swift
import ClaudeAgentSDK

actor RemoteTransport: TransportProtocol {
    var isRunning = false
    
    func connect() async throws {
        // Connect to remote CLI via SSH, Docker, etc.
        isRunning = true
    }
    
    func write(_ message: String) async throws {
        // Send message to remote CLI
    }
    
    func readMessages() -> AsyncThrowingStream<[String: Any], Error> {
        AsyncThrowingStream { continuation in
            // Stream messages from remote CLI
        }
    }
    
    func close() async {
        isRunning = false
    }
}
```

## 🧪 Testing

### Unit Tests

Run the comprehensive test suite:

```bash
swift test
```

The SDK includes 148+ tests covering:
- ✅ Transport layer (CLI discovery, command building)
- ✅ Client initialization and state management
- ✅ Message parsing (all message types)
- ✅ Control protocol (hooks, permissions)
- ✅ MCP server functionality
- ✅ Streaming and async patterns
- ✅ Type safety and Codable conformance

### Mock Transport for Testing

Use `MockCLITransport` in your tests:

```swift
import XCTest
@testable import ClaudeAgentSDK

final class MyTests: XCTestCase {
    func testClaudeInteraction() async throws {
        let mock = MockCLITransport()
        mock.queueResponse(["type": "assistant", "message": ["role": "assistant"]])
        mock.queueResponse(["type": "result", "subtype": "success"])
        
        try await mock.connect()
        
        for try await message in mock.readMessages() {
            // Test message handling
        }
        
        XCTAssertTrue(mock.wasConnected)
    }
}
```

## 📖 API Documentation

Generate documentation using DocC:

```bash
swift package generate-documentation
```

Or view inline documentation in Xcode with ⌥+Click on any type or method.

## 🌍 Examples

Check out the `examples/` directory for more examples:

- **Quick Start**: Basic query usage
- **Streaming Mode**: Interactive conversations
- **Tool Permissions**: Custom tool control
- **Hooks**: Lifecycle event handling
- **MCP Calculator**: In-process MCP server
- **Filesystem Agent**: File system operations
- **Multi-Agent**: Agent delegation

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/anthropics/claude-agent-sdk-swift.git
   cd claude-agent-sdk-swift
   ```

2. Install Claude Code CLI:
   ```bash
   npm install -g @anthropic-ai/claude-code
   ```

3. Run tests:
   ```bash
   swift test
   ```

4. Build the package:
   ```bash
   swift build
   ```

## 🐛 Troubleshooting

### CLI Not Found

If you get a "CLI not found" error:

```bash
# Install the CLI
npm install -g @anthropic-ai/claude-code

# Verify installation
which claude

# Or specify the path explicitly
let options = ClaudeAgentOptions(
    cliPath: "/path/to/claude"
)
```

### Version Compatibility

Check CLI version compatibility:

```bash
claude -v
```

Skip version check (for testing):

```bash
export CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK=1
```

### Debug Stderr Output

Capture CLI stderr for debugging:

```swift
let options = ClaudeAgentOptions(
    stderrCallback: { stderr in
        print("CLI stderr: \(stderr)")
    }
)
```

## 📄 Communication Protocol

The SDK communicates with the CLI using line-delimited JSON over stdin/stdout:

## 📄 Communication Protocol

The SDK communicates with the CLI using line-delimited JSON over stdin/stdout:

**SDK → CLI (stdin):**
```json
{"type": "user", "message": {"role": "user", "content": "Hello"}, "session_id": "default"}
```

**CLI → SDK (stdout):**
```json
{"type": "assistant", "message": {"role": "assistant", "content": [...]}, "model": "claude-sonnet-4"}
{"type": "result", "subtype": "success", "total_cost_usd": 0.05}
```

### Control Protocol

For advanced features (hooks, permissions), the SDK uses a control protocol:

```json
// Permission request (CLI → SDK)
{"type": "control_request", "subtype": "tool_permission", "data": {"tool_name": "Bash", "input": {...}}}

// Permission response (SDK → CLI)
{"type": "control_response", "request_id": "req_123", "data": {"permission": "allow"}}
```

## 🔒 Security Considerations

- **Tool Permissions**: Always validate tool calls, especially for `Bash` and file operations
- **Input Sanitization**: Sanitize user inputs before passing to Claude
- **API Keys**: Never hardcode API keys; use environment variables
- **Sandbox**: Consider using sandbox mode for untrusted operations:
  ```swift
  let options = ClaudeAgentOptions(
      sandbox: SandboxSettings(type: .docker),
      sandboxPermissions: NetworkPermissions(
          allowLocalhostBinding: false,
          outboundDenyHosts: ["sensitive.internal"]
      )
  )
  ```

## 🎯 Best Practices

1. **Use Actors for Thread Safety**
   ```swift
   actor MyAgent {
       let client: ClaudeSDKClient
       
       func chat(prompt: String) async throws {
           // Thread-safe access
       }
   }
   ```

2. **Handle Errors Gracefully**
   ```swift
   do {
       for try await message in query(prompt: "Hello") {
           // Process messages
       }
   } catch let error as ClaudeSDKError {
       switch error {
       case .cliNotFound(let paths):
           print("Install Claude CLI: npm install -g @anthropic-ai/claude-code")
       case .connectionFailed(let reason):
           print("Connection failed: \(reason)")
       default:
           print("Error: \(error)")
       }
   }
   ```

3. **Clean Up Resources**
   ```swift
   let client = ClaudeSDKClient()
   defer { Task { await client.close() } }
   ```

4. **Use Structured Concurrency**
   ```swift
   await withTaskGroup(of: Void.self) { group in
       group.addTask {
           for try await message in query(prompt: "Task 1") {
               // Handle message
           }
       }
       group.addTask {
           for try await message in query(prompt: "Task 2") {
               // Handle message
           }
       }
   }
   ```

5. **Monitor Costs**
   ```swift
   var totalCost = 0.0
   for try await message in query(prompt: "Expensive task") {
       if case .result(let result) = message {
           totalCost += result.totalCostUSD ?? 0
           if totalCost > 10.0 {
               print("⚠️ Cost limit exceeded!")
           }
       }
   }
   ```

## 🆚 Comparison with Python SDK

The Swift SDK provides equivalent functionality to the Python SDK with Swift-native patterns:

| Feature            | Python             | Swift                 |
| ------------------ | ------------------ | --------------------- |
| **Async/Await**    | `async for`        | `for try await`       |
| **Streaming**      | `AsyncGenerator`   | `AsyncThrowingStream` |
| **Thread Safety**  | Threading/asyncio  | Actors                |
| **Type System**    | TypedDict/Pydantic | Structs/Enums/Codable |
| **Error Handling** | Exceptions         | Throwing functions    |
| **Memory Model**   | GC                 | ARC                   |

## 📚 Resources

- **Official Documentation**: [Claude Code Docs](https://docs.anthropic.com/en/docs/claude-code)
- **API Reference**: [Anthropic API](https://docs.anthropic.com)
- **MCP Specification**: [Model Context Protocol](https://modelcontextprotocol.io)
- **Swift Concurrency**: [Swift.org](https://www.swift.org/documentation/concurrency/)

## 🙏 Acknowledgements

This SDK is built on top of the official Claude Code CLI. Thanks to:
- The Anthropic team for Claude and the CLI
- The Swift community for async/await and structured concurrency
- Contributors and testers

## 📜 License

MIT License - see [LICENSE](LICENSE) file for details.

---

<p align="center">
  <strong>Built with ❤️ by Jack</strong>
  <br>
  <a href="https://github.com/anthropics/claude-agent-sdk-swift/issues">Report Bug</a>
  ·
  <a href="https://github.com/anthropics/claude-agent-sdk-swift/issues">Request Feature</a>
  ·
  <a href="https://docs.anthropic.com">Documentation</a>
</p>
