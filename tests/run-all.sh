#!/usr/bin/env bash
# Deterministic test suite of plugin-plugin: bash + jq, no network, no Claude session,
# no quota. Usage, from anywhere: bash tests/run-all.sh
# Exit codes: 0 every step passed, 1 a step failed, 2 a prerequisite is missing (a step is
# blocked, never counted as passed).
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
# The whole suite checks this directory: a mutated copy is targeted suite by suite, never here.
unset PLUGIN_UNDER_TEST

command -v jq >/dev/null 2>&1 || { echo "bloqué : jq est requis par la suite et introuvable dans le PATH." >&2; exit 2; }

# Always-on context budget of a plugin of the model (PRD, « Coût en contexte »). Beyond it,
# plugin-plugin's own suite fails (criterion 9); the scaffolding sets alert in the plugins it
# produces, whose suite says so and still passes.
MAX_ALWAYS_ON_TOKENS=1000
OVER_BUDGET=alert

passed=() failed=() skipped=() blocked=() alerts=()

shopt -s nullglob
for suite in tests/static/test_*.sh tests/hooks/test_*.sh tests/integration/test_*.sh tests/project/test_*.sh; do
  printf '\n== %s\n' "$suite"
  if bash "$suite"; then passed+=("$suite"); else failed+=("$suite"); fi
done
shopt -u nullglob

# The official validator only checks what its target names: the root is the marketplace
# manifest, plugin.json is the plugin manifest, agents/ and skills/ are the components.
# A missing manifest fails; only a missing component directory is skipped.
printf '\n== claude plugin validate --strict\n'
if command -v claude >/dev/null 2>&1; then
  for target in . .claude-plugin/plugin.json skills agents; do
    if [[ ! -e $target && $target == .claude-plugin/* ]]; then
      printf '  ÉCHEC  %s (absent)\n' "$target"
      failed+=("claude plugin validate $target --strict ($target absent)")
    elif [[ ! -e $target ]]; then
      printf '  sauté  %s (absent)\n' "$target"
      skipped+=("claude plugin validate $target --strict ($target absent)")
    elif output=$(claude plugin validate "$target" --strict 2>&1); then
      printf '  ok     %s\n' "$target"
      passed+=("claude plugin validate $target --strict")
    else
      printf '  ÉCHEC  %s\n%s\n' "$target" "$output"
      failed+=("claude plugin validate $target --strict")
    fi
  done
else
  printf '  bloqué claude introuvable dans le PATH\n'
  blocked+=("claude plugin validate (claude introuvable dans le PATH)")
fi

# Projected always-on cost, as `claude plugin details` reports it: ~841 tok, ~1,126 tok, ~1.2k tok.
printf '\n== coût en contexte permanent\n'
name=$(jq -r '.name // empty' .claude-plugin/plugin.json 2>/dev/null)
if ! command -v claude >/dev/null 2>&1; then
  printf '  bloqué claude introuvable dans le PATH\n'
  blocked+=("coût en contexte (claude introuvable dans le PATH)")
elif [[ -z $name ]]; then
  printf '  ÉCHEC  nom du plugin illisible dans .claude-plugin/plugin.json\n'
  failed+=("coût en contexte (nom illisible)")
elif ! output=$(claude --plugin-dir . plugin details "$name" 2>&1); then
  printf '  ÉCHEC  claude --plugin-dir . plugin details %s\n%s\n' "$name" "$output"
  failed+=("coût en contexte (plugin details a échoué)")
else
  tokens=$(sed -n 's/.*Always-on:[[:space:]]*~\([0-9.,]*k\{0,1\}\) tok.*/\1/p' <<<"$output" | head -n 1 | tr -d ,)
  tokens=$(awk -v t="$tokens" 'BEGIN { if (t == "") exit; n = t + 0; if (t ~ /k$/) n *= 1000; printf "%d", n }')
  if [[ -z $tokens ]]; then
    printf '  ÉCHEC  coût permanent illisible dans la sortie de plugin details\n%s\n' "$output"
    failed+=("coût en contexte (illisible)")
  elif ((tokens > MAX_ALWAYS_ON_TOKENS)) && [[ $OVER_BUDGET == alert ]]; then
    printf '  alerte coût permanent : %d tokens, au-delà du seuil de %d\n' "$tokens" "$MAX_ALWAYS_ON_TOKENS"
    alerts+=("coût en contexte ($tokens tokens > $MAX_ALWAYS_ON_TOKENS)")
  elif ((tokens > MAX_ALWAYS_ON_TOKENS)); then
    printf '  ÉCHEC  coût permanent : %d tokens, au-delà du seuil de %d\n' "$tokens" "$MAX_ALWAYS_ON_TOKENS"
    failed+=("coût en contexte ($tokens tokens > $MAX_ALWAYS_ON_TOKENS)")
  else
    printf '  ok     coût permanent : %d tokens (seuil %d)\n' "$tokens" "$MAX_ALWAYS_ON_TOKENS"
    passed+=("coût en contexte ($tokens tokens)")
  fi
fi

printf '\n== bilan\n'
printf 'réussies : %d\n' "${#passed[@]}"
printf 'échouées : %d\n' "${#failed[@]}"
for item in ${failed[@]+"${failed[@]}"}; do printf '  - %s\n' "$item"; done
printf 'sautées : %d\n' "${#skipped[@]}"
for item in ${skipped[@]+"${skipped[@]}"}; do printf '  - %s\n' "$item"; done
printf 'bloquées : %d\n' "${#blocked[@]}"
for item in ${blocked[@]+"${blocked[@]}"}; do printf '  - %s\n' "$item"; done
printf 'alertes : %d\n' "${#alerts[@]}"
for item in ${alerts[@]+"${alerts[@]}"}; do printf '  - %s\n' "$item"; done
((${#failed[@]} == 0)) || exit 1
((${#blocked[@]} == 0)) || exit 2
exit 0
