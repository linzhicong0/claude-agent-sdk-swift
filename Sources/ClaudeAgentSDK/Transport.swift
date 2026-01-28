// MARK: - Transport Protocol & CLI Transport
//
// This file defines the transport abstraction layer for the Claude Agent SDK.
// The transport layer handles communication between the SDK and the Claude CLI.
//

import Foundation

// MARK: - Transport Protocol

/// Protocol for implementing custom transport mechanisms.
///
/// The transport layer is responsible for spawning and communicating with the Claude CLI process.
/// The default implementation uses ``SubprocessCLITransport`` which communicates via JSON-RPC over stdio.
///
/// ## Custom Transport
///
/// You can implement a custom transport for scenarios like:
/// - Remote CLI execution over SSH
/// - Container-based execution
/// - Mock transport for testing
///
/// ```swift
/// actor RemoteTransport: TransportProtocol {
///     func connect() async throws {
///         // Connect to remote CLI
///     }
///
///     func write(_ message: String) async throws {
///         // Send message to remote CLI
///     }
///
///     func readMessages() -> AsyncThrowingStream<[String: Any], Error> {
///         // Read messages from remote CLI
///     }
///
///     func close() async {
///         // Disconnect from remote CLI
///     }
/// }
/// ```
public protocol TransportProtocol: Actor {
    /// Start the transport connection.
    ///
    /// This method should establish the connection to the CLI process
    /// and begin listening for incoming messages.
    func connect() async throws

    /// Write a message to the transport.
    ///
    /// - Parameter message: The JSON-RPC message to send.
    func write(_ message: String) async throws

    /// Read messages from the transport as an async stream.
    ///
    /// - Returns: An async throwing stream of parsed JSON messages.
    func readMessages() -> AsyncThrowingStream<[String: Any], Error>

    /// Close the transport connection.
    ///
    /// This method should cleanly terminate the CLI process and
    /// release any resources.
    func close() async

    /// Whether the transport is currently connected/running.
    var isRunning: Bool { get }
}

// MARK: - Mock Transport (for testing)

/// Mock transport for unit testing.
///
/// This transport doesn't spawn a real process - instead it allows
/// injecting responses for testing purposes.
///
/// ```swift
/// let mock = MockCLITransport()
/// mock.queueResponse(["type": "system", "message": "init"])
/// mock.queueResponse(["type": "result", "subtype": "success"])
///
/// try await mock.connect()
/// for try await message in mock.readMessages() {
///     // Process mock messages
/// }
/// ```
public actor MockCLITransport: TransportProtocol {
    /// Queued responses to return when readMessages() is called.
    private var responses: [[String: Any]] = []

    /// Messages sent via write().
    public private(set) var sentMessages: [String] = []

    /// Whether connect() was called.
    public private(set) var wasConnected = false

    /// Whether close() was called.
    public private(set) var wasClosed = false

    /// Simulated error to throw on connect.
    public var connectError: Error?

    /// Simulated error to throw on write.
    public var writeError: Error?

    /// Whether the transport is "running".
    public var isRunning: Bool {
        wasConnected && !wasClosed
    }

    public init() {}

    /// Queue a response to be returned by readMessages().
    public func queueResponse(_ response: [String: Any]) {
        responses.append(response)
    }

    /// Queue multiple responses.
    public func queueResponses(_ responses: [[String: Any]]) {
        self.responses.append(contentsOf: responses)
    }

    public func connect() async throws {
        if let error = connectError {
            throw error
        }
        wasConnected = true
    }

    public func write(_ message: String) async throws {
        if let error = writeError {
            throw error
        }
        sentMessages.append(message)
    }

    public func readMessages() -> AsyncThrowingStream<[String: Any], Error> {
        let responses = self.responses
        return AsyncThrowingStream { continuation in
            for response in responses {
                continuation.yield(response)
            }
            continuation.finish()
        }
    }

    public func close() async {
        wasClosed = true
    }

    /// Clear all state for reuse.
    public func reset() {
        responses.removeAll()
        sentMessages.removeAll()
        wasConnected = false
        wasClosed = false
        connectError = nil
        writeError = nil
    }
}

