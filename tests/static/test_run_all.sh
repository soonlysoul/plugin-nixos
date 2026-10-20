#!/usr/bin/env bash
# tests/run-all.sh itself: its exit codes (0, 1, 2), a missing component directory skipped and
# never passed, the validator and the context cost blocked without claude, the cost budget.
# Each case runs the suite of a copy of the plugin, without this file, against a claude stub.
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
SUITE=test_run_all

# The cases copy the plugin this test is pointed at: anything but a plugin stops it before any
# copy — an empty PLUGIN_ROOT would make it copy /.
if [[ -z ${PLUGIN_ROOT:-} || ! -f $PLUGIN_ROOT/.claude-plugin/plugin.json ]]; then
  echo "bloqué : PLUGIN_ROOT « ${PLUGIN_ROOT:-} » n'est pas un plugin (.claude-plugin/plugin.json absent) ; rien n'est copié." >&2
  exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A claude stub: validation passes, plugin details reports STUB_ALWAYS_ON tokens.
mkdir "$work/stub"
cat >"$work/stub/claude" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *" plugin validate "*) echo "✔ Validation passed" ;;
  *" plugin details "*) printf 'Projected token cost\n  Always-on:   ~%s tok   added to every session\n' "${STUB_ALWAYS_ON:-0}" ;;
  *) echo "claude stub: unexpected arguments: $*" >&2; exit 3 ;;
esac
EOF
chmod +x "$work/stub/claude"

# copy_plugin <name>: a copy of the plugin without VCS nor build output.
copy_plugin() {
  local copy="$work/$1" entry
  mkdir "$copy"
  for entry in "$PLUGIN_ROOT"/* "$PLUGIN_ROOT"/.[!.]*; do
    case ${entry##*/} in .git | build | .superpowers | .shots) continue ;; esac
    cp -R "$entry" "$copy/"
  done
  # Neither this test (it would recurse) nor its guard's, nor the integration tests, which create
  # plugins and need claude: the copies only exercise run-all.sh.
  rm -rf "$copy/tests/static/test_run_all.sh" "$copy/tests/static/test_run_all_guard.sh" "$copy/tests/integration"
  printf '%s' "$copy"
}

# run_suite <copy> [env assignments...]: sets RUN_STATUS and RUN_OUTPUT (stdout and stderr).
run_suite() {
  local copy=$1
  shift
  RUN_OUTPUT=$(env "$@" "$BASH" "$copy/tests/run-all.sh" 2>&1)
  RUN_STATUS=$?
}

expect_run() {
  if [[ $RUN_STATUS == "$2" ]]; then pass "$1"; else fail "$1" "attendu exit $2, obtenu $RUN_STATUS ; sortie : $(tail -n 12 <<<"$RUN_OUTPUT" | tr '\n' '|')"; fi
}
expect_output() {
  if grep -qE -- "$2" <<<"$RUN_OUTPUT"; then pass "$1"; else fail "$1" "motif absent : $2"; fi
}
refuse_output() {
  if grep -qE -- "$2" <<<"$RUN_OUTPUT"; then fail "$1" "motif présent : $2"; else pass "$1"; fi
}

echo "# copie intacte"
intact=$(copy_plugin intact)
run_suite "$intact" PATH="$work/stub:$PATH" STUB_ALWAYS_ON=840
expect_run "copie intacte : exit 0" 0
expect_output "le bilan compte zéro échec" '^échouées : 0$'
expect_output "le coût permanent est affiché" 'ok +coût permanent : 840 tokens \(seuil 1000\)'

run_suite "$intact" PATH="$work/stub:$PATH" PLUGIN_UNDER_TEST="$work/nope"
expect_run "PLUGIN_UNDER_TEST hérité : la suite vérifie quand même son propre dossier" 0

echo "# dossiers de composants absents"
bare=$(copy_plugin bare)
rm -rf "$bare/skills" "$bare/agents"
run_suite "$bare" PATH="$work/stub:$PATH"
expect_output "skills/ absent : sauté" 'sauté +skills \(absent\)'
expect_output "agents/ absent : sauté" 'sauté +agents \(absent\)'
refuse_output "skills/ absent : jamais réussi" 'ok +skills$'

echo "# manifeste faussé ou absent"
falsified=$(copy_plugin falsified)
jq '.license = "Apache-2.0"' "$PLUGIN_ROOT/.claude-plugin/plugin.json" >"$falsified/.claude-plugin/plugin.json" 2>/dev/null \
  || echo '{}' >"$falsified/.claude-plugin/plugin.json"
