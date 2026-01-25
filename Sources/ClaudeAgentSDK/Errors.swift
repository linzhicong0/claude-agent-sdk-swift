// MARK: - Errors

import Foundation

/// Base error type for all Claude SDK errors
public enum ClaudeSDKError: Error, LocalizedError, Sendable {
    /// CLI binary not found at any expected location
    case cliNotFound(searchedPaths: [String])
    
    /// Failed to connect to CLI process
    case connectionFailed(reason: String)
    
    /// Process exited with non-zero exit code
    case processError(exitCode: Int32, stderr: String?)
    
    /// Failed to decode JSON from CLI output
    case jsonDecodeError(line: String, underlyingError: Error)
    
    /// Failed to parse message structure
    case messageParseError(rawData: [String: Any], reason: String)
    
    /// Control protocol error (timeout, invalid response, etc.)
    case controlProtocolError(reason: String)
    
    /// Buffer overflow - CLI output exceeded maximum buffer size
    case bufferOverflow(bufferSize: Int, maxSize: Int)
    
    /// Invalid configuration
    case configurationError(reason: String)
    
    /// Operation timeout
    case timeout(operation: String, duration: TimeInterval)
    
    /// Stdin write error
    case writeError(reason: String)
    
    public var errorDescription: String? {
        switch self {
        case .cliNotFound(let paths):
            return """
                Claude Code CLI not found. Searched paths:
                \(paths.map { "  - \($0)" }.joined(separator: "\n"))
                
                Install with: npm install -g @anthropic-ai/claude-code
                """
        case .connectionFailed(let reason):
            return "Failed to connect to Claude CLI: \(reason)"
        case .processError(let exitCode, let stderr):
            var msg = "CLI process exited with code \(exitCode)"
            if let stderr = stderr, !stderr.isEmpty {
                msg += "\nStderr: \(stderr.prefix(500))"
            }
            return msg
        case .jsonDecodeError(let line, let error):
            return "Failed to decode JSON: \(error.localizedDescription)\nLine: \(line.prefix(100))"
        case .messageParseError(_, let reason):
            return "Failed to parse message: \(reason)"
        case .controlProtocolError(let reason):
            return "Control protocol error: \(reason)"
        case .bufferOverflow(let size, let maxSize):
            return "Buffer overflow: \(size) bytes exceeds maximum \(maxSize) bytes"
        case .configurationError(let reason):
            return "Configuration error: \(reason)"
        case .timeout(let operation, let duration):
            return "Operation '\(operation)' timed out after \(duration) seconds"
        case .writeError(let reason):
            return "Failed to write to stdin: \(reason)"
        }
    }
}
