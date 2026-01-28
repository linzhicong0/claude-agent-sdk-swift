#!/usr/bin/env python3
"""
Simple Calculator MCP Server using FastMCP.

This is an example MCP server that provides basic arithmetic operations.
It can be used to test the Swift Claude Agent SDK's MCP server integration.

Usage:
    # Run directly with Python
    python3 calculator_mcp_server.py
    
    # Or use with Claude CLI
    claude --mcp-config '{"mcpServers":{"calc":{"command":"python3","args":["examples/calculator_mcp_server.py"]}}}'
"""

from fastmcp import FastMCP

# Create the MCP server
mcp = FastMCP("calculator", instructions="A simple calculator that can add and multiply numbers.")


@mcp.tool()
def add(a: float, b: float) -> str:
    """Add two numbers together.
    
    Args:
        a: The first number
        b: The second number
        
    Returns:
        The sum of a and b as a formatted string
    """
    result = a + b
    return f"The result of {a} + {b} = {result}"


@mcp.tool()
def multiply(a: float, b: float) -> str:
    """Multiply two numbers together.
    
    Args:
        a: The first number
        b: The second number
        
    Returns:
        The product of a and b as a formatted string
    """
    result = a * b
    return f"The result of {a} × {b} = {result}"


@mcp.tool()
def subtract(a: float, b: float) -> str:
    """Subtract the second number from the first.
    
    Args:
        a: The first number
        b: The second number to subtract
        
    Returns:
        The difference of a - b as a formatted string
    """
    result = a - b
    return f"The result of {a} - {b} = {result}"


@mcp.tool()
def divide(a: float, b: float) -> str:
    """Divide the first number by the second.
    
    Args:
        a: The dividend
        b: The divisor (must not be zero)
        
    Returns:
        The quotient of a / b as a formatted string
    """
    if b == 0:
        return "Error: Cannot divide by zero"
    result = a / b
    return f"The result of {a} ÷ {b} = {result}"


if __name__ == "__main__":
    # Run the MCP server using stdio transport (default for CLI integration)
    mcp.run(transport="stdio", show_banner=False)
