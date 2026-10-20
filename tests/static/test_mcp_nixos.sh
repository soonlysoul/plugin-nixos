#!/usr/bin/env bash
# .mcp.json: the nixos server, declared as pp.sh add-mcp wrote it; its variables in the README.
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
SUITE=test_mcp_nixos
MCP="$PLUGIN_ROOT/.mcp.json"

if ! jq -e --arg s nixos '.mcpServers[$s]' "$MCP" >/dev/null 2>&1; then
  fail "serveur nixos déclaré" ".mcp.json absent, ou sans le serveur nixos"
  finish
  exit
fi
pass "serveur nixos déclaré"
want=$(cat <<'JSON'
{"command":"bash","args":["${CLAUDE_PLUGIN_ROOT}/scripts/mcp-nixos.sh"]}
JSON
)
jq -e --arg s nixos --argjson want "$want" '.mcpServers[$s] == $want' "$MCP" >/dev/null \
  && pass "déclaration de nixos" || fail "déclaration de nixos" "$(jq -c --arg s nixos '.mcpServers[$s]' "$MCP")"

finish
