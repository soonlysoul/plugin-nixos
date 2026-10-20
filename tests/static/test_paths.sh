#!/usr/bin/env bash
# Paths: every ${CLAUDE_PLUGIN_ROOT}/… cited by a skill, an agent or .mcp.json exists; scripts
# under scripts/ and hooks/scripts/, tools without extension included, are bash scripts that
# parse; MCP servers follow tests/mcp.sh; no /bin/bash, no personal or store path anywhere in the
# components.
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
SUITE=test_paths
shopt -s nullglob

echo "# chemins cités"
substituted=("$PLUGIN_ROOT"/skills/*/SKILL.md "$PLUGIN_ROOT"/agents/*.md)
MCP_JSON="$PLUGIN_ROOT/.mcp.json"
mcp=()
[[ -f $MCP_JSON ]] && mcp=("$MCP_JSON")
cited=$(cat "${substituted[@]}" ${mcp[@]+"${mcp[@]}"} /dev/null | grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]*[A-Za-z0-9_/-]' | sort -u)
while IFS= read -r ref; do
  [[ -n $ref ]] || continue
  [[ -e $PLUGIN_ROOT/${ref#'${CLAUDE_PLUGIN_ROOT}/'} ]] && pass "chemin cité présent : $ref" || fail "chemin cité présent : $ref"
done <<<"$cited"

echo "# hooks/hooks.json"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"
if [[ ! -e $HOOKS_JSON ]]; then
  skip "hooks/hooks.json" "aucun hook"
elif ! jq -e '.hooks | type == "object"' "$HOOKS_JSON" >/dev/null 2>&1; then
  fail "hooks.json est du JSON avec une enveloppe \"hooks\"" "$HOOKS_JSON"
else
  pass "hooks.json est du JSON avec une enveloppe \"hooks\""
  # One line per command hook. Fields are joined by \x1f: read merges consecutive tabs and
  # would drop an empty matcher.
  hooks=$(jq -r '.hooks | to_entries[] | .key as $event | .value[] | (.matcher // "") as $m
                 | .hooks[] | [$event, $m, (.type // ""), (.command // ""), (.args[0] // ""),
                               (.onFailure // ""), ((.args // []) | length), (.timeout // "")]
                 | map(tostring) | join("\u001f")' "$HOOKS_JSON")
  while IFS=$'\x1f' read -r event matcher type command arg0 on_failure argc timeout; do
    label="$event [$matcher] ${arg0##*/}"
    [[ $type == command ]] && pass "$label : hook de type command" || fail "$label : hook de type command" "type : $type"
    [[ $command == bash && $argc == 1 ]] && pass "$label : forme exec (bash + script)" \
      || fail "$label : forme exec (bash + script)" "command : $command, args : $argc"
    [[ $timeout =~ ^[0-9]+$ ]] && pass "$label : timeout déclaré" || fail "$label : timeout déclaré" "timeout : ${timeout:-absent}"
    [[ $event == Stop || $on_failure == block || $on_failure == continue ]] && pass "$label : onFailure déclaré" \
      || fail "$label : onFailure déclaré" "onFailure : ${on_failure:-absent}"
    if [[ $arg0 == '${CLAUDE_PLUGIN_ROOT}/'* ]]; then
      pass "$label : chemin par \${CLAUDE_PLUGIN_ROOT}"
      script=$PLUGIN_ROOT/${arg0#'${CLAUDE_PLUGIN_ROOT}/'}
      [[ -f $script ]] && pass "$label : script présent" || fail "$label : script présent" "$arg0"
      # The mode the script declares in its header decides onFailure.
      if grep -q '^# Fail-closed' "$script" 2>/dev/null; then
        [[ $on_failure == block ]] && pass "$label : fail-closed, onFailure block" || fail "$label : fail-closed, onFailure block" "onFailure : ${on_failure:-absent}"
      elif grep -q '^# Fail-open' "$script" 2>/dev/null && [[ $event != Stop && $event != SubagentStop ]]; then
        [[ $on_failure == continue ]] && pass "$label : fail-open, onFailure continue" || fail "$label : fail-open, onFailure continue" "onFailure : ${on_failure:-absent}"
      fi
    else
      fail "$label : chemin par \${CLAUDE_PLUGIN_ROOT}" "$arg0"
    fi
  done <<<"$hooks"

  for script in "$PLUGIN_ROOT"/hooks/scripts/*.sh; do
    grep -qF "hooks/scripts/${script##*/}" "$HOOKS_JSON" && pass "${script##*/} est câblé dans hooks.json" \
      || fail "${script##*/} est câblé dans hooks.json"
  done
fi

echo "# .mcp.json"
if [[ ! -e $MCP_JSON ]]; then
  skip ".mcp.json" "aucun serveur MCP"
elif ! jq -e '.mcpServers | type == "object"' "$MCP_JSON" >/dev/null 2>&1; then
  fail ".mcp.json est du JSON avec une enveloppe \"mcpServers\"" "$MCP_JSON"
elif [[ ! -f $PLUGIN_ROOT/tests/mcp.sh ]]; then
  fail "tests/mcp.sh présent" "les règles d'une déclaration MCP"
else
  pass ".mcp.json est du JSON avec une enveloppe \"mcpServers\""
  # shellcheck source=../mcp.sh
  source "$PLUGIN_ROOT/tests/mcp.sh"
  while IFS= read -r server; do
    entry=$(jq -c --arg s "$server" '.mcpServers[$s]' "$MCP_JSON")
    if jq -e 'has("command")' <<<"$entry" >/dev/null; then
      error=$(mcp_launcher_error "$entry")
      [[ -z $error ]] && pass "serveur $server : lancé par bash, lanceur de scripts/" || fail "serveur $server : lancé par bash, lanceur de scripts/" "$error"
    else
      error=$(mcp_remote_error "$entry")
      [[ -z $error ]] && pass "serveur $server : distant en HTTPS ou WSS" || fail "serveur $server : distant en HTTPS ou WSS" "$error"
    fi
    error=$(mcp_install_error "$entry" "$PLUGIN_ROOT")
    [[ -z $error ]] && pass "aucune installation impérative (serveur $server)" || fail "aucune installation impérative (serveur $server)" "$error"
    error=$(mcp_variable_error "$entry")
    [[ -z $error ]] && pass "variables en \${VAR} (serveur $server)" || fail "variables en \${VAR} (serveur $server)" "$error"
    error=$(mcp_secret_error "$entry")
    [[ -z $error ]] && pass "aucune valeur secrète en clair (serveur $server)" || fail "aucune valeur secrète en clair (serveur $server)" "$error"
  done < <(jq -r '.mcpServers | keys_unsorted[]' "$MCP_JSON")
fi

echo "# gabarits et annexes"
annexes=()
while IFS= read -r -d '' file; do annexes+=("$file"); done \
  < <(find "$PLUGIN_ROOT/templates" "$PLUGIN_ROOT/skills" -type f ! -name SKILL.md -print0 2>/dev/null)
for file in ${annexes[@]+"${annexes[@]}"}; do
  rel=${file#"$PLUGIN_ROOT"/}
  grep -qF "\${CLAUDE_PLUGIN_ROOT}/$rel" "${substituted[@]}" /dev/null \
    && pass "$rel est cité par \${CLAUDE_PLUGIN_ROOT}" || fail "$rel est cité par \${CLAUDE_PLUGIN_ROOT}"
  grep -qF '${CLAUDE_PLUGIN_ROOT}' "$file" \
    && fail "$rel ne contient pas \${CLAUDE_PLUGIN_ROOT} (les annexes ne sont pas substituées)" \
    || pass "$rel ne contient pas \${CLAUDE_PLUGIN_ROOT} (les annexes ne sont pas substituées)"
done

echo "# scripts"
# A tool under scripts/ may be named without .sh (decision a): a file without extension whose first
# line is a shebang. A data file there is not a script.
tools=()
for file in "$PLUGIN_ROOT"/scripts/*; do
  [[ -f $file && ${file##*/} != *.* && $(head -c 2 "$file") == '#!' ]] && tools+=("$file")
