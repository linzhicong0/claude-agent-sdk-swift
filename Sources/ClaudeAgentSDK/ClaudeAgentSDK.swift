// MARK: - Claude Agent SDK for Swift
//
// A Swift SDK for interacting with the Claude Code CLI.
// Provides programmatic access to Claude via subprocess communication.

@_exported import Foundation

// MARK: - Public API

// Query function
public let claudeQuery = query

// Re-export all public types
// Messages
public typealias ClaudeMessage = Message
public typealias ClaudeUserMessage = UserMessage
public typealias ClaudeAssistantMessage = AssistantMessage
public typealias ClaudeSystemMessage = SystemMessage
public typealias ClaudeResultMessage = ResultMessage
public typealias ClaudeStreamEvent = StreamEvent

// Content blocks
public typealias ClaudeTextBlock = TextBlock
public typealias ClaudeThinkingBlock = ThinkingBlock
public typealias ClaudeToolUseBlock = ToolUseBlock
public typealias ClaudeToolResultBlock = ToolResultBlock

// Options
public typealias ClaudeOptions = ClaudeAgentOptions

// Client
public typealias ClaudeClient = ClaudeSDKClient

// MCP Server
public typealias ClaudeMCPServer = SDKMCPServer
public typealias ClaudeMCPTool = MCPTool
public typealias ClaudeMCPToolResult = MCPToolResult
