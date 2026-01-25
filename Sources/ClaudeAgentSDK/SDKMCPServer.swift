// MARK: - SDK MCP Server

import Foundation

/// An in-process MCP server that runs within the SDK
public final class SDKMCPServer: @unchecked Sendable {
    
    // MARK: - Properties
    
    public let name: String
    public let version: String
    public private(set) var tools: [MCPTool]
    
    // MARK: - Initialization
    
    public init(name: String, version: String, tools: [MCPTool] = []) {
        self.name = name
        self.version = version
        self.tools = tools
    }
    
    /// Add a tool to the server
    public func addTool(_ tool: MCPTool) {
        tools.append(tool)
    }
    
    // MARK: - Message Handling
    
    /// Handle an incoming MCP JSON-RPC message
    func handleMessage(_ message: [String: Any]) async throws -> [String: Any] {
        guard let method = message["method"] as? String else {
            return buildError(id: message["id"], code: -32600, message: "Invalid request: missing method")
        }
        
        let id = message["id"]
        
        switch method {
        case "initialize":
            return buildInitializeResponse(id: id)
            
        case "notifications/initialized":
            // Acknowledge, no response needed for notifications
            return [:]
            
        case "tools/list":
            return buildToolsListResponse(id: id)
            
        case "tools/call":
            return try await handleToolCall(message: message, id: id)
            
        default:
            return buildError(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }
    
    // MARK: - Response Builders
    
    private func buildInitializeResponse(id: Any?) -> [String: Any] {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "result": [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": [:]
                ],
                "serverInfo": [
                    "name": name,
                    "version": version
                ]
            ]
        ]
        if let id = id {
            response["id"] = id
        }
        return response
    }
    
    private func buildToolsListResponse(id: Any?) -> [String: Any] {
        let toolsList = tools.map { tool -> [String: Any] in
            [
                "name": tool.name,
                "description": tool.description,
                "inputSchema": tool.inputSchema
            ]
        }
        
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "result": [
                "tools": toolsList
            ]
        ]
        if let id = id {
            response["id"] = id
        }
        return response
    }
    
    private func handleToolCall(message: [String: Any], id: Any?) async throws -> [String: Any] {
        guard let params = message["params"] as? [String: Any],
              let toolName = params["name"] as? String else {
            return buildError(id: id, code: -32602, message: "Invalid params: missing tool name")
        }
        
        guard let tool = tools.first(where: { $0.name == toolName }) else {
            return buildError(id: id, code: -32602, message: "Tool not found: \(toolName)")
        }
        
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        
        do {
            let result = try await tool.handler(arguments)
            return buildToolCallResponse(id: id, result: result)
        } catch {
            return buildError(id: id, code: -32000, message: "Tool error: \(error.localizedDescription)")
        }
    }
    
    private func buildToolCallResponse(id: Any?, result: MCPToolResult) -> [String: Any] {
        let content: [[String: Any]] = result.content.map { item in
            switch item {
            case .text(let text):
                return ["type": "text", "text": text]
            case .image(let data, let mimeType):
                return ["type": "image", "data": data, "mimeType": mimeType]
            case .resource(let uri, let mimeType, let text):
                var dict: [String: Any] = ["type": "resource", "uri": uri]
                if let mimeType = mimeType { dict["mimeType"] = mimeType }
                if let text = text { dict["text"] = text }
                return dict
            }
        }
        
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "result": [
                "content": content,
                "isError": result.isError
            ]
        ]
        if let id = id {
            response["id"] = id
        }
        return response
    }
    
    private func buildError(id: Any?, code: Int, message: String) -> [String: Any] {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "error": [
                "code": code,
                "message": message
            ]
        ]
        if let id = id {
            response["id"] = id
        }
        return response
    }
}

// MARK: - MCP Tool Definition

/// A tool that can be called by Claude via MCP
public struct MCPTool: Sendable {
    
    /// Tool name
    public let name: String
    
    /// Human-readable description
    public let description: String
    
    /// JSON Schema for input validation
    public let inputSchema: [String: Any]
    
    /// Handler function
    public let handler: @Sendable ([String: Any]) async throws -> MCPToolResult
    
    /// Initialize a new MCP tool
    public init(
        name: String,
        description: String,
        inputSchema: [String: Any],
        handler: @escaping @Sendable ([String: Any]) async throws -> MCPToolResult
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.handler = handler
    }
}

// MARK: - MCP Tool Result

/// Result returned from an MCP tool call
public struct MCPToolResult: Sendable {
    
    /// Content items in the result
    public let content: [MCPContentItem]
    
    /// Whether this result represents an error
    public let isError: Bool
    
    public init(content: [MCPContentItem], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }
    
    /// Convenience initializer for text result
    public static func text(_ text: String, isError: Bool = false) -> MCPToolResult {
        MCPToolResult(content: [.text(text)], isError: isError)
    }
    
    /// Convenience initializer for error result
    public static func error(_ message: String) -> MCPToolResult {
        MCPToolResult(content: [.text(message)], isError: true)
    }
}

/// Content item in an MCP result
public enum MCPContentItem: Sendable {
    case text(String)
    case image(data: String, mimeType: String)
    case resource(uri: String, mimeType: String?, text: String?)
}

// MARK: - Tool Builder DSL

/// Decorator-style tool creation
public func mcpTool(
    name: String,
    description: String,
    parameters: [String: MCPParameterType] = [:],
    required: [String] = [],
    handler: @escaping @Sendable ([String: Any]) async throws -> MCPToolResult
) -> MCPTool {
    
    var properties: [String: [String: Any]] = [:]
    for (paramName, paramType) in parameters {
        properties[paramName] = paramType.schema
    }
    
    let inputSchema: [String: Any] = [
        "type": "object",
        "properties": properties,
        "required": required
    ]
    
    return MCPTool(
        name: name,
        description: description,
        inputSchema: inputSchema,
        handler: handler
    )
}

/// Parameter type for tool schema
public indirect enum MCPParameterType {
    case string(description: String? = nil)
    case number(description: String? = nil)
    case integer(description: String? = nil)
    case boolean(description: String? = nil)
    case array(items: MCPParameterType, description: String? = nil)
    case object(properties: [String: MCPParameterType], description: String? = nil)
    
    var schema: [String: Any] {
        switch self {
        case .string(let desc):
            var s: [String: Any] = ["type": "string"]
            if let desc = desc { s["description"] = desc }
            return s
        case .number(let desc):
            var s: [String: Any] = ["type": "number"]
            if let desc = desc { s["description"] = desc }
            return s
        case .integer(let desc):
            var s: [String: Any] = ["type": "integer"]
            if let desc = desc { s["description"] = desc }
            return s
        case .boolean(let desc):
            var s: [String: Any] = ["type": "boolean"]
            if let desc = desc { s["description"] = desc }
            return s
        case .array(let items, let desc):
            var s: [String: Any] = ["type": "array", "items": items.schema]
            if let desc = desc { s["description"] = desc }
            return s
        case .object(let props, let desc):
            var s: [String: Any] = [
                "type": "object",
                "properties": props.mapValues { $0.schema }
            ]
            if let desc = desc { s["description"] = desc }
            return s
        }
    }
}