// MARK: - Constants

/// Default maximum buffer size (1MB)
let defaultMaxBufferSize = 1_048_576

/// Command length limit (Windows compatibility)
let cmdLengthLimit = 8000

/// SDK version for entrypoint identification
let sdkVersion = "1.0.0"

// MARK: - Subprocess CLI Transport

/// Transport layer for communicating with Claude Code CLI via subprocess.
///
/// This is the default transport implementation that spawns the Claude CLI
/// as a subprocess and communicates via JSON-RPC messages over stdio.
///
/// ## Usage
///
/// ```swift
/// let transport = SubprocessCLITransport(
///     prompt: .text("Hello Claude!"),
///     options: ClaudeAgentOptions(maxTurns: 5)
/// )
///
/// try await transport.connect()
///
/// for try await message in transport.readMessages() {
///     // Process messages
/// }
///
/// await transport.close()
/// ```
public actor SubprocessCLITransport: TransportProtocol {

    // MARK: - Properties

    private let options: ClaudeAgentOptions
    private let prompt: PromptInput?
    private let isStreamingMode: Bool

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private var stderrTask: Task<Void, Never>?
    private var tempFiles: [URL] = []

    private let maxBufferSize: Int

    // MARK: - Initialization

    public init(prompt: PromptInput?, options: ClaudeAgentOptions, isStreamingMode: Bool = false) {
        self.prompt = prompt
        self.options = options
        self.isStreamingMode = isStreamingMode
        self.maxBufferSize = options.maxBufferSize ?? defaultMaxBufferSize
    }

    // MARK: - CLI Discovery

    /// Find the Claude CLI binary
    private func findCLI() throws -> String {
        var searchedPaths: [String] = []

        // 1. User-specified path
        if let cliPath = options.cliPath {
            searchedPaths.append(cliPath)
            if FileManager.default.isExecutableFile(atPath: cliPath) {
                return cliPath
            }
        }

        // 2. Check bundled CLI (if distributed with SDK)
        let bundledPath = Bundle.main.bundlePath + "/Contents/Resources/claude"
        searchedPaths.append(bundledPath)
        if FileManager.default.isExecutableFile(atPath: bundledPath) {
            return bundledPath
        }

        // 3. System PATH via `which`
        if let pathResult = try? runWhich("claude") {
            return pathResult
        }
        searchedPaths.append("which claude")

        // 4. Common installation locations
        let commonPaths = [
            "\(NSHomeDirectory())/.npm-global/bin/claude",
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
            "\(NSHomeDirectory())/node_modules/.bin/claude",
            "/opt/homebrew/bin/claude",
        ]

        for path in commonPaths {
            searchedPaths.append(path)
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        throw ClaudeSDKError.cliNotFound(searchedPaths: searchedPaths)
    }

    /// Run `which` command to find CLI in PATH
    private func runWhich(_ command: String) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines),
            !path.isEmpty
        else { return nil }

        return path
    }

    // MARK: - Command Building

    /// Build the command line arguments for the CLI
    private func buildArguments() throws -> [String] {
        var args: [String] = []

        // Output format
        args.append(contentsOf: ["--output-format", "stream-json"])
        args.append("--verbose")

        // Input mode
        if isStreamingMode {
            args.append(contentsOf: ["--input-format", "stream-json"])
        }

        // System prompt
        if let systemPrompt = options.systemPrompt {
            let promptValue: String
            switch systemPrompt {
            case .preset(let preset):
                promptValue = preset.rawValue
            case .custom(let custom):
                promptValue = custom
            }
            args.append(contentsOf: ["--system-prompt", promptValue])
        }

        // Tools configuration
        if let tools = options.tools {
            let toolsValue: String
            switch tools {
            case .preset(let preset):
                toolsValue = preset.rawValue
            case .list(let list):
                toolsValue = list.joined(separator: ",")
            }
            args.append(contentsOf: ["--tools", toolsValue])
        }

        // Allowed/disallowed tools
        if !options.allowedTools.isEmpty {
            args.append(contentsOf: ["--allowedTools", options.allowedTools.joined(separator: ",")])
        }
        if !options.disallowedTools.isEmpty {
            args.append(contentsOf: [
                "--disallowedTools", options.disallowedTools.joined(separator: ","),
            ])
        }

        // Permission mode
        if let mode = options.permissionMode {
            args.append(contentsOf: ["--permission-mode", mode.rawValue])
        }

        // Tool permission callback requires stdio
        if options.canUseTool != nil {
            args.append(contentsOf: ["--permission-prompt-tool-name", "stdio"])
        }

        // Conversation settings
        if let maxTurns = options.maxTurns {
            args.append(contentsOf: ["--max-turns", String(maxTurns)])
        }
        if let maxBudget = options.maxBudgetUSD {
            args.append(contentsOf: ["--max-budget-usd", String(maxBudget)])
        }

        // Model
        if let model = options.model {
            args.append(contentsOf: ["--model", model])
        }
        if let fallback = options.fallbackModel {
            args.append(contentsOf: ["--fallback-model", fallback])
        }

        // Session management
        if options.continueConversation {
            args.append("--continue")
        }
        if let resume = options.resume {
            args.append(contentsOf: ["--resume", resume])
        }

        // Partial messages
        if options.includePartialMessages {
            args.append("--include-partial-messages")
        }

        // Settings sources
        if let settings = options.settings {
            args.append(contentsOf: ["--setting-sources", settings])
        }

        // Additional directories
        for dir in options.additionalDirectories {
            args.append(contentsOf: ["--add-dir", dir])
        }

        // MCP servers (external only, SDK servers handled via control protocol)
        let externalMCPConfig = buildExternalMCPConfig()
        if !externalMCPConfig.isEmpty {
            let jsonData = try JSONSerialization.data(withJSONObject: externalMCPConfig)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            args.append(contentsOf: ["--mcp-config", jsonString])
        }

        // Agents
        if let agents = options.agents, !agents.isEmpty {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let agentsData = try encoder.encode(agents)
            let agentsJSON = String(data: agentsData, encoding: .utf8) ?? "{}"

            // Handle long agent configs with temp file
            if agentsJSON.count > cmdLengthLimit {
                let tempFile = try writeTempFile(content: agentsJSON, prefix: "agents")
                args.append(contentsOf: ["--agents", "@\(tempFile.path)"])
            } else {
                args.append(contentsOf: ["--agents", agentsJSON])
            }
        }

        // Structured output (JSON schema)
        if let outputFormat = options.outputFormat {
            let jsonData = try JSONSerialization.data(
                withJSONObject: outputFormat.mapValues { $0.value })
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            args.append(contentsOf: ["--json-schema", jsonString])
        }

        // Extra arguments
        for (key, value) in options.extraArgs {
            if let value = value {
                args.append(contentsOf: ["--\(key)", value])
            } else {
                args.append("--\(key)")
            }
        }

        // Non-streaming mode: add prompt directly
        if !isStreamingMode, case .text(let promptText) = prompt {
            args.append("--print")
            args.append("--")
            args.append(promptText)
        }

        return args
    }

    /// Build external MCP server config (excludes SDK servers)
    private func buildExternalMCPConfig() -> [String: Any] {
        var config: [String: Any] = [:]
        var servers: [String: Any] = [:]

        for (name, serverConfig) in options.mcpServers {
            if case .external(let external) = serverConfig {
                var serverDict: [String: Any] = ["command": external.command]
                if let args = external.args { serverDict["args"] = args }
                if let env = external.env { serverDict["env"] = env }
                if let cwd = external.cwd { serverDict["cwd"] = cwd }
                servers[name] = serverDict
            } else if case .sdkServer(let server) = serverConfig {
                // SDK servers use special "sdk://" transport
                servers[name] = [
                    "command": "sdk://\(server.name)",
                    "transportType": "sdk",
                ]
            }
        }

        if !servers.isEmpty {
            config["mcpServers"] = servers
        }
        return config
    }

    /// Write content to a temporary file
    private func writeTempFile(content: String, prefix: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
        try content.write(to: tempFile, atomically: true, encoding: .utf8)
        tempFiles.append(tempFile)
        return tempFile
    }

    // MARK: - Process Management

    /// Start the CLI process
    public func connect() async throws {
        let cliPath = try findCLI()
        let arguments = try buildArguments()

        // Optional: Check CLI version
        try await checkCLIVersion(cliPath: cliPath)

        // Create pipes
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        // Create process
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cliPath)
        proc.arguments = arguments
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        // Set working directory
        if let cwd = options.cwd {
            guard FileManager.default.fileExists(atPath: cwd) else {
                throw ClaudeSDKError.connectionFailed(
                    reason: "Working directory does not exist: \(cwd)")
            }
            proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        // Set environment
        var environment = ProcessInfo.processInfo.environment
        environment["CLAUDE_CODE_ENTRYPOINT"] = "sdk-swift"
        environment["CLAUDE_AGENT_SDK_VERSION"] = sdkVersion
        if options.enableFileCheckpointing {
            environment["CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING"] = "true"
        }
        for (key, value) in options.env {
            environment[key] = value
        }
        proc.environment = environment

        // Start process
        do {
            try proc.run()
        } catch {
            throw ClaudeSDKError.connectionFailed(
                reason: "Failed to start CLI: \(error.localizedDescription)")
        }

        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        // Start stderr reading if callback provided
        // Note: This runs outside actor isolation to avoid blocking
        if let callback = options.stderrCallback {
            let stderrHandle = stderr.fileHandleForReading
            stderrTask = Task.detached {
                while !Task.isCancelled {
                    let data = stderrHandle.availableData
                    if data.isEmpty {
                        // EOF or closed
                        break
                    }

                    if let line = String(data: data, encoding: .utf8) {
                        callback(line)
                    }
                }
            }
        }

        // Close stdin immediately for non-streaming mode
        if !isStreamingMode {
            try stdin.fileHandleForWriting.close()
        }
    }

    /// Check CLI version compatibility
    private func checkCLIVersion(cliPath: String) async throws {
        // Skip if environment variable set
        if ProcessInfo.processInfo.environment["CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK"] != nil {
            return
        }

        let versionProcess = Process()
        versionProcess.executableURL = URL(fileURLWithPath: cliPath)
        versionProcess.arguments = ["-v"]

        let pipe = Pipe()
        versionProcess.standardOutput = pipe
        versionProcess.standardError = FileHandle.nullDevice

        try versionProcess.run()

        // Wait with timeout
        let timeout: UInt64 = 2_000_000_000  // 2 seconds
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                versionProcess.waitUntilExit()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeout)
                versionProcess.terminate()
            }

            try await group.next()
            group.cancelAll()
        }

        // Parse version (basic check)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let versionString = String(data: data, encoding: .utf8) {
            // Could add version comparison logic here
            _ = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Communication

    /// Write a message to stdin
    public func write(_ message: String) async throws {
        guard let pipe = stdinPipe else {
            throw ClaudeSDKError.writeError(reason: "Stdin pipe not available")
        }

        guard process?.isRunning == true else {
            throw ClaudeSDKError.writeError(reason: "Process not running")
        }

        let data = (message + "\n").data(using: .utf8)!

        do {
            try pipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw ClaudeSDKError.writeError(reason: error.localizedDescription)
        }
    }

    // Track the message reader task to prevent multiple concurrent readers
    private var messageReaderTask: Task<Void, Never>?

    /// Read messages from stdout as an async stream.
    /// Note: Only one consumer should iterate over the stream at a time.
    /// Calling this while another consumer is reading will start a new reader
    /// that may compete for data.
    public func readMessages() -> AsyncThrowingStream<[String: Any], Error> {
        // Cancel any existing reader
        messageReaderTask?.cancel()

        // Capture what we need from actor state
        guard let stdoutHandle = stdoutPipe?.fileHandleForReading else {
            return AsyncThrowingStream { $0.finish() }
        }
        let proc = self.process
        let maxBuffer = self.maxBufferSize
        let stderrHandle = self.stderrPipe?.fileHandleForReading

        let stream = AsyncThrowingStream<[String: Any], Error> { continuation in
            // Run blocking I/O in a detached task to avoid blocking the actor
            let task = Task.detached {
                var buffer = ""

                while !Task.isCancelled {
                    // Read available data - this is blocking!
                    let data = stdoutHandle.availableData

                    if data.isEmpty {
                        // Check if process ended
                        if proc?.isRunning == false {
                            break
                        }
                        // Small delay to prevent busy-waiting
                        try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
                        continue
                    }

                    guard let chunk = String(data: data, encoding: .utf8) else {
                        continue
                    }

                    buffer += chunk

                    // Check buffer size limit
                    if buffer.count > maxBuffer {
                        continuation.finish(
                            throwing: ClaudeSDKError.bufferOverflow(
                                bufferSize: buffer.count, maxSize: maxBuffer))
                        return
                    }

                    // Process complete lines
                    while let newlineIndex = buffer.firstIndex(of: "\n") {
                        let line = String(buffer[..<newlineIndex])
                        buffer = String(buffer[buffer.index(after: newlineIndex)...])

                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { continue }

                        // Try to parse JSON
                        guard let jsonData = trimmed.data(using: .utf8) else { continue }

                        do {
                            if let json = try JSONSerialization.jsonObject(with: jsonData)
                                as? [String: Any]
                            {
                                print()
                                continuation.yield(json)
                            }
                        } catch {
                            // Speculative parsing - might be incomplete JSON
                            if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
                                continuation.finish(
                                    throwing: ClaudeSDKError.jsonDecodeError(
                                        line: trimmed, underlyingError: error))
                                return
                            }
                        }
                    }
                }

                // Check exit code
                if let proc = proc {
                    proc.waitUntilExit()

                    if proc.terminationStatus != 0 {
                        // Read remaining stderr
                        var stderrOutput: String?
                        if let handle = stderrHandle {
                            let data = handle.readDataToEndOfFile()
                            stderrOutput = String(data: data, encoding: .utf8)
                        }

                        continuation.finish(
                            throwing: ClaudeSDKError.processError(
                                exitCode: proc.terminationStatus, stderr: stderrOutput))
                        return
                    }
                }

                continuation.finish()
            }

            // Set up cancellation handler
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }

            // Store the task reference (we can't await in this closure, but we need to track cancellation)
            // The onTermination handler already handles cancellation
        }

        return stream
    }

    /// Set the message reader task (must be called on the actor)
    private func setMessageReaderTask(_ task: Task<Void, Never>) {
        self.messageReaderTask = task
    }

    /// Stop the current message reader if one is active
    public func stopMessageReader() {
        messageReaderTask?.cancel()
        messageReaderTask = nil
    }

    // MARK: - Cleanup

    /// Close the transport and cleanup resources
    public func close() async {
        // Cancel stderr task
        stderrTask?.cancel()
        stderrTask = nil

        // Close stdin
        if let pipe = stdinPipe {
            try? pipe.fileHandleForWriting.close()
        }

        // Terminate process if running
        if let proc = process, proc.isRunning {
            proc.terminate()
            proc.waitUntilExit()
        }

        // Cleanup temp files
        for tempFile in tempFiles {
            try? FileManager.default.removeItem(at: tempFile)
        }
        tempFiles.removeAll()

        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    /// Check if process is running
    public var isRunning: Bool {
        process?.isRunning ?? false
    }
}

// MARK: - Prompt Input Type

/// Input prompt type - text string or async stream for bidirectional
public enum PromptInput: Sendable {
    case text(String)
    case stream(AsyncStream<String>)
}
