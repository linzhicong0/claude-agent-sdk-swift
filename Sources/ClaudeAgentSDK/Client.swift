// MARK: - Public API
//
// This file defines the public API for the Claude Agent SDK.
// It provides both a simple one-shot query function and a streaming client.
//

import Foundation

// MARK: - Query Function

/// Execute a simple one-shot query to Claude.
///
/// This is the simplest way to interact with Claude. It spawns a CLI process,
/// sends the prompt, and streams messages as they arrive. The function returns
/// an `AsyncThrowingStream` that yields messages until the conversation completes.
///
/// For more complex interactions (tool permission callbacks, hooks, multi-turn),
/// use ``ClaudeSDKClient`` instead.
///
/// ## Example
///
/// ```swift
/// let options = ClaudeAgentOptions(model: "claude-sonnet-4-20250514")
///
/// for try await message in query(prompt: "Hello Claude!", options: options) {
///     switch message {
///     case .assistant(let msg):
///         print(msg.textContent)
///     case .result(let result):
///         print("Cost: $\(result.totalCostUSD ?? 0)")
///     default:
///         break
///     }
/// }
/// ```
///
/// - Parameters:
///   - prompt: The user prompt to send to Claude
///   - options: Configuration options for the SDK
/// - Returns: An async stream of messages from Claude
/// - Throws: ``ClaudeSDKError`` if the query fails
public func query(
    prompt: String,
    options: ClaudeAgentOptions = ClaudeAgentOptions()
) -> AsyncThrowingStream<Message, Error> {

    // Validate options
    if options.canUseTool != nil {
        return AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: ClaudeSDKError.configurationError(
                    reason:
                        "canUseTool callback requires streaming mode. Use ClaudeSDKClient instead."
                ))
        }
    }

    return AsyncThrowingStream { continuation in
        Task {
            do {
                let transport = SubprocessCLITransport(
                    prompt: .text(prompt),
                    options: options,
                    isStreamingMode: false
                )

                // Connect to CLI
                try await transport.connect()

                // Ensure cleanup on exit
                defer {
                    Task {
                        await transport.close()
                    }
                }

                // Read and parse messages
                for try await data in await transport.readMessages() {
                    // Skip control messages in simple mode
                    if isControlMessage(data) {
                        continue
                    }

                    let message = try MessageParser.parse(data)
                    continuation.yield(message)
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

// MARK: - ClaudeSDKClient

/// A streaming client for bidirectional communication with Claude.
///
/// Use this client when you need:
/// - Tool permission callbacks (``ClaudeAgentOptions/canUseTool``)
/// - Lifecycle hooks (``ClaudeAgentOptions/hooks``)
/// - Multi-turn conversations
/// - SDK MCP servers (in-process tools)
/// - Dynamic model switching (``setModel(_:)``)
/// - Dynamic permission mode changes (``setPermissionMode(_:)``)
/// - File checkpointing and rewind (``rewindFiles(to:)``)
///
/// ## Basic Usage
///
/// ```swift
/// let client = ClaudeSDKClient(options: options)
/// try await client.connect()
/// defer { Task { await client.close() } }
///
/// try await client.query(prompt: "Hello!")
///
/// for try await message in client.receiveMessages() {
///     print(message)
/// }
/// ```
///
/// ## Multi-turn Conversation
///
/// ```swift
/// let client = ClaudeSDKClient(options: options)
/// try await client.connect()
///
/// // First turn
/// try await client.query(prompt: "What is 2+2?")
/// for try await message in client.receiveUntilResult() {
///     if case .assistant(let msg) = message {
///         print(msg.textContent)
///     }
/// }
///
/// // Second turn
/// try await client.query(prompt: "What about 3+3?")
/// for try await message in client.receiveUntilResult() {
///     if case .assistant(let msg) = message {
///         print(msg.textContent)
///     }
/// }
///
/// await client.close()
/// ```
public actor ClaudeSDKClient {

    // MARK: - Properties

    private let options: ClaudeAgentOptions
    private var transport: SubprocessCLITransport?
    private var controlProtocol: ControlProtocol?
    private var messageStream: AsyncThrowingStream<[String: Any], Error>?
    private var isConnected = false
    private var readTask: Task<Void, Never>?
    private var initInfo: [String: Any]?

    /// Message channel for filtered SDK messages
    private var messageChannel: AsyncStream<Message>.Continuation?
    private var pendingMessages: [Message] = []

    // MARK: - Initialization

    /// Create a new Claude SDK client.
    ///
    /// The client is not connected after initialization. Call ``connect()``
    /// before sending queries.
    ///
    /// - Parameter options: Configuration options for the SDK
    public init(options: ClaudeAgentOptions = ClaudeAgentOptions()) {
        self.options = options
    }

    // MARK: - Connection

    /// Connect to the Claude CLI and initialize the control protocol.
    ///
    /// This must be called before sending queries. The connection establishes
    /// a bidirectional communication channel with the CLI process.
    ///
    /// - Throws: ``ClaudeSDKError/connectionFailed(reason:)`` if connection fails
    /// - Throws: ``ClaudeSDKError/cliNotFound(searchedPaths:)`` if CLI is not installed
    public func connect() async throws {
        guard !isConnected else {
            throw ClaudeSDKError.configurationError(reason: "Already connected")
        }

        // Create transport in streaming mode
        let transport = SubprocessCLITransport(
            prompt: nil,
            options: options,
            isStreamingMode: true
        )

        try await transport.connect()
        self.transport = transport

        // Create control protocol handler
        let protocol_ = ControlProtocol(transport: transport, options: options)
        self.controlProtocol = protocol_

        // Initialize control protocol
        // The protocol's sendControlRequest handles reading responses internally
        self.initInfo = try await protocol_.initialize()

        isConnected = true
    }

    // MARK: - Querying

    /// Send a user query to Claude.
    ///
    /// The query is sent to the CLI and responses will be available through
    /// ``receiveMessages()`` or ``receiveUntilResult()``.
    ///
    /// - Parameter prompt: The user prompt to send
    /// - Throws: ``ClaudeSDKError/configurationError(reason:)`` if not connected
    public func query(prompt: String) async throws {
        guard let transport = transport, isConnected else {
            throw ClaudeSDKError.configurationError(reason: "Not connected. Call connect() first.")
        }

        let userMessage: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": prompt,
            ],
            "session_id": "default",
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: userMessage)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ClaudeSDKError.writeError(reason: "Failed to serialize user message")
        }

        try await transport.write(jsonString)
    }

    /// Receive messages from Claude.
    ///
    /// Returns an async stream of all messages. This stream continues
    /// indefinitely until the client is closed or an error occurs.
    /// For single-turn interactions, use ``receiveUntilResult()`` instead.
    ///
    /// - Returns: An async stream of messages
    public nonisolated func receiveMessages() -> AsyncThrowingStream<Message, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let transport = await self.transport,
                        let protocol_ = await self.controlProtocol
                    else {
                        continuation.finish(
                            throwing: ClaudeSDKError.configurationError(reason: "Not connected"))
                        return
                    }

                    // First, yield any messages that were buffered during initialization
                    let buffered = await protocol_.drainBufferedMessages()
                    for data in buffered {
                        if let sdkMessage = try await protocol_.routeMessage(data) {
                            let message = try MessageParser.parse(sdkMessage)
                            continuation.yield(message)
                        }
                    }

                    for try await data in await transport.readMessages() {
                        // Route through control protocol
                        if let sdkMessage = try await protocol_.routeMessage(data) {
                            let message = try MessageParser.parse(sdkMessage)
                            continuation.yield(message)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Receive messages until a result message is received.
    ///
    /// This is useful for single-turn interactions where you want to
    /// process all messages until the conversation turn completes.
    /// The result message is included in the output.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await client.query(prompt: "Hello!")
    ///
    /// for try await message in client.receiveUntilResult() {
    ///     switch message {
    ///     case .assistant(let msg):
    ///         print(msg.textContent)
    ///     case .result(let result):
    ///         print("Completed with \(result.numTurns) turns")
    ///     default:
    ///         break
    ///     }
    /// }
    /// ```
    ///
    /// - Returns: An async stream of messages that ends after a result message
    public nonisolated func receiveUntilResult() -> AsyncThrowingStream<Message, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let transport = await self.transport,
                        let protocol_ = await self.controlProtocol
                    else {
                        continuation.finish(
                            throwing: ClaudeSDKError.configurationError(reason: "Not connected"))
                        return
                    }

                    // First, yield any messages that were buffered during initialization
                    let buffered = await protocol_.drainBufferedMessages()
                    for data in buffered {
                        if let sdkMessage = try await protocol_.routeMessage(data) {
                            let message = try MessageParser.parse(sdkMessage)
                            continuation.yield(message)

                            // Stop after result message
                            if case .result = message {
                                continuation.finish()
                                return
                            }
                        }
                    }

                    for try await data in await transport.readMessages() {
                        // Route through control protocol
                        if let sdkMessage = try await protocol_.routeMessage(data) {
                            let message = try MessageParser.parse(sdkMessage)
                            continuation.yield(message)

                            // Stop after result message
                            if case .result = message {
                                break
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Initialization Info

    /// Get the initialization information from the control protocol.
    ///
    /// This contains information about the session, capabilities, and
    /// configuration that was established during ``connect()``.
    ///
    /// - Returns: The initialization info dictionary, or nil if not connected
    public func getInitInfo() -> [String: Any]? {
        return initInfo
    }

    // MARK: - Control Protocol Methods

    /// Interrupt the current operation.
    ///
    /// Sends an interrupt signal to stop the current conversation turn.
    /// This is useful for canceling long-running operations.
    ///
    /// - Throws: ``ClaudeSDKError/configurationError(reason:)`` if not connected
    public func interrupt() async throws {
        guard let protocol_ = controlProtocol else {
            throw ClaudeSDKError.configurationError(reason: "Not connected")
        }
        try await protocol_.interrupt()
    }

    /// Change the model mid-conversation.
    ///
    /// Dynamically switch to a different Claude model. This takes effect
    /// for subsequent messages in the conversation.
    ///
    /// - Parameter model: The new model identifier (e.g., "claude-opus-4-20250514")
    /// - Throws: ``ClaudeSDKError/configurationError(reason:)`` if not connected
    public func setModel(_ model: String) async throws {
        guard let protocol_ = controlProtocol else {
            throw ClaudeSDKError.configurationError(reason: "Not connected")
        }
        try await protocol_.setModel(model)
    }

    /// Change the permission mode dynamically.
    ///
    /// Adjust the permission mode for tool execution. This affects how
    /// the CLI handles permission prompts for dangerous operations.
    ///
    /// - Parameter mode: The new permission mode
    /// - Throws: ``ClaudeSDKError/configurationError(reason:)`` if not connected
    public func setPermissionMode(_ mode: PermissionMode) async throws {
        guard let protocol_ = controlProtocol else {
            throw ClaudeSDKError.configurationError(reason: "Not connected")
        }
        try await protocol_.setPermissionMode(mode)
    }

    /// Rewind files to a checkpoint.
    ///
    /// When file checkpointing is enabled, this restores files to the state
    /// they were in at the specified checkpoint. Checkpoints are created
    /// automatically for user messages with UUIDs.
    ///
    /// - Parameter checkpointId: The checkpoint UUID to rewind to
    /// - Throws: ``ClaudeSDKError/configurationError(reason:)`` if not connected
    public func rewindFiles(to checkpointId: String) async throws {
        guard let protocol_ = controlProtocol else {
            throw ClaudeSDKError.configurationError(reason: "Not connected")
        }
        try await protocol_.rewindFiles(to: checkpointId)
    }

    /// Get MCP server connection status.
    ///
    /// Query the current status of all MCP server connections.
    ///
    /// - Returns: A dictionary containing MCP status information
    /// - Throws: ``ClaudeSDKError/configurationError(reason:)`` if not connected
    public func getMcpStatus() async throws -> [String: Any] {
        guard let protocol_ = controlProtocol else {
            throw ClaudeSDKError.configurationError(reason: "Not connected")
        }
        return try await protocol_.getMcpStatus()
    }

    /// Get server initialization information.
    ///
    /// Returns information about the connected CLI server including
    /// supported commands, output styles, and capabilities.
    ///
    /// - Returns: The server info dictionary, or nil if not connected
    public func getServerInfo() async -> [String: Any]? {
        return initInfo
    }

    // MARK: - Cleanup

    /// Close the client and cleanup resources.
    ///
    /// This terminates the CLI process and releases all resources.
    /// The client cannot be reused after closing.
    public func close() async {
        readTask?.cancel()
        readTask = nil

        if let transport = transport {
            await transport.close()
        }

        transport = nil
        controlProtocol = nil
        initInfo = nil
        isConnected = false
    }

    /// Check if the client is connected.
    public var connected: Bool {
        isConnected
    }
}

// MARK: - Convenience Extensions

extension ClaudeSDKClient {

    /// Connect, query, receive all messages until result, and close.
    ///
    /// This is a convenience method for simple single-turn interactions
    /// that still need streaming mode features (like SDK MCP servers).
    ///
    /// ## Example
    ///
    /// ```swift
    /// let messages = try await client.runQuery(prompt: "What is 2+2?")
    /// for message in messages {
    ///     if case .assistant(let msg) = message {
    ///         print(msg.textContent)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter prompt: The user prompt
    /// - Returns: All messages from the conversation
    public func runQuery(prompt: String) async throws -> [Message] {
        try await connect()
        defer { Task { await close() } }

        try await query(prompt: prompt)

        var messages: [Message] = []
        for try await message in receiveUntilResult() {
            messages.append(message)
        }

        return messages
    }

    /// Get the last result message from an array of messages.
    ///
    /// - Parameter messages: Array of messages to search
    /// - Returns: The result message, or nil if none found
    public static func getResult(from messages: [Message]) -> ResultMessage? {
        for message in messages.reversed() {
            if case .result(let result) = message {
                return result
            }
        }
        return nil
    }

    /// Get all assistant messages from an array of messages.
    ///
    /// - Parameter messages: Array of messages to filter
    /// - Returns: Array of assistant messages
    public static func getAssistantMessages(from messages: [Message]) -> [AssistantMessage] {
        messages.compactMap { message in
            if case .assistant(let msg) = message {
                return msg
            }
            return nil
        }
    }

    /// Get the combined text content from all assistant messages.
    ///
    /// - Parameter messages: Array of messages to process
    /// - Returns: Combined text content
    public static func getTextContent(from messages: [Message]) -> String {
        getAssistantMessages(from: messages)
            .map { $0.textContent }
            .joined()
    }
}

// MARK: - Type Aliases

/// Type alias for the query function signature.
public typealias ClaudeQuery = (String, ClaudeAgentOptions) -> AsyncThrowingStream<Message, Error>
