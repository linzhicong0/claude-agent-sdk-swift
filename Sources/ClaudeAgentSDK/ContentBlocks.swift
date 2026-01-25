// MARK: - Content Block Types

import Foundation

/// A block of content in a message
public enum ContentBlock: Sendable, Equatable {
    case text(TextBlock)
    case thinking(ThinkingBlock)
    case toolUse(ToolUseBlock)
    case toolResult(ToolResultBlock)
}

/// Plain text content
public struct TextBlock: Sendable, Equatable, Codable {
    public let text: String
    
    public init(text: String) {
        self.text = text
    }
}

/// Extended thinking content
public struct ThinkingBlock: Sendable, Equatable, Codable {
    public let thinking: String
    public let signature: String
    
    public init(thinking: String, signature: String) {
        self.thinking = thinking
        self.signature = signature
    }
}

/// Tool use request from Claude
public struct ToolUseBlock: Sendable, Equatable {
    public let id: String
    public let name: String
    public let input: [String: AnyCodable]
    
    public init(id: String, name: String, input: [String: AnyCodable]) {
        self.id = id
        self.name = name
        self.input = input
    }
}

/// Result of a tool execution
public struct ToolResultBlock: Sendable, Equatable {
    public let toolUseId: String
    public let content: ToolResultContent?
    public let isError: Bool?
    
    public init(toolUseId: String, content: ToolResultContent?, isError: Bool?) {
        self.toolUseId = toolUseId
        self.content = content
        self.isError = isError
    }
}

/// Content of a tool result - can be string or structured
public enum ToolResultContent: Sendable, Equatable {
    case text(String)
    case structured([[String: AnyCodable]])
}

// MARK: - ContentBlock Codable

extension ContentBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "text":
            self = .text(try TextBlock(from: decoder))
        case "thinking":
            self = .thinking(try ThinkingBlock(from: decoder))
        case "tool_use":
            self = .toolUse(try ToolUseBlock(from: decoder))
        case "tool_result":
            self = .toolResult(try ToolResultBlock(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content block type: \(type)"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let block):
            try container.encode("text", forKey: .type)
            try block.encode(to: encoder)
        case .thinking(let block):
            try container.encode("thinking", forKey: .type)
            try block.encode(to: encoder)
        case .toolUse(let block):
            try container.encode("tool_use", forKey: .type)
            try block.encode(to: encoder)
        case .toolResult(let block):
            try container.encode("tool_result", forKey: .type)
            try block.encode(to: encoder)
        }
    }
}

// MARK: - ToolUseBlock Codable

extension ToolUseBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, input
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        input = try container.decode([String: AnyCodable].self, forKey: .input)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(input, forKey: .input)
    }
}

// MARK: - ToolResultBlock Codable

extension ToolResultBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolUseId = try container.decode(String.self, forKey: .toolUseId)
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError)
        
        // Content can be string or array
        if let stringContent = try? container.decode(String.self, forKey: .content) {
            content = .text(stringContent)
        } else if let arrayContent = try? container.decode([[String: AnyCodable]].self, forKey: .content) {
            content = .structured(arrayContent)
        } else {
            content = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(toolUseId, forKey: .toolUseId)
        try container.encodeIfPresent(isError, forKey: .isError)
        
        switch content {
        case .text(let str):
            try container.encode(str, forKey: .content)
        case .structured(let arr):
            try container.encode(arr, forKey: .content)
        case .none:
            break
        }
    }
}

// MARK: - AnyCodable for dynamic JSON

/// A type-erased Codable value for handling dynamic JSON
public struct AnyCodable: Sendable, Equatable, Codable, CustomStringConvertible {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode AnyCodable"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unable to encode AnyCodable")
            )
        }
    }
    
    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (is NSNull, is NSNull):
            return true
        case (let l as Bool, let r as Bool):
            return l == r
        case (let l as Int, let r as Int):
            return l == r
        case (let l as Double, let r as Double):
            return l == r
        case (let l as String, let r as String):
            return l == r
        default:
            return false
        }
    }
    
    public var description: String {
        switch value {
        case is NSNull:
            return "null"
        case let bool as Bool:
            return bool ? "true" : "false"
        case let num as Int:
            return "\(num)"
        case let num as Double:
            return "\(num)"
        case let str as String:
            return "\"\(str)\""
        case let arr as [Any]:
            return "[\(arr.map { AnyCodable($0).description }.joined(separator: ", "))]"
        case let dict as [String: Any]:
            let pairs = dict.map { "\"\($0.key)\": \(AnyCodable($0.value).description)" }
            return "{\(pairs.joined(separator: ", "))}"
        default:
            return String(describing: value)
        }
    }
    
    // MARK: - Value Accessors
    
    public var stringValue: String? { value as? String }
    public var intValue: Int? { value as? Int }
    public var doubleValue: Double? { value as? Double }
    public var boolValue: Bool? { value as? Bool }
    public var arrayValue: [Any]? { value as? [Any] }
    public var dictionaryValue: [String: Any]? { value as? [String: Any] }
    public var isNull: Bool { value is NSNull }
}
