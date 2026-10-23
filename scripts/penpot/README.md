# Penpot MCP tooling

Scripts for driving the Penpot file「M1-B G5 Design」from a shell. The design
source of truth is `design/`; these scripts only automate reading and
exporting it so the Penpot file and the repository cannot drift apart.

## `penpot_mcp.py`

A command-line client for the remote Penpot MCP server. Editors (Claude Code,
Codex) mount that server through their own MCP clients; this script is the
equivalent for a terminal or a CI step.

```sh
# The user token lives in the URL. Keep it in a local, untracked file.
TOKEN_FILE="$HOME/.dsh/penpot-mcp-url"

python3 scripts/penpot/penpot_mcp.py --url-file "$TOKEN_FILE" tools
python3 scripts/penpot/penpot_mcp.py --url-file "$TOKEN_FILE" \
    call high_level_overview '{}'
python3 scripts/penpot/penpot_mcp.py --url-file "$TOKEN_FILE" \
    call execute_code '{"code": "return penpot.currentFile.name"}'
# export_shape returns an image content block; --out writes it to disk
python3 scripts/penpot/penpot_mcp.py --url-file "$TOKEN_FILE" \
    call export_shape '{"shapeId": "page"}' --out /tmp/page.png
```

Notes:

- The endpoint is `https://design.penpot.app/mcp/stream?userToken=…`. The token
  is a secret: pass it by `--url`, `--url-file`, or `PENPOT_MCP_URL`, never by
  committing it. Diagnostics redact the query string.
- Cloudflare rejects non-browser clients with `HTTP 403 / error 1010`, so the
  script sends a browser User-Agent and Origin header. Keep those in the script
  in sync with a real browser if Penpot tightens the check.
- The Penpot file must be connected to the MCP server through the Penpot MCP
  plugin in a browser tab. Without that connection `execute_code` has no project
  to act on and calls fail or time out.
- The server exposes four tools: `execute_code`, `high_level_overview`,
  `penpot_api_info`, `export_shape`.

## `import-penpot-exports.py` and `set-2x-export-presets.js`

Existing Penpot helpers: import a 2x export zip into `design/*/screens/` and set
2x export presets on Penpot boards. See their file headers for usage.
