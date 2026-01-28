// MARK: - Options & Configuration Types
//
// This file defines all configuration options for the Claude Agent SDK.
// Options control how the SDK interacts with the Claude CLI and API.
//

import Foundation

// MARK: - Permission Mode

/// Permission mode for tool execution.
///
/// Controls how the CLI handles permission prompts for potentially dangerous operations.
public enum PermissionMode: String, Sendable, Codable {
    /// Default mode - CLI prompts for dangerous tool calls
    case `default` = "default"

    /// Auto-accept file edits without prompting
    case acceptEdits = "acceptEdits"

    /// Planning mode - Claude explains actions without executing
    case plan = "plan"

    /// Bypass all permission prompts (use with caution!)
    case bypassPermissions = "bypassPermissions"
}

// MARK: - Tools Configuration

/// Tools preset options.
public enum ToolsPreset: String, Sendable {
    /// Default set of tools
    case `default` = "default"

    /// No tools enabled
    case none = ""
}

/// System prompt preset options.
public enum SystemPromptPreset: String, Sendable {
    /// Default Claude Code system prompt
    case `default` = "default"
}

// MARK: - Hook Types

/// Hook event types for lifecycle callbacks.
///
/// Hooks allow you to intercept and modify Claude's behavior at key points.
public enum HookEvent: String, Sendable, Codable, Hashable {
    /// Triggered before a tool is executed
    case preToolUse = "PreToolUse"

    /// Triggered after a tool is executed
    case postToolUse = "PostToolUse"

    /// Triggered when the user submits a prompt
    case userPromptSubmit = "UserPromptSubmit"

    /// Triggered when the session stops
    case stop = "Stop"

    /// Triggered when a subagent stops
    case subagentStop = "SubagentStop"

    /// Triggered before context compaction
    case preCompact = "PreCompact"
}

// MARK: - Beta Features

/// SDK beta features that can be enabled.
/// See https://docs.anthropic.com/en/api/beta-headers
public enum SdkBeta: String, Sendable, Codable {
    /// Interleaved thinking - show Claude's reasoning
    case interleaved_thinking

    /// Output schema - structured JSON output
    case output_schema

    /// Extended context window (1M tokens)
    case context_1m_2025_08_07 = "context-1m-2025-08-07"
}

// MARK: - Setting Sources

/// Setting source locations for configuration.
public enum SettingSource: String, Sendable, Codable {
    /// User-level settings
    case userSettings

    /// Project-level settings
    case projectSettings

    /// Local (gitignored) settings
    case localSettings

    /// Session-only settings
    case session
}

// MARK: - Permission Result

/// Result of a tool permission check.
///
/// Return from the ``CanUseTool`` callback to allow or deny tool execution.
public enum PermissionResult: Sendable {
    /// Allow the tool to execute
    case allow(updatedInput: [String: Any]?, updatedPermissions: [PermissionUpdate]?)

    /// Deny the tool execution
    case deny(message: String, interrupt: Bool)

    /// Create an allow result.
    ///
    /// - Parameters:
    ///   - updatedInput: Optionally modify the tool input
    ///   - updatedPermissions: Optionally update permission rules
    public static func allowTool(
        updatedInput: [String: Any]? = nil, updatedPermissions: [PermissionUpdate]? = nil
    ) -> PermissionResult {
        .allow(updatedInput: updatedInput, updatedPermissions: updatedPermissions)
    }

    /// Create a deny result.
    ///
    /// - Parameters:
    ///   - message: Reason for denial (shown to Claude)
    ///   - interrupt: If true, interrupt the entire session
    public static func denyTool(message: String = "", interrupt: Bool = false) -> PermissionResult {
        .deny(message: message, interrupt: interrupt)
    }
}

/// Permission update entry for modifying rules.
public struct PermissionUpdate: Sendable {
    /// The tool name to update
    public let toolName: String

    /// The permission rule ("allow", "deny", "ask")
    public let permission: String

    public init(toolName: String, permission: String) {
        self.toolName = toolName
        self.permission = permission
    }
}

// MARK: - Tool Permission Context

/// Context provided to tool permission callbacks.
public struct ToolPermissionContext: Sendable {
    /// The current session ID
    public let sessionId: String

    /// Optional abort controller for cancellation
    public let abortController: AbortController?

    /// Timestamps of files read (for checkpointing)
    public let readFileTimestamps: [String: Date]?

