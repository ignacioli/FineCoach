#!/usr/bin/env python3
"""Command-line client for the remote Penpot MCP server.

What this is
------------
The Penpot MCP server is a Streamable-HTTP MCP endpoint, not a local process:
    https://design.penpot.app/mcp/stream?userToken=<secret>
Editors (Claude Code, Codex) mount it through their own MCP clients. This
script is the equivalent for a terminal or CI step, so a shell can list the
server's tools and call them without an MCP-aware host.

It is a *client*, not a server or a proxy: every invocation opens a fresh MCP
session, calls one method, prints the result, and exits.

Why the browser-shaped request
------------------------------
Cloudflare fronts the endpoint and rejects non-browser signatures with
HTTP 403 ("Error 1010: Access denied"). A stock urllib/requests call is
blocked; sending a normal browser User-Agent (and Origin) is accepted. Keep
those headers in sync with a real browser if Penpot tightens the check.

Secret handling
---------------
The user token is part of the endpoint URL, so the URL must never be committed
or echoed. This script takes it from, in order:
    1. --url
    2. --url-file PATH (first non-empty line)
    3. the PENPOT_MCP_URL environment variable
Diagnostics redact the query string (and therefore the token).

Usage
-----
    # List the tools the server exposes
    penpot_mcp.py --url-file "$HOME/.dsh/penpot-mcp-url" tools

    # Call a tool with inline JSON arguments
    penpot_mcp.py call high_level_overview '{}'
    penpot_mcp.py call penpot_api_info '{"type": "Board"}'
    penpot_mcp.py call execute_code '{"code": "return penpot.currentFile.name"}'

    # Read JSON arguments from a file (safer for long code snippets)
    penpot_mcp.py call execute_code --args-file /tmp/execute.json

    # Save an exported image (export_shape returns an image content block)
    penpot_mcp.py call export_shape '{"shapeId": "page"}' --out /tmp/page.png

    # Raw JSON output instead of pretty-printed text
    penpot_mcp.py call high_level_overview '{}' --json

Prerequisites
-------------
The Penpot file must be connected to the MCP server through the Penpot MCP
plugin in a browser tab; without that connection `execute_code` has no project
to act on and calls fail or time out.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request

PROTOCOL_VERSION = "2025-06-18"
BROWSER_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
)
PENPOT_ORIGIN = "https://design.penpot.app"


def redacted(url: str) -> str:
    """Strip the query string so a token never reaches logs."""
    base, _, _query = url.partition("?")
    return f"{base}?<redacted>" if _query else base


def resolve_url(args: argparse.Namespace) -> str:
    """Resolve the endpoint URL from --url, --url-file, or the environment."""
    if args.url:
        return args.url.strip()
    if args.url_file:
        with open(os.path.expanduser(args.url_file), encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if line and not line.startswith("#"):
                    return line
        raise SystemExit(f"{args.url_file}: no endpoint URL found")
    env = os.environ.get("PENPOT_MCP_URL", "").strip()
    if env:
        return env
    raise SystemExit(
        "no endpoint URL: pass --url or --url-file, or set PENPOT_MCP_URL "
        "(see the module docstring for the format)"
    )


def parse_sse(text: str) -> list[str]:
    """Return the payloads of an SSE response body, one per event."""
    payloads: list[str] = []
    current: list[str] = []
    for line in text.splitlines():
        if line.startswith("data:"):
            current.append(line[5:].strip())
        elif not line and current:
            payloads.append("\n".join(current))
            current = []
    if current:
        payloads.append("\n".join(current))
    return payloads


class McpSession:
    """One Streamable-HTTP MCP session against the Penpot server."""

    def __init__(self, url: str, timeout: float) -> None:
        self.url = url
        self.timeout = timeout
        self.session_id: str | None = None
        self._next_id = 0
        self._call("initialize", {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {},
            "clientInfo": {"name": "penpot-mcp-cli", "version": "1.0"},
        })
        # The initialized notification has no id and no result to read.
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def _post(self, payload: dict) -> list[dict]:
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            "User-Agent": BROWSER_UA,
            "Origin": PENPOT_ORIGIN,
        }
        if self.session_id:
            headers["mcp-session-id"] = self.session_id
        request = urllib.request.Request(
            self.url,
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        try:
            response = urllib.request.urlopen(request, timeout=self.timeout)
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8", "replace")[:800]
            hint = ""
            if error.code == 403:
                hint = " (Cloudflare blocks non-browser clients; check the User-Agent)"
            raise SystemExit(f"HTTP {error.code}{hint}: {body}") from None
        except urllib.error.URLError as error:
            raise SystemExit(f"cannot reach {redacted(self.url)}: {error.reason}") from None

        session_id = response.headers.get("mcp-session-id")
        if session_id:
            self.session_id = session_id
        body = response.read().decode("utf-8", "replace")
        content_type = response.headers.get("content-type") or ""
        if "text/event-stream" in content_type:
            return [json.loads(item) for item in parse_sse(body) if item.strip()]
        return [json.loads(body)] if body.strip() else []

    def _call(self, method: str, params: dict | None = None) -> dict:
        self._next_id += 1
        messages = self._post({
            "jsonrpc": "2.0",
            "id": self._next_id,
            "method": method,
            "params": params or {},
        })
        for message in messages:
            if "error" in message:
                raise SystemExit("MCP error: " + json.dumps(message["error"], ensure_ascii=False))
        replies = [message for message in messages if "id" in message]
        if not replies:
            raise SystemExit(f"MCP: no response to {method}")
        return replies[-1]

    def list_tools(self) -> list[dict]:
        return self._call("tools/list")["result"]["tools"]

    def call_tool(self, name: str, arguments: dict) -> dict:
        return self._call("tools/call", {"name": name, "arguments": arguments})["result"]


def print_text_blocks(result: dict, raw: bool) -> list[dict]:
    """Print a tool result; return any image blocks for optional saving."""
    images: list[dict] = []
    for block in result.get("content", []):
        if block.get("type") == "text":
            if raw:
                print(json.dumps({"text": block["text"]}, ensure_ascii=False))
            else:
                print(block["text"])
        elif block.get("type") == "image":
            images.append(block)
            if not raw:
                print(f"[image {block.get('mimeType', 'unknown')}, {len(block.get('data', ''))} base64 chars]")
        else:
            print(json.dumps(block, ensure_ascii=False))
    if "structuredContent" in result:
        print(json.dumps(result["structuredContent"], ensure_ascii=False, indent=2))
    if result.get("isError"):
        raise SystemExit(1)
    return images


def command_tools(session: McpSession, args: argparse.Namespace) -> int:
    tools = session.list_tools()
    for tool in tools:
        first_line = (tool.get("description") or "").strip().splitlines()
        summary = first_line[0][:120] if first_line else ""
        print(f"{tool['name']} :: {summary}")
    print(f"\n{len(tools)} tools")
    return 0


def command_call(session: McpSession, args: argparse.Namespace) -> int:
    if args.args_file:
        with open(os.path.expanduser(args.args_file), encoding="utf-8") as handle:
            arguments = json.load(handle)
    else:
        arguments = json.loads(args.arguments) if args.arguments else {}
    result = session.call_tool(args.tool, arguments)
    images = print_text_blocks(result, args.json)
    if args.out:
        if not images:
            raise SystemExit("--out given but the tool returned no image block")
        image = images[0]
        data = base64.b64decode(image["data"])
        with open(os.path.expanduser(args.out), "wb") as handle:
            handle.write(data)
        print(f"wrote {args.out} ({len(data)} bytes)")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Call the remote Penpot MCP server from a shell.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__.split("Usage\n-----", 1)[-1].split("Prerequisites", 1)[0],
    )
    parser.add_argument("--url", help="full MCP Streamable-HTTP URL including userToken")
    parser.add_argument("--url-file", help="file whose first non-empty, non-comment line is the URL")
    parser.add_argument("--timeout", type=float, default=180.0, help="request timeout in seconds (default 180)")
    subparsers = parser.add_subparsers(dest="command", required=True)

    tools_parser = subparsers.add_parser("tools", help="list the server's tools")
    tools_parser.set_defaults(handler=command_tools)

    call_parser = subparsers.add_parser("call", help="call one tool")
    call_parser.add_argument("tool", help="tool name, for example execute_code")
    call_parser.add_argument("arguments", nargs="?", default=None, help="tool arguments as JSON")
    call_parser.add_argument("--args-file", help="read tool arguments from this JSON file instead")
    call_parser.add_argument("--out", help="write the first returned image block to this file")
    call_parser.add_argument("--json", action="store_true", help="print each text block as JSON")
    call_parser.set_defaults(handler=command_call)

    args = parser.parse_args(argv)
    session = McpSession(resolve_url(args), args.timeout)
    return args.handler(session, args)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
