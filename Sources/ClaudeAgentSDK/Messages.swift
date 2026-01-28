// MARK: - Message Types
//
// This file defines all message types used in the Claude Agent SDK.
// Messages are the primary way to communicate with Claude through the SDK.
//

import Foundation

// MARK: - Message Union Type

/// A message from the Claude SDK.
///
/// This is the main union type representing all possible message types
/// that can be received from the Claude CLI. Messages flow through the
/// SDK as a stream, with each message representing a different event
/// in the conversation.
///
/// ## Topics
///
/// ### Message Types
/// - ``user(_:)`` - Messages from the user
/// - ``assistant(_:)`` - Responses from Claude
/// - ``system(_:)`` - System-level events
/// - ``result(_:)`` - Final result of a conversation turn
/// - ``streamEvent(_:)`` - Partial streaming events
///
/// ## Example
/// ```swift
/// for try await message in query(prompt: "Hello!", options: options) {
///     switch message {
///     case .user(let msg):
///         print("User: \(msg.content.text)")
///     case .assistant(let msg):
///         print("Claude: \(msg.textContent)")
///     case .result(let result):
///         print("Cost: $\(result.totalCostUSD ?? 0)")
///     default:
///         break
///     }
/// }
/// ```
public enum Message: Sendable {
    /// A message from the user
    case user(UserMessage)

    /// A response from Claude
    case assistant(AssistantMessage)

    /// A system-level event (e.g., initialization)
    case system(SystemMessage)

    /// The final result of a conversation turn
    case result(ResultMessage)

    /// A partial streaming event (when `includePartialMessages` is true)
    case streamEvent(StreamEvent)
}

// MARK: - User Message

/// A message from the user in the conversation.
///
/// User messages represent input from the human user or tool results
/// being sent back to Claude.
///
/// ## Properties
/// - `content`: The message content (text or structured blocks)
/// - `uuid`: Optional unique identifier for checkpointing
/// - `parentToolUseId`: If this is a tool result, the ID of the tool use
public struct UserMessage: Sendable, Equatable {
    /// The content of the user message
    public let content: UserContent

    /// Optional unique identifier for file checkpointing
    public let uuid: String?

    /// If this message is a tool result, the ID of the corresponding tool use
    public let parentToolUseId: String?

    /// Create a new user message
    /// - Parameters:
    ///   - content: The message content
    ///   - uuid: Optional unique identifier
    ///   - parentToolUseId: Optional parent tool use ID for tool results
    public init(content: UserContent, uuid: String? = nil, parentToolUseId: String? = nil) {
        self.content = content
        self.uuid = uuid
        self.parentToolUseId = parentToolUseId
    }
}

// MARK: - User Content

/// The content of a user message.
///
/// User content can be either plain text or a structured array of content blocks.
public enum UserContent: Sendable, Equatable {
    /// Plain text content
    case text(String)

    /// Structured content blocks
    case blocks([ContentBlock])
}

// MARK: - Assistant Message

/// A response message from Claude.
///
/// Assistant messages contain Claude's responses, which may include
/// text, thinking blocks, and tool use requests.
///
/// ## Properties
/// - `content`: Array of content blocks (text, thinking, tool_use, tool_result)
/// - `model`: The model identifier that generated this response
/// - `parentToolUseId`: For nested tool contexts
/// - `error`: Error information if the response failed
///
/// ## Example
/// ```swift
/// if case .assistant(let msg) = message {
///     print("Response: \(msg.textContent)")
///     for tool in msg.toolUses {
///         print("Tool: \(tool.name)")
///     }
/// }
/// ```
public struct AssistantMessage: Sendable, Equatable {
    /// The content blocks in this message
    public let content: [ContentBlock]

    /// The model that generated this response
    public let model: String

    /// For nested tool contexts, the parent tool use ID
    public let parentToolUseId: String?

    /// Error information if the response failed
    public let error: AssistantMessageError?