    public init(
        sessionId: String, abortController: AbortController? = nil,
        readFileTimestamps: [String: Date]? = nil
    ) {
        self.sessionId = sessionId
        self.abortController = abortController
        self.readFileTimestamps = readFileTimestamps
    }
}

/// Abort controller for cancellation support.
public final class AbortController: @unchecked Sendable {
    private var _isAborted = false
    private let lock = NSLock()

    /// Whether the operation has been aborted.
    public var isAborted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isAborted
    }

    /// Signal an abort.
    public func abort() {
        lock.lock()
        defer { lock.unlock() }
        _isAborted = true
    }

    public init() {}
}

/// Tool permission callback type.
///
/// Called when Claude requests to use a tool. Return ``PermissionResult/allowTool(updatedInput:updatedPermissions:)``
/// or ``PermissionResult/denyTool(message:interrupt:)`` to control execution.
public typealias CanUseTool =
    @Sendable (
        _ toolName: String,
        _ input: [String: Any],
        _ context: ToolPermissionContext
    ) async throws -> PermissionResult

// MARK: - Hook Types

/// Input data for hook callbacks.
public struct HookInput: Sendable {
    /// The hook event type
    public let hookEventName: HookEvent

    /// Tool name (for tool-related hooks)
    public let toolName: String?

    /// Tool input (for PreToolUse)
    public let toolInput: [String: AnyCodable]?

    /// Tool output (for PostToolUse)
    public let toolOutput: AnyCodable?

    /// User prompt (for UserPromptSubmit)
    public let prompt: String?

    /// Stop reason (for Stop hooks)
    public let stopReason: String?

    public init(
        hookEventName: HookEvent,
        toolName: String? = nil,
        toolInput: [String: AnyCodable]? = nil,
        toolOutput: AnyCodable? = nil,
        prompt: String? = nil,
        stopReason: String? = nil
    ) {
        self.hookEventName = hookEventName
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolOutput = toolOutput
        self.prompt = prompt
        self.stopReason = stopReason
    }
}

/// Context for hook callbacks.
public struct HookContext: Sendable {
    /// The current session ID
    public let sessionId: String

    /// Optional abort controller for cancellation
    public let abortController: AbortController?

    public init(sessionId: String, abortController: AbortController? = nil) {
        self.sessionId = sessionId
        self.abortController = abortController
    }
}

/// Output from a hook callback.
public struct HookOutput: Sendable {
    /// Whether to continue execution (default true)
    public let shouldContinue: Bool

    /// Whether to hide output from transcript
    public let suppressOutput: Bool

    /// Custom stop reason
    public let stopReason: String?

    /// Decision to block execution
    public let decision: HookDecision?

    /// System message to send to Claude
    public let systemMessage: String?

    /// Reason for the decision
    public let reason: String?

    /// Event-specific output data
    public let hookSpecificOutput: HookSpecificOutput?

    public init(
        shouldContinue: Bool = true,
        suppressOutput: Bool = false,
        stopReason: String? = nil,
        decision: HookDecision? = nil,
        systemMessage: String? = nil,
        reason: String? = nil,
        hookSpecificOutput: HookSpecificOutput? = nil
    ) {
        self.shouldContinue = shouldContinue
        self.suppressOutput = suppressOutput
        self.stopReason = stopReason
        self.decision = decision
        self.systemMessage = systemMessage
        self.reason = reason
        self.hookSpecificOutput = hookSpecificOutput
    }
}

/// Hook decision type.
public enum HookDecision: String, Sendable {
    /// Block the operation
    case block

    /// Allow the operation
    case allow

    /// Deny the operation
    case deny

    /// Ask for permission (default behavior)
    case ask
}

/// Hook-specific output data for PreToolUse events.
public struct PreToolUseHookSpecificOutput: Sendable {
    public let hookEventName: HookEvent = .preToolUse

    /// Permission decision: "allow", "deny", or "ask"
    public let permissionDecision: String?

    /// Reason for the permission decision
    public let permissionDecisionReason: String?

    /// Updated input to use for the tool call
    public let updatedInput: [String: Any]?

    public init(
        permissionDecision: String? = nil,
        permissionDecisionReason: String? = nil,
        updatedInput: [String: Any]? = nil
    ) {
        self.permissionDecision = permissionDecision
        self.permissionDecisionReason = permissionDecisionReason
        self.updatedInput = updatedInput
    }
}

/// Hook-specific output data for PostToolUse events.
public struct PostToolUseHookSpecificOutput: Sendable {
    public let hookEventName: HookEvent = .postToolUse

    /// Additional context to provide to Claude
    public let additionalContext: String?

