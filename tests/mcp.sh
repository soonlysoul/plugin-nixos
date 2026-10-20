# shellcheck shell=bash
# Rules of an MCP server declaration (.mcp.json). Shared by plugin-plugin's scripts/pp.sh, which
# refuses to write a declaration that breaks them, and by test_paths.sh of every plugin it creates,
# where it is copied as is and checks what is declared, by hand included. Each function takes one
# server entry of .mcp.json, as JSON, and prints why it breaks the rule; nothing when it holds.

# A command that installs at startup: package managers, and runners that fetch a package.
IMPERATIVE_INSTALL='(^|[^[:alnum:]_-])((npm|pnpm|yarn|bun) +(install|i|add|ci)|pip3? +install|pipx +(install|run)|uv +(pip +install|tool +install|add|sync)|npx|pnpx|bunx|uvx|(cargo|go|gem) +install|nix-env +-i|nix +profile +install)([^[:alnum:]_-]|$)'

# mcp_strings <entry>: every string value of the entry, one per line.
mcp_strings() { jq -r '[.. | strings] | join("\n")' <<<"$1"; }

# mcp_launcher_error <entry>: a local server runs a bash script of scripts/, cited by
# ${CLAUDE_PLUGIN_ROOT}, without the execute bit, as hooks do.
mcp_launcher_error() {
  local command launcher pattern='^\$\{CLAUDE_PLUGIN_ROOT\}/scripts/[A-Za-z0-9_.-]+\.sh$'
  command=$(jq -r '.command // empty' <<<"$1")
  [[ -n $command ]] || return 0
  launcher=$(jq -r '.args[0] // ""' <<<"$1")
  [[ $command == bash && $launcher =~ $pattern ]] \
    || echo "command « $command », args[0] « $launcher » : attendu bash et \${CLAUDE_PLUGIN_ROOT}/scripts/<nom>.sh"
}

# mcp_remote_error <entry>: a remote server is reached in HTTPS or WSS.
mcp_remote_error() {
  local url
  url=$(jq -r '.url // empty' <<<"$1")
  [[ -z $url || $url == https://* || $url == wss://* ]] || echo "adresse « $url » : HTTPS ou WSS seulement"
}

# mcp_install_error <entry> <plugin root>: nothing installs at startup, neither in the command
# nor in the launcher it runs.
mcp_install_error() {
  local text launcher found
  text=$(jq -r '[.command // empty] + (.args // []) | join(" ")' <<<"$1")
  launcher=$(jq -r '.args[0] // ""' <<<"$1")
  if [[ $launcher == '${CLAUDE_PLUGIN_ROOT}/'* && -f $2/${launcher#'${CLAUDE_PLUGIN_ROOT}/'} ]]; then
    text+=$'\n'$(<"$2/${launcher#'${CLAUDE_PLUGIN_ROOT}/'}")
  fi
  found=$(grep -oE "$IMPERATIVE_INSTALL" <<<"$text" | head -n 1 | sed -E 's/^[^[:alnum:]]+//; s/[^[:alnum:]]+$//')
  [[ -z $found ]] || echo "installation impérative au démarrage : « $found »"
}

# mcp_variable_error <entry>: every value of the user's environment is written ${VAR}.
mcp_variable_error() {
  local rest
  rest=$(mcp_strings "$1" | sed -E 's/\$\{[A-Z_][A-Z0-9_]*\}//g')
  [[ $rest != *'$'* ]] || echo "variable hors \${VAR}, en majuscules : « $(grep -m 1 -F '$' <<<"$rest") »"
}

# mcp_secret_error <entry>: no secret written in clear. Once the ${VAR} are taken out, no run of 20
# letters, digits, - or _ mixing letters and digits; no sensitive header or URL parameter whose
# value is not a ${VAR}. The secret itself is never printed.
mcp_secret_error() {
  local run name value url query='[?&][^=&]*(token|key|secret|password)[^=&]*=[^$&]'
  while IFS= read -r run; do
    [[ $run =~ [0-9] && $run =~ [A-Za-z] ]] && { echo "secret écrit en clair : le passer par \${VAR}"; return; }
  done < <(mcp_strings "$1" | sed -E 's/\$\{[^}]*\}//g' | grep -oE '[A-Za-z0-9_-]{20,}')
  while IFS=$'\t' read -r name value; do
    if [[ ${name,,} =~ authorization|cookie|token|secret|key|password && $value != *'${'* ]]; then
      echo "secret écrit en clair dans l'en-tête $name : le passer par \${VAR}"
      return
    fi
  done < <(jq -r '(.headers // {}) | to_entries[] | [.key, .value] | @tsv' <<<"$1")
  url=$(jq -r '.url // ""' <<<"$1")
  [[ ! ${url,,} =~ $query ]] || echo "secret écrit en clair dans l'adresse : le passer par \${VAR}"
}

# mcp_variables <entry>: the user's variables the entry reads, in order, one per line.
mcp_variables() {
  mcp_strings "$1" | grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' | sed -E 's/^\$\{//; s/\}$//' \
    | grep -vxE 'CLAUDE_PLUGIN_ROOT|CLAUDE_PLUGIN_DATA' | awk '!seen[$0]++'
}