    /// Create a new assistant message
    /// - Parameters:
    ///   - content: Array of content blocks
    ///   - model: Model identifier
    ///   - parentToolUseId: Optional parent tool use ID
    ///   - error: Optional error information
    public init(
        content: [ContentBlock], model: String, parentToolUseId: String? = nil,
        error: AssistantMessageError? = nil
    ) {
        self.content = content
        self.model = model
        self.parentToolUseId = parentToolUseId
        self.error = error
    }
}

// MARK: - Assistant Message Error

/// Error information attached to an assistant message.
///
/// This indicates that Claude encountered an error while processing
/// the request. Common error types include rate limiting, authentication
/// failures, and server errors.
public struct AssistantMessageError: Sendable, Equatable, Codable {
    /// The error type (e.g., "rate_limit", "authentication_failed", "server_error")
    public let type: String

    /// Human-readable error message
    public let message: String

    /// Create a new assistant message error
    /// - Parameters:
    ///   - type: The error type identifier
    ///   - message: Human-readable error description
    public init(type: String, message: String) {
        self.type = type
        self.message = message
    }
}

// MARK: - System Message

/// A system-level message representing internal SDK events.
///
/// System messages are used for initialization, configuration changes,
/// and other internal events. The `subtype` field indicates the specific
/// event type.
public struct SystemMessage: Sendable, Equatable {
    /// The type of system event (e.g., "init")
    public let subtype: String

    /// Additional data associated with the event
    public let data: [String: AnyCodable]

    /// Create a new system message
    /// - Parameters:
    ///   - subtype: The system event type
    ///   - data: Associated event data
    public init(subtype: String, data: [String: AnyCodable]) {
        self.subtype = subtype
        self.data = data
    }
}

// MARK: - Result Subtype

/// The subtype of a result message indicating how the conversation ended.
public enum ResultSubtype: String, Sendable, Codable {
    /// The conversation completed successfully (API variant)
    case success

    /// The conversation completed successfully (legacy)
    case done

    /// The conversation ended with an error
    case error

    /// The conversation was interrupted by the user
    case interrupted
}

// MARK: - Result Message

/// The final result message at the end of a conversation turn.
///
/// Result messages contain summary information about the conversation,
/// including timing, costs, and token usage.
///
/// ## Properties
/// - `subtype`: How the conversation ended (done, error, interrupted)
/// - `durationMs`: Total wall-clock duration in milliseconds
/// - `durationApiMs`: Time spent in API calls
/// - `isError`: Whether an error occurred
/// - `numTurns`: Number of conversation turns
/// - `sessionId`: The session identifier
/// - `totalCostUSD`: Estimated cost in USD
/// - `usage`: Detailed token usage statistics
/// - `structuredOutput`: Parsed JSON output (if using outputFormat)
public struct ResultMessage: Sendable, Equatable {
    /// How the conversation ended
    public let subtype: ResultSubtype

    /// Total wall-clock duration in milliseconds
    public let durationMs: Int

    /// Time spent in API calls in milliseconds
    public let durationApiMs: Int

    /// Whether an error occurred
    public let isError: Bool

    /// Number of conversation turns
    public let numTurns: Int

    /// The session identifier
    public let sessionId: String

    /// Estimated cost in USD (may be nil)
    public let totalCostUSD: Double?

    /// Detailed token usage statistics
    public let usage: [String: AnyCodable]?

    /// Parsed structured output when using JSON schema
    public let structuredOutput: AnyCodable?

    /// Create a new result message
    public init(
        subtype: ResultSubtype,
        durationMs: Int,
        durationApiMs: Int,
        isError: Bool,
        numTurns: Int,
        sessionId: String,
        totalCostUSD: Double?,
        usage: [String: AnyCodable]?,
        structuredOutput: AnyCodable? = nil
    ) {
        self.subtype = subtype
        self.durationMs = durationMs
        self.durationApiMs = durationApiMs
        self.isError = isError
        self.numTurns = numTurns
        self.sessionId = sessionId
        self.totalCostUSD = totalCostUSD
        self.usage = usage
        self.structuredOutput = structuredOutput
    }
}