    public init(additionalContext: String? = nil) {
        self.additionalContext = additionalContext
    }
}

/// Hook-specific output data for UserPromptSubmit events.
public struct UserPromptSubmitHookSpecificOutput: Sendable {
    public let hookEventName: HookEvent = .userPromptSubmit

    /// Additional context to provide to Claude
    public let additionalContext: String?

    public init(additionalContext: String? = nil) {
        self.additionalContext = additionalContext
    }
}

/// Hook-specific output data (legacy, for backward compatibility).
public struct HookSpecificOutput: Sendable {
    public let hookEventName: HookEvent
    public let permissionDecision: String?
    public let permissionDecisionReason: String?
    public let additionalContext: String?
    public let updatedInput: [String: Any]?

    public init(
        hookEventName: HookEvent,
        permissionDecision: String? = nil,
        permissionDecisionReason: String? = nil,
        additionalContext: String? = nil,
        updatedInput: [String: Any]? = nil
    ) {
        self.hookEventName = hookEventName
        self.permissionDecision = permissionDecision
        self.permissionDecisionReason = permissionDecisionReason
        self.additionalContext = additionalContext
        self.updatedInput = updatedInput
    }
}

/// Hook callback type.
public typealias HookCallback =
    @Sendable (
        _ input: HookInput,
        _ toolUseId: String?,
        _ context: HookContext
    ) async throws -> HookOutput

/// Hook matcher for filtering hooks by tool pattern.
public struct HookMatcher: Sendable {
    /// Pattern to match tool names (supports regex-like patterns)
    public let matcher: String?

    /// Callbacks to execute when matched
    public let hooks: [HookCallback]

    /// Timeout for hook execution in seconds
    public let timeout: TimeInterval?

    public init(matcher: String? = nil, hooks: [HookCallback], timeout: TimeInterval? = nil) {
        self.matcher = matcher
        self.hooks = hooks
        self.timeout = timeout
    }
}

// MARK: - MCP Configuration

/// MCP server transport type.
public enum MCPTransportType: String, Sendable, Codable {
    /// Standard I/O transport (local process)
    case stdio
    /// HTTP transport (remote server)
    case http
    /// SSE transport (deprecated, use HTTP instead)
    case sse
}

/// MCP server configuration - external process or SDK-embedded.
public enum MCPServerConfig: Sendable {
    /// External MCP server (stdio or HTTP)
    case external(ExternalMCPServerConfig)

    /// SDK-embedded MCP server
    case sdkServer(SDKMCPServer)

    // MARK: - Convenience Factory Methods

    /// Create a stdio MCP server configuration.
    ///
    /// Use this for local MCP servers that run as subprocess commands.
    ///
    /// - Parameters:
    ///   - command: Command to run (e.g., "npx", "python")
    ///   - args: Command arguments
    ///   - env: Environment variables
    ///   - cwd: Working directory
    /// - Returns: MCPServerConfig configured for stdio transport
    ///
    /// Example:
    /// ```swift
    /// // Using npx to run a filesystem server
    /// let fsServer = MCPServerConfig.stdio(
    ///     command: "npx",
    ///     args: ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"]
    /// )
    ///
    /// // Using Python MCP server
    /// let pythonServer = MCPServerConfig.stdio(
    ///     command: "python",
    ///     args: ["-m", "mcp_server"],
    ///     env: ["API_KEY": "secret"]
    /// )
    /// ```
    public static func stdio(
        command: String,
        args: [String]? = nil,
        env: [String: String]? = nil,
        cwd: String? = nil
    ) -> MCPServerConfig {
        .external(
            ExternalMCPServerConfig(
                type: .stdio,
                command: command,
                args: args,
                env: env,
                cwd: cwd
            ))
    }

    /// Create an HTTP MCP server configuration.
    ///
    /// Use this for remote MCP servers that communicate over HTTP.
    ///
    /// - Parameters:
    ///   - url: The HTTP URL of the MCP server
    ///   - headers: Optional HTTP headers (e.g., for authentication)
    /// - Returns: MCPServerConfig configured for HTTP transport
    ///
    /// Example:
    /// ```swift
    /// // Public HTTP MCP server
    /// let notion = MCPServerConfig.http(url: "https://mcp.notion.com/mcp")
    ///
    /// // HTTP MCP server with authentication
    /// let privateApi = MCPServerConfig.http(
    ///     url: "https://api.example.com/mcp",
    ///     headers: ["Authorization": "Bearer your-token"]
    /// )
    /// ```
    public static func http(
        url: String,
        headers: [String: String]? = nil
    ) -> MCPServerConfig {
        .external(
            ExternalMCPServerConfig(
                type: .http,
                url: url,
                headers: headers
            ))
    }

