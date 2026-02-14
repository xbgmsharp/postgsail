# Model context protocol (MCP)

Connect your AI tools to PostgSail using MCP

<video controls>
  <source src="https://github.com/user-attachments/assets/162dac63-8f80-4e46-9357-1033b6b6c78b" type="video/mp4">
</video>

The [Model Context Protocol](https://modelcontextprotocol.io/introduction) (MCP) is a standard for connecting Large Language Models (LLMs) to platforms like PostgSail.

Once connected, your AI assistants can interact with and query your PostgSail API on your behalf.

PostgSail MCP server provides AI agents with read-only access to PostgSail marine data systems. This server enables LeChat, Claude and other AI assistants to search and navigate logs, moorages, and stays, monitor and analyze your boat all in one place.

## Key Features

* Daily vessel summaries (current status, weather, systems)
* Voyage summary (reviewing past trips, moorages, stays information)
* System monitoring (battery, solar, sensors, connectivity)
* Historical analysis (tracking patterns, favorite destinations)
* Data export (for external navigation tools)
* Maintenance tracking (through stay notes and logs)

## Authentication

Tool execution (API call) require a valid PostgSail JWT token. Get your token from the profile settings page in the web portal.

## Available Methods
MCP implementation:
* initialize - Initialize MCP connection
* tools/list - List available tools
* tools/call - Execute a tool (requires JWT authentication)
* prompts/list - List available prompts
* prompts/get - Get a specific prompt
* resources/list - List available resources
* resources/read - Read a specific resource

## Remote MCP Server

Accessible at https://mcp.openplotter.cloud/

[LeChat](https://chat.mistral.ai/) allow remote [connectors](https://chat.mistral.ai/connections) even with a free account.

Others AI [ClaudeAI](https://claude.ai) and [OpenAI](https://chatgpt.com/) requires an upgrade plan to use remote connectors.

However you can use the MCP locally with Claude Desktop app.


### Endpoints

    POST /mcp - Main MCP endpoint (JSON-RPC 2.0)
    GET /health - Health check endpoint
    GET / - Overview

### Authentication

The authentication is done via authorization Bearer header, https://iot.openplotter.cloud/profile profile page -> MCP.

### Configuration
```json
{
    "mcpServers": {
        "postgsail": {
            "type": "streamable-http",
            "url": "https://mcp.openplotter.cloud/mcp",
              "note": "A Model Context Protocol (MCP) server that provides AI agents with read-only access to PostgSail marine data systems.",
              "headers": {
                "Authorization": "Bearer ${POSTGSAIL_MCP_ACCESS_TOKEN}"
              }
        }
    }
}
```

## Local STDIO MCP Server

Accessible locally, works with Claude Desktop app.

### Installation

* Install Claude App
* Settings -> Extensions
* Drag .MCPB or .DXT files here to install

OR

* Install Claude App.
* Settings -> Extensions -> Advanced settings -> Extension Developer
* Install Extension...
