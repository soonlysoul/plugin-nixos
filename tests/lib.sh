# shellcheck shell=bash disable=SC2034  # variables set here are read by the sourcing test
# Shared helpers for the deterministic test suite: bash + jq, no network, no Claude session.
# Source it from a test file, set SUITE, call the assertions, end with `finish`.

# PLUGIN_UNDER_TEST points a test at a mutated copy of the plugin, to prove it fails there.
PLUGIN_ROOT=${PLUGIN_UNDER_TEST:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
SCRIPTS="$PLUGIN_ROOT/hooks/scripts"
PASS=0 FAIL=0 SKIP=0

# The suite must not depend on the session it runs from.
unset CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA

pass() { PASS=$((PASS + 1)); printf '  ok     %s\n' "$1"; }
fail() {
  FAIL=$((FAIL + 1)); printf '  ÉCHEC  %s\n' "$1"
  if [[ -n ${2:-} ]]; then printf '         %s\n' "$2"; fi
}
skip() { SKIP=$((SKIP + 1)); printf '  sauté  %s (%s)\n' "$1" "$2"; }

# run_hook <script> <stdin> [env assignments...]
# Sets HOOK_STATUS, HOOK_STDOUT and HOOK_STDERR.
run_hook() {
  local script=$1 input=$2 out err
  shift 2
  out=$(mktemp) err=$(mktemp)
  printf '%s' "$input" | env "$@" "$BASH" "$script" >"$out" 2>"$err"
  HOOK_STATUS=$?
  HOOK_STDOUT=$(<"$out") HOOK_STDERR=$(<"$err")
  rm -f "$out" "$err"
}

# expect_status <label> <expected exit code>, after run_hook.
expect_status() {
  if [[ $HOOK_STATUS == "$2" ]]; then
    pass "$1"
  else
    fail "$1" "attendu exit $2, obtenu $HOOK_STATUS ; stderr : ${HOOK_STDERR:0:300}"
  fi
}

# expect_blocked <label>: exit 2 with a reason on stderr.
expect_blocked() {
  if [[ $HOOK_STATUS == 2 && -n $HOOK_STDERR ]]; then
    pass "$1"
  else
    fail "$1" "attendu exit 2 avec une raison, obtenu exit $HOOK_STATUS ; stderr : ${HOOK_STDERR:0:300}"
  fi
}

# expect_silent_allow <label>: exit 0, nothing on stdout or stderr.
expect_silent_allow() {
  if [[ $HOOK_STATUS == 0 && -z $HOOK_STDOUT && -z $HOOK_STDERR ]]; then
    pass "$1"
  else
    fail "$1" "attendu exit 0 silencieux, obtenu exit $HOOK_STATUS ; stdout : ${HOOK_STDOUT:0:200} ; stderr : ${HOOK_STDERR:0:200}"
  fi
}

# bash_input <command> [tool] [cwd]: PreToolUse input for a shell tool.
bash_input() {
  jq -nc --arg c "$1" --arg t "${2:-Bash}" --arg d "${3:-/work/proj}" \
    '{session_id: "test", cwd: $d, hook_event_name: "PreToolUse", permission_mode: "default",
      tool_name: $t, tool_input: {command: $c}, tool_use_id: "toolu_test"}'
}

# restricted_path <tool...>: a PATH holding only the named tools, to simulate a missing
# dependency. Prints the directory; the caller removes it.
restricted_path() {
  local dir tool
  dir=$(mktemp -d)
  for tool in "$@"; do
    ln -s "$(command -v "$tool")" "$dir/$tool"
  done
  printf '%s' "$dir"
}

# path_without <tool...>: a directory of links to every command of PATH except the named
# ones, first match winning as in PATH, to simulate a missing dependency.
# Prints the directory; the caller removes it.
path_without() {
  local dir entry name excluded
  local -a dirs batch
  dir=$(mktemp -d)
  IFS=: read -ra dirs <<<"$PATH"
  for entry in "${dirs[@]}"; do
    [[ -d $entry ]] || continue
    batch=()
    for name in "$entry"/*; do
      [[ -x $name && ! -d $name && ! -e $dir/${name##*/} ]] || continue
      for excluded in "$@"; do [[ ${name##*/} == "$excluded" ]] && continue 2; done
      batch+=("$name")
    done
    ((${#batch[@]} == 0)) || ln -s -t "$dir" -- "${batch[@]}" 2>/dev/null
  done
  printf '%s' "$dir"
}

finish() {
  printf '%s : %d réussis, %d échoués, %d sautés\n' "$SUITE" "$PASS" "$FAIL" "$SKIP"
  [[ $FAIL == 0 ]]
}