    /// Create an SSE MCP server configuration.
    ///
    /// - Note: SSE transport is deprecated. Use HTTP instead where available.
    ///
    /// - Parameters:
    ///   - url: The SSE URL of the MCP server
    ///   - headers: Optional HTTP headers (e.g., for authentication)
    /// - Returns: MCPServerConfig configured for SSE transport
    public static func sse(
        url: String,
        headers: [String: String]? = nil
    ) -> MCPServerConfig {
        .external(
            ExternalMCPServerConfig(
                type: .sse,
                url: url,
                headers: headers
            ))
    }
}

/// Configuration for external MCP server (stdio or HTTP).
///
/// External MCP servers can be configured in two ways:
///
/// 1. **stdio transport**: Local process that communicates via stdin/stdout
///    - Requires: `command` (and optionally `args`, `env`, `cwd`)
///    - Example: `npx -y @modelcontextprotocol/server-filesystem /path`
///
/// 2. **HTTP transport**: Remote server that communicates via HTTP
///    - Requires: `url` (and optionally `headers`)
///    - Example: `https://mcp.notion.com/mcp`
///
/// Use the convenience factory methods on ``MCPServerConfig`` for easier creation.
public struct ExternalMCPServerConfig: Sendable, Codable {
    /// Transport type (stdio or http)
    public let type: MCPTransportType

    // MARK: - stdio transport properties

    /// Command to run (e.g., "npx", "python") - required for stdio
    public let command: String?

    /// Command arguments - for stdio
    public let args: [String]?

    /// Environment variables - for stdio
    public let env: [String: String]?

    /// Working directory - for stdio
    public let cwd: String?

    // MARK: - HTTP transport properties

    /// URL of the MCP server - required for http/sse
    public let url: String?

    /// HTTP headers (e.g., for authentication) - for http/sse
    public let headers: [String: String]?

    /// Create a stdio MCP server configuration.
    ///
    /// - Parameters:
    ///   - command: Command to run (e.g., "npx")
    ///   - args: Command arguments
    ///   - env: Environment variables
    ///   - cwd: Working directory
    public init(
        command: String,
        args: [String]? = nil,
        env: [String: String]? = nil,
        cwd: String? = nil
    ) {
        self.type = .stdio
        self.command = command
        self.args = args
        self.env = env
        self.cwd = cwd
        self.url = nil
        self.headers = nil
    }

    /// Create an HTTP/SSE MCP server configuration.
    ///
    /// - Parameters:
    ///   - type: Transport type (.http or .sse)
    ///   - url: URL of the MCP server
    ///   - headers: Optional HTTP headers
    public init(
        type: MCPTransportType,
        url: String,
        headers: [String: String]? = nil
    ) {
        precondition(type == .http || type == .sse, "Use init(command:...) for stdio transport")
        self.type = type
        self.url = url
        self.headers = headers
        self.command = nil
        self.args = nil
        self.env = nil
        self.cwd = nil
    }

    /// Internal initializer for all properties.
    internal init(
        type: MCPTransportType,
        command: String? = nil,
        args: [String]? = nil,
        env: [String: String]? = nil,
        cwd: String? = nil,
        url: String? = nil,
        headers: [String: String]? = nil
    ) {
        self.type = type
        self.command = command
        self.args = args
        self.env = env
        self.cwd = cwd
        self.url = url
        self.headers = headers
    }
}

// MARK: - Agent Definition

/// Agent definition for multi-agent scenarios.
public struct AgentDefinition: Sendable, Codable {
    /// Model to use for this agent
    public let model: String?

    /// System prompt for this agent
    public let systemPrompt: String?

    /// Tools available to this agent
    public let tools: [String]?

    /// Additional allowed tools
    public let allowedTools: [String]?

    /// Tools to disallow
    public let disallowedTools: [String]?

    /// Maximum conversation turns
    public let maxTurns: Int?

    public init(
        model: String? = nil,
        systemPrompt: String? = nil,
        tools: [String]? = nil,
        allowedTools: [String]? = nil,
        disallowedTools: [String]? = nil,
        maxTurns: Int? = nil
    ) {
        self.model = model
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.allowedTools = allowedTools
        self.disallowedTools = disallowedTools
        self.maxTurns = maxTurns
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case systemPrompt = "system_prompt"
        case tools
        case allowedTools = "allowed_tools"
        case disallowedTools = "disallowed_tools"
        case maxTurns = "max_turns"
    }
}