done
scripts=("$PLUGIN_ROOT"/scripts/*.sh ${tools[@]+"${tools[@]}"} "$PLUGIN_ROOT"/scripts/lib/*.sh "$PLUGIN_ROOT"/hooks/scripts/*.sh "$PLUGIN_ROOT"/hooks/scripts/lib/*.sh)
for script in ${scripts[@]+"${scripts[@]}"}; do
  rel=${script#"$PLUGIN_ROOT"/}
  bash -n "$script" 2>/dev/null && pass "$rel : bash -n" || fail "$rel : bash -n"
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -S warning -x --source-path=SCRIPTDIR "$script" >/dev/null 2>&1 && pass "$rel : shellcheck -S warning" \
      || fail "$rel : shellcheck -S warning" "$(shellcheck -S warning -x --source-path=SCRIPTDIR -f gcc "$script" 2>&1 | head -n 2)"
  else
    skip "$rel : shellcheck -S warning" "shellcheck absent"
  fi
  case $rel in
    */lib/*) ;;
    *) [[ $(head -n 1 "$script") == '#!/usr/bin/env bash' ]] && pass "$rel : #!/usr/bin/env bash" \
      || fail "$rel : #!/usr/bin/env bash" "$(head -n 1 "$script")" ;;
  esac
done
for script in "$PLUGIN_ROOT"/scripts/*.sh ${tools[@]+"${tools[@]}"} "$PLUGIN_ROOT"/hooks/scripts/*.sh; do
  name=${script##*/}
  grep -qF "\${CLAUDE_PLUGIN_ROOT}/${script#"$PLUGIN_ROOT"/}" "${substituted[@]}" "$PLUGIN_ROOT"/hooks/hooks.json ${mcp[@]+"${mcp[@]}"} /dev/null \
    && pass "$name est cité par \${CLAUDE_PLUGIN_ROOT}" || fail "$name est cité par \${CLAUDE_PLUGIN_ROOT}"
done

# The fact base describes these paths, it does not use them: scripts/facts/ is left out.
components=()
for dir in agents skills hooks scripts templates; do [[ -d $PLUGIN_ROOT/$dir ]] && components+=("$PLUGIN_ROOT/$dir"); done
components+=(${mcp[@]+"${mcp[@]}"})
bin_bash=$(grep -rn --exclude-dir=facts '/bin/bash' ${components[@]+"${components[@]}"} /dev/null 2>/dev/null)
[[ -z $bin_bash ]] && pass "aucun /bin/bash (absent sous NixOS)" || fail "aucun /bin/bash (absent sous NixOS)" "$bin_bash"
personal=$(grep -rnE --exclude-dir=facts '/(home|Users)/|/nix/(store)/' ${components[@]+"${components[@]}"} /dev/null 2>/dev/null)
[[ -z $personal ]] && pass "aucun chemin personnel ni du store" || fail "aucun chemin personnel ni du store" "$personal"
shopt -u nullglob

finish