// MARK: - Stream Event

/// A streaming event containing raw Anthropic API data.
///
/// Stream events are emitted when `includePartialMessages` is enabled,
/// providing real-time updates as Claude generates its response.
///
/// ## Event Types
/// - `message_start`: Beginning of a message
/// - `content_block_start`: Beginning of a content block
/// - `content_block_delta`: Incremental content update
/// - `content_block_stop`: End of a content block
/// - `message_stop`: End of a message
public struct StreamEvent: Sendable, Equatable {
    /// Unique identifier for this event
    public let uuid: String

    /// The session identifier
    public let sessionId: String

    /// The raw Anthropic API event data
    public let event: [String: AnyCodable]

    /// For nested tool contexts, the parent tool use ID
    public let parentToolUseId: String?

    /// Create a new stream event
    /// - Parameters:
    ///   - uuid: Unique event identifier
    ///   - sessionId: Session identifier
    ///   - event: Raw API event data
    ///   - parentToolUseId: Optional parent tool use ID
    public init(
        uuid: String, sessionId: String, event: [String: AnyCodable], parentToolUseId: String? = nil
    ) {
        self.uuid = uuid
        self.sessionId = sessionId
        self.event = event
        self.parentToolUseId = parentToolUseId
    }
}

// MARK: - Message Equatable

extension Message: Equatable {
    public static func == (lhs: Message, rhs: Message) -> Bool {
        switch (lhs, rhs) {
        case (.user(let l), .user(let r)): return l == r
        case (.assistant(let l), .assistant(let r)): return l == r
        case (.system(let l), .system(let r)): return l == r
        case (.result(let l), .result(let r)): return l == r
        case (.streamEvent(let l), .streamEvent(let r)): return l == r
        default: return false
        }
    }
}

// MARK: - Message Codable

extension Message: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "user":
            self = .user(try UserMessage(from: decoder))
        case "assistant":
            self = .assistant(try AssistantMessage(from: decoder))
        case "system":
            self = .system(try SystemMessage(from: decoder))
        case "result":
            self = .result(try ResultMessage(from: decoder))
        case "stream_event":
            self = .streamEvent(try StreamEvent(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown message type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .user(let msg):
            try container.encode("user", forKey: .type)
            try msg.encode(to: encoder)
        case .assistant(let msg):
            try container.encode("assistant", forKey: .type)
            try msg.encode(to: encoder)
        case .system(let msg):
            try container.encode("system", forKey: .type)
            try msg.encode(to: encoder)
        case .result(let msg):
            try container.encode("result", forKey: .type)
            try msg.encode(to: encoder)
        case .streamEvent(let event):
            try container.encode("stream_event", forKey: .type)
            try event.encode(to: encoder)
        }
    }
}

// MARK: - UserMessage Codable

extension UserMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case message
        case uuid
        case parentToolUseId = "parent_tool_use_id"
    }

    private enum MessageKeys: String, CodingKey {
        case content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let messageContainer = try container.nestedContainer(
            keyedBy: MessageKeys.self, forKey: .message)

        // Try string first, then blocks
        if let text = try? messageContainer.decode(String.self, forKey: .content) {
            content = .text(text)
        } else {
            content = .blocks(try messageContainer.decode([ContentBlock].self, forKey: .content))
        }

        uuid = try container.decodeIfPresent(String.self, forKey: .uuid)
        parentToolUseId = try container.decodeIfPresent(String.self, forKey: .parentToolUseId)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var messageContainer = container.nestedContainer(
            keyedBy: MessageKeys.self, forKey: .message)

        switch content {
        case .text(let text):
            try messageContainer.encode(text, forKey: .content)
        case .blocks(let blocks):
            try messageContainer.encode(blocks, forKey: .content)
        }

        try container.encodeIfPresent(uuid, forKey: .uuid)
        try container.encodeIfPresent(parentToolUseId, forKey: .parentToolUseId)
    }
}

// MARK: - UserContent Codable

extension UserContent: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            self = .blocks(try container.decode([ContentBlock].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }
}