run_suite "$falsified" PATH="$work/stub:$PATH"
expect_run "manifeste faussé : exit 1" 1
expect_output "la suite qui échoue est nommée au bilan" '^  - tests/static/test_manifest\.sh$'
missing=$(copy_plugin missing)
rm -f "$missing/.claude-plugin/plugin.json"
run_suite "$missing" PATH="$work/stub:$PATH"
expect_run "manifeste absent : exit 1" 1
expect_output "le manifeste absent est nommé au bilan" '^  - claude plugin validate \.claude-plugin/plugin\.json --strict \(\.claude-plugin/plugin\.json absent\)$'
expect_output "manifeste absent : sa validation échoue" 'ÉCHEC +\.claude-plugin/plugin\.json \(absent\)'
refuse_output "manifeste absent : sa validation n'est jamais sautée" 'sauté +\.claude-plugin/plugin\.json'

echo "# prérequis manquants"
no_jq=$(path_without jq)
run_suite "$intact" PATH="$work/stub:$no_jq"
expect_run "jq absent : exit 2" 2
expect_output "jq absent : la cause est dite" 'bloqué : jq est requis'
rm -rf "$no_jq"
no_claude=$(path_without claude)
run_suite "$intact" PATH="$no_claude"
expect_run "claude absent : exit 2" 2
expect_output "claude absent : validation bloquée" 'claude plugin validate \(claude introuvable dans le PATH\)'
expect_output "claude absent : coût bloqué" 'coût en contexte \(claude introuvable dans le PATH\)'
refuse_output "claude absent : rien n'est réussi en silence" '^  ok +(\.|\.claude-plugin/plugin\.json|coût .*)$'
rm -rf "$no_claude"

echo "# budget de contexte"
# Beyond the budget, plugin-plugin's own suite fails (criterion 9); a plugin it produces is only
# alerted (PRD, « Coût en contexte »). OVER_BUDGET decides; each case sets it in its copy.
name=$(jq -r '.name // empty' "$PLUGIN_ROOT/.claude-plugin/plugin.json")
expected=alert
[[ $name == plugin-plugin ]] && expected=fail
grep -qx "OVER_BUDGET=$expected" "$PLUGIN_ROOT/tests/run-all.sh" \
  && pass "$name : au-delà du budget, OVER_BUDGET=$expected" || fail "$name : au-delà du budget, OVER_BUDGET=$expected" "$(grep -n '^OVER_BUDGET=' "$PLUGIN_ROOT/tests/run-all.sh")"
over_fail=$(copy_plugin over-fail) over_alert=$(copy_plugin over-alert)
sed -i 's/^OVER_BUDGET=.*/OVER_BUDGET=fail/' "$over_fail/tests/run-all.sh"
sed -i 's/^OVER_BUDGET=.*/OVER_BUDGET=alert/' "$over_alert/tests/run-all.sh"

run_suite "$over_fail" PATH="$work/stub:$PATH" STUB_ALWAYS_ON=1.2k
expect_run "OVER_BUDGET=fail, 1.2k tokens permanents : exit 1" 1
expect_output "le dépassement est nommé" 'coût permanent : 1200 tokens, au-delà du seuil de 1000'
expect_output "le dépassement est nommé au bilan" '^  - coût en contexte \(1200 tokens > 1000\)$'
run_suite "$over_alert" PATH="$work/stub:$PATH" STUB_ALWAYS_ON=1.2k
expect_run "OVER_BUDGET=alert, 1.2k tokens permanents : exit 0" 0
expect_output "l'alerte est dite" 'alerte +coût permanent : 1200 tokens, au-delà du seuil de 1000'
expect_output "l'alerte est comptée au bilan" '^alertes : 1$'
expect_output "l'alerte est nommée au bilan" '^  - coût en contexte \(1200 tokens > 1000\)$'
expect_output "l'alerte n'est pas un échec" '^échouées : 0$'
run_suite "$over_alert" PATH="$work/stub:$PATH" STUB_ALWAYS_ON=1,126
expect_output "~1,126 tok : 1126 tokens, séparateur de milliers lu" 'coût permanent : 1126 tokens, au-delà du seuil de 1000'
run_suite "$over_fail" PATH="$work/stub:$PATH" STUB_ALWAYS_ON=1k
expect_run "1k tokens permanents, au seuil : exit 0" 0
expect_output "au seuil : aucune alerte" '^alertes : 0$'

finish
