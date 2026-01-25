// MARK: - Message Parser

import Foundation

/// Parser for converting raw JSON to typed Message objects
public struct MessageParser {
    
    /// Parse a raw JSON dictionary into a typed Message
    public static func parse(_ data: [String: Any]) throws -> Message {
        guard let type = data["type"] as? String else {
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Missing 'type' field"
            )
        }
        
        switch type {
        case "user":
            return .user(try parseUserMessage(data))
        case "assistant":
            return .assistant(try parseAssistantMessage(data))
        case "system":
            return .system(try parseSystemMessage(data))
        case "result":
            return .result(try parseResultMessage(data))
        case "stream_event":
            return .streamEvent(try parseStreamEvent(data))
        default:
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Unknown message type: \(type)"
            )
        }
    }
    
    // MARK: - User Message
    
    private static func parseUserMessage(_ data: [String: Any]) throws -> UserMessage {
        guard let messageData = data["message"] as? [String: Any] else {
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Missing 'message' field in user message"
            )
        }
        
        let content: UserContent
        if let contentString = messageData["content"] as? String {
            content = .text(contentString)
        } else if let contentArray = messageData["content"] as? [[String: Any]] {
            let blocks = try contentArray.map { try parseContentBlock($0) }
            content = .blocks(blocks)
        } else {
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Invalid content format in user message"
            )
        }
        
        return UserMessage(
            content: content,
            uuid: data["uuid"] as? String,
            parentToolUseId: data["parent_tool_use_id"] as? String
        )
    }
    
    // MARK: - Assistant Message
    
    private static func parseAssistantMessage(_ data: [String: Any]) throws -> AssistantMessage {
        guard let messageData = data["message"] as? [String: Any] else {
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Missing 'message' field in assistant message"
            )
        }
        
        guard let contentArray = messageData["content"] as? [[String: Any]] else {
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Missing or invalid 'content' array in assistant message"
            )
        }
        
        let content = try contentArray.map { try parseContentBlock($0) }
        
        guard let model = data["model"] as? String else {
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Missing 'model' field in assistant message"
            )
        }
        
        var error: AssistantMessageError?
        if let errorData = data["error"] as? [String: Any],
           let errorType = errorData["type"] as? String,
           let errorMessage = errorData["message"] as? String {
            error = AssistantMessageError(type: errorType, message: errorMessage)
        }
        
        return AssistantMessage(
            content: content,
            model: model,
            parentToolUseId: data["parent_tool_use_id"] as? String,
            error: error
        )
    }
    
    // MARK: - System Message
    
    private static func parseSystemMessage(_ data: [String: Any]) throws -> SystemMessage {
        guard let subtype = data["subtype"] as? String else {
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Missing 'subtype' field in system message"
            )
        }
        
        // Everything except type and subtype goes into data
        var messageData: [String: AnyCodable] = [:]
        for (key, value) in data where key != "type" && key != "subtype" {
            messageData[key] = AnyCodable(value)
        }
        
        return SystemMessage(subtype: subtype, data: messageData)
    }
    
    // MARK: - Result Message
    
    private static func parseResultMessage(_ data: [String: Any]) throws -> ResultMessage {
        guard let subtypeStr = data["subtype"] as? String,
              let subtype = ResultSubtype(rawValue: subtypeStr) else {
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Missing or invalid 'subtype' field in result message"
            )
        }
        
        guard let durationMs = data["duration_ms"] as? Int else {
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Missing 'duration_ms' field in result message"
            )
        }
        
        guard let durationApiMs = data["duration_api_ms"] as? Int else {
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Missing 'duration_api_ms' field in result message"
            )
        }
        
        guard let isError = data["is_error"] as? Bool else {
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Missing 'is_error' field in result message"
            )
        }
        
        guard let numTurns = data["num_turns"] as? Int else {
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Missing 'num_turns' field in result message"
            )
        }
        
        guard let sessionId = data["session_id"] as? String else {
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Missing 'session_id' field in result message"
            )
        }
        
        var usage: [String: AnyCodable]?
        if let usageData = data["usage"] as? [String: Any] {
            usage = usageData.mapValues { AnyCodable($0) }
        }
        
        var structuredOutput: AnyCodable?
        if let output = data["structured_output"] {
            structuredOutput = AnyCodable(output)
        }
        
        return ResultMessage(
            subtype: subtype,
            durationMs: durationMs,
            durationApiMs: durationApiMs,
            isError: isError,
            numTurns: numTurns,
            sessionId: sessionId,
            totalCostUSD: data["total_cost_usd"] as? Double,
            usage: usage,
            structuredOutput: structuredOutput
        )
    }
    
    // MARK: - Stream Event
    
    private static func parseStreamEvent(_ data: [String: Any]) throws -> StreamEvent {
        guard let uuid = data["uuid"] as? String else {
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Missing 'uuid' field in stream event"
            )
        }
        
        guard let sessionId = data["session_id"] as? String else {
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Missing 'session_id' field in stream event"
            )
        }
        
        guard let event = data["event"] as? [String: Any] else {
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Missing 'event' field in stream event"
            )
        }
        
        return StreamEvent(
            uuid: uuid,
            sessionId: sessionId,
            event: event.mapValues { AnyCodable($0) },
            parentToolUseId: data["parent_tool_use_id"] as? String
        )
    }
    
    // MARK: - Content Blocks
    
    private static func parseContentBlock(_ data: [String: Any]) throws -> ContentBlock {
        guard let type = data["type"] as? String else {
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Missing 'type' field in content block"
            )
        }
        
        switch type {
        case "text":
            guard let text = data["text"] as? String else {
                throw ClaudeSDKError.messageParseError(
                    rawData: data.mapValues { AnyCodable($0) },
                    reason: "Missing 'text' field in text block"
                )
            }
            return .text(TextBlock(text: text))
            
        case "thinking":
            guard let thinking = data["thinking"] as? String else {
                throw ClaudeSDKError.messageParseError(
                    rawData: data.mapValues { AnyCodable($0) },
                    reason: "Missing 'thinking' field in thinking block"
                )
            }
            guard let signature = data["signature"] as? String else {
                throw ClaudeSDKError.messageParseError(
                    rawData: data.mapValues { AnyCodable($0) },
                    reason: "Missing 'signature' field in thinking block"
                )
            }
            return .thinking(ThinkingBlock(thinking: thinking, signature: signature))
            
        case "tool_use":
            guard let id = data["id"] as? String else {
                throw ClaudeSDKError.messageParseError(
                    rawData: data.mapValues { AnyCodable($0) },
                    reason: "Missing 'id' field in tool_use block"
                )
            }
            guard let name = data["name"] as? String else {
                throw ClaudeSDKError.messageParseError(
                    rawData: data.mapValues { AnyCodable($0) },
                    reason: "Missing 'name' field in tool_use block"
                )
            }
            guard let input = data["input"] as? [String: Any] else {
                throw ClaudeSDKError.messageParseError(
                    rawData: data.mapValues { AnyCodable($0) },
                    reason: "Missing 'input' field in tool_use block"
                )
            }
            return .toolUse(ToolUseBlock(
                id: id,
                name: name,
                input: input.mapValues { AnyCodable($0) }
            ))
            
        case "tool_result":
            guard let toolUseId = data["tool_use_id"] as? String else {
                throw ClaudeSDKError.messageParseError(
                    rawData: data.mapValues { AnyCodable($0) },
                    reason: "Missing 'tool_use_id' field in tool_result block"
                )
            }
            
            var content: ToolResultContent?
            if let contentStr = data["content"] as? String {
                content = .text(contentStr)
            } else if let contentArr = data["content"] as? [[String: Any]] {
                content = .structured(contentArr.map { dict in
                    dict.mapValues { AnyCodable($0) }
                })
            }
            
            return .toolResult(ToolResultBlock(
                toolUseId: toolUseId,
                content: content,
                isError: data["is_error"] as? Bool
            ))
            
        default:
            throw ClaudeSDKError.messageParseError(
                rawData: data.mapValues { AnyCodable($0) },
                reason: "Unknown content block type: \(type)"
            )
        }
    }
}

// MARK: - Control Message Types

/// Types of control messages in the protocol
public enum ControlMessageType: String {
    case controlRequest = "control_request"
    case controlResponse = "control_response"
}

/// Check if raw data is a control message
public func isControlMessage(_ data: [String: Any]) -> Bool {
    guard let type = data["type"] as? String else { return false }
    return type == ControlMessageType.controlRequest.rawValue ||
           type == ControlMessageType.controlResponse.rawValue
}