// MARK: - AssistantMessage Codable

extension AssistantMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case message
        case model
        case parentToolUseId = "parent_tool_use_id"
        case error
    }

    private enum MessageKeys: String, CodingKey {
        case content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let messageContainer = try container.nestedContainer(
            keyedBy: MessageKeys.self, forKey: .message)

        content = try messageContainer.decode([ContentBlock].self, forKey: .content)
        model = try container.decode(String.self, forKey: .model)
        parentToolUseId = try container.decodeIfPresent(String.self, forKey: .parentToolUseId)
        error = try container.decodeIfPresent(AssistantMessageError.self, forKey: .error)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var messageContainer = container.nestedContainer(
            keyedBy: MessageKeys.self, forKey: .message)

        try messageContainer.encode(content, forKey: .content)
        try container.encode(model, forKey: .model)
        try container.encodeIfPresent(parentToolUseId, forKey: .parentToolUseId)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

// MARK: - SystemMessage Codable

extension SystemMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case subtype
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subtype = try container.decode(String.self, forKey: .subtype)

        // Decode remaining keys as data
        let allContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        var data: [String: AnyCodable] = [:]
        for key in allContainer.allKeys
        where key.stringValue != "type" && key.stringValue != "subtype" {
            data[key.stringValue] = try allContainer.decode(AnyCodable.self, forKey: key)
        }
        self.data = data
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(subtype, forKey: .subtype)

        var dataContainer = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in data {
            try dataContainer.encode(value, forKey: DynamicCodingKey(stringValue: key)!)
        }
    }
}

// MARK: - ResultMessage Codable

extension ResultMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case subtype
        case durationMs = "duration_ms"
        case durationApiMs = "duration_api_ms"
        case isError = "is_error"
        case numTurns = "num_turns"
        case sessionId = "session_id"
        case totalCostUSD = "total_cost_usd"
        case usage
        case structuredOutput = "structured_output"
    }
}

// MARK: - StreamEvent Codable

extension StreamEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case uuid
        case sessionId = "session_id"
        case event
        case parentToolUseId = "parent_tool_use_id"
    }
}

// MARK: - Dynamic Coding Key

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

// MARK: - Helper Extensions

extension AssistantMessage {
    /// Extract all text content from the message.
    ///
    /// This concatenates all text blocks in the message, ignoring
    /// thinking blocks and tool use blocks.
    public var textContent: String {
        content.compactMap { block in
            if case .text(let text) = block {
                return text.text
            }
            return nil
        }.joined()
    }

    /// Get all tool use blocks from the message.
    ///
    /// Returns an array of tool use requests that Claude is making.
    public var toolUses: [ToolUseBlock] {
        content.compactMap { block in
            if case .toolUse(let tool) = block {
                return tool
            }
            return nil
        }
    }

    /// Get all thinking blocks from the message.
    ///
    /// Returns an array of thinking blocks showing Claude's reasoning.
    public var thinkingBlocks: [ThinkingBlock] {
        content.compactMap { block in
            if case .thinking(let thinking) = block {
                return thinking
            }
            return nil
        }
    }
}

extension UserContent {
    /// Get the text representation of the content.
    ///
    /// For text content, returns the string directly.
    /// For block content, concatenates all text blocks.
    public var text: String {
        switch self {
        case .text(let str):
            return str
        case .blocks(let blocks):
            return blocks.compactMap { block in
                if case .text(let text) = block {
                    return text.text
                }
                return nil
            }.joined()
        }
    }
}

extension ResultMessage {
    /// The duration in seconds.
    public var durationSeconds: Double {
        Double(durationMs) / 1000.0
    }

    /// The API duration in seconds.
    public var durationApiSeconds: Double {
        Double(durationApiMs) / 1000.0
    }

    /// Get input token count from usage.
    public var inputTokens: Int? {
        usage?["input_tokens"]?.intValue
    }

    /// Get output token count from usage.
    public var outputTokens: Int? {
        usage?["output_tokens"]?.intValue
    }
}