// MARK: - Sandbox Settings

/// Sandbox settings for isolated execution.
public struct SandboxSettings: Sendable, Codable {
    /// Sandbox type
    public let type: SandboxType

    /// Additional options
    public let options: [String: AnyCodable]?

    public init(type: SandboxType, options: [String: AnyCodable]? = nil) {
        self.type = type
        self.options = options
    }
}

/// Sandbox type.
public enum SandboxType: String, Sendable, Codable {
    /// Docker container sandbox
    case docker

    /// No sandboxing
    case none
}

/// Network permission settings for sandbox.
public struct NetworkPermissions: Sendable, Codable {
    /// Unix socket paths to allow
    public let unixSocketPaths: [String]?

    /// Allow all socket connections
    public let allowAllSockets: Bool?

    /// Allow binding to localhost
    public let allowLocalhostBinding: Bool?

    /// Outbound hosts to allow
    public let outboundHosts: [String]?

    /// Outbound hosts to deny
    public let outboundDenyHosts: [String]?

    public init(
        unixSocketPaths: [String]? = nil,
        allowAllSockets: Bool? = nil,
        allowLocalhostBinding: Bool? = nil,
        outboundHosts: [String]? = nil,
        outboundDenyHosts: [String]? = nil
    ) {
        self.unixSocketPaths = unixSocketPaths
        self.allowAllSockets = allowAllSockets
        self.allowLocalhostBinding = allowLocalhostBinding
        self.outboundHosts = outboundHosts
        self.outboundDenyHosts = outboundDenyHosts
    }
}

// MARK: - Plugin Configuration

/// Plugin configuration for extending Claude.
public struct PluginConfig: Sendable, Codable {
    /// Path to the plugin directory
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

// MARK: - Main Options

/// Main configuration options for Claude Agent SDK.
///
/// This struct contains all configuration options for controlling
/// how the SDK interacts with Claude. Options can be provided when
/// calling ``query(prompt:options:)`` or creating a ``ClaudeSDKClient``.
///
/// ## Example
///
/// ```swift
/// let options = ClaudeAgentOptions(
///     allowedTools: ["Read", "Write"],
///     model: "claude-sonnet-4-20250514",
///     maxTurns: 10,
///     permissionMode: .acceptEdits
/// )
///
/// for try await message in query(prompt: "Hello!", options: options) {
///     // Process messages
/// }
/// ```
public struct ClaudeAgentOptions: Sendable {
    // MARK: - Tools

    /// Tools to enable (preset or explicit list)
    public var tools: ToolsConfig?

    /// Additional tools to allow
    public var allowedTools: [String]

    /// Tools to disallow
    public var disallowedTools: [String]

    // MARK: - System Prompt

    /// System prompt for Claude
    public var systemPrompt: SystemPromptConfig?

    // MARK: - Working Directory

    /// Working directory for CLI
    public var cwd: String?

    /// Explicit path to Claude CLI binary
    public var cliPath: String?

    /// Environment variables for CLI process
    public var env: [String: String]

    // MARK: - Permissions

    /// Permission mode for tool execution
    public var permissionMode: PermissionMode?

    /// Callback for tool permission decisions
    public var canUseTool: CanUseTool?

    // MARK: - Conversation

    /// Continue existing conversation
    public var continueConversation: Bool

    /// Resume specific session by ID
    public var resume: String?

    /// Fork session instead of continuing
    public var forkSession: Bool

    /// Maximum conversation turns
    public var maxTurns: Int?

    /// Maximum budget in USD
    public var maxBudgetUSD: Double?

    // MARK: - Model

    /// Claude model to use
    public var model: String?

    /// Fallback model if primary unavailable
    public var fallbackModel: String?

    /// Beta features to enable
    public var betas: [SdkBeta]

    // MARK: - MCP & Tools

    /// MCP server configurations
    public var mcpServers: [String: MCPServerConfig]

    /// Only use MCP servers from --mcp-config, ignoring all other MCP configurations
    public var strictMcpConfig: Bool

    // MARK: - Hooks

    /// Lifecycle hooks
    public var hooks: [HookEvent: [HookMatcher]]?

    // MARK: - Advanced

    /// Include partial/streaming messages
    public var includePartialMessages: Bool

    /// Setting sources to use
    public var settings: String?

    /// Setting sources as enum list
    public var settingSources: [SettingSource]?

    /// Sandbox settings
    public var sandbox: SandboxSettings?

    /// Network permissions for sandbox
    public var sandboxPermissions: NetworkPermissions?

    /// Agent definitions for multi-agent
    public var agents: [String: AgentDefinition]?

    /// JSON schema for structured output
    public var outputFormat: [String: AnyCodable]?

    /// Enable file checkpointing
    public var enableFileCheckpointing: Bool

    /// Maximum thinking tokens
    public var maxThinkingTokens: Int?

    // MARK: - Plugins

    /// Plugin configurations
    public var plugins: [PluginConfig]?

    // MARK: - User

    /// User identity for subprocess
    public var user: String?

    // MARK: - Debugging

    /// Callback for stderr output
    public var stderrCallback: (@Sendable (String) -> Void)?

    /// Maximum buffer size in bytes
    public var maxBufferSize: Int?

    /// Extra CLI arguments
    public var extraArgs: [String: String?]

    /// Additional directories to add
    public var additionalDirectories: [String]

    // MARK: - Initializer

    /// Create new configuration options.
    ///
    /// All parameters have sensible defaults. Provide only the options you need to customize.
    public init(
        tools: ToolsConfig? = nil,
        allowedTools: [String] = [],
        disallowedTools: [String] = [],
        systemPrompt: SystemPromptConfig? = nil,
        cwd: String? = nil,
        cliPath: String? = nil,
        env: [String: String] = [:],
        permissionMode: PermissionMode? = nil,
        canUseTool: CanUseTool? = nil,
        continueConversation: Bool = false,
        resume: String? = nil,
        forkSession: Bool = false,
        maxTurns: Int? = nil,
        maxBudgetUSD: Double? = nil,
        model: String? = nil,
        fallbackModel: String? = nil,
        betas: [SdkBeta] = [],
        mcpServers: [String: MCPServerConfig] = [:],
        strictMcpConfig: Bool = false,
        hooks: [HookEvent: [HookMatcher]]? = nil,
        includePartialMessages: Bool = false,
        settings: String? = nil,
        settingSources: [SettingSource]? = nil,
        sandbox: SandboxSettings? = nil,
        sandboxPermissions: NetworkPermissions? = nil,
        agents: [String: AgentDefinition]? = nil,
        outputFormat: [String: AnyCodable]? = nil,
        enableFileCheckpointing: Bool = false,
        maxThinkingTokens: Int? = nil,
        plugins: [PluginConfig]? = nil,
        user: String? = nil,
        stderrCallback: (@Sendable (String) -> Void)? = nil,
        maxBufferSize: Int? = nil,
        extraArgs: [String: String?] = [:],
        additionalDirectories: [String] = []
    ) {
        self.tools = tools
        self.allowedTools = allowedTools
        self.disallowedTools = disallowedTools
        self.systemPrompt = systemPrompt
        self.cwd = cwd
        self.cliPath = cliPath
        self.env = env
        self.permissionMode = permissionMode
        self.canUseTool = canUseTool
        self.continueConversation = continueConversation
        self.resume = resume
        self.forkSession = forkSession
        self.maxTurns = maxTurns
        self.maxBudgetUSD = maxBudgetUSD
        self.model = model
        self.fallbackModel = fallbackModel
        self.betas = betas
        self.mcpServers = mcpServers
        self.strictMcpConfig = strictMcpConfig
        self.hooks = hooks
        self.includePartialMessages = includePartialMessages
        self.settings = settings
        self.settingSources = settingSources
        self.sandbox = sandbox
        self.sandboxPermissions = sandboxPermissions
        self.agents = agents
        self.outputFormat = outputFormat
        self.enableFileCheckpointing = enableFileCheckpointing
        self.maxThinkingTokens = maxThinkingTokens
        self.plugins = plugins
        self.user = user
        self.stderrCallback = stderrCallback
        self.maxBufferSize = maxBufferSize
        self.extraArgs = extraArgs
        self.additionalDirectories = additionalDirectories
    }
}

// MARK: - Tools Configuration

/// Tools configuration - preset or explicit list.
public enum ToolsConfig: Sendable {
    /// Use a tools preset
    case preset(ToolsPreset)

    /// Explicit list of tool names
    case list([String])
}

/// System prompt configuration - preset or custom.
public enum SystemPromptConfig: Sendable {
    /// Use a system prompt preset
    case preset(SystemPromptPreset)

    /// Custom system prompt string
    case custom(String)
}
