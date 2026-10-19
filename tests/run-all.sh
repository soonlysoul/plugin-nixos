#!/usr/bin/env bash
# Les suites déterministes de plugin-nixos : bash + jq, sans réseau, sans
# session Claude, sans quota. Usage, de n'importe où : bash tests/run-all.sh
# Sorties : 0 toutes les suites passent, 1 une suite échoue, 2 un prérequis manque.
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

command -v jq > /dev/null 2>&1 || {
  echo "bloqué : les suites demandent jq, absent du PATH (nix shell nixpkgs#jq -c bash tests/run-all.sh)." >&2
  exit 2
}

reussies=()
echouees=()
bloquees=()

for suite in tests/test_*.sh; do
  printf '\n== %s\n' "$suite"
  if bash "$suite"; then reussies+=("$suite"); else echouees+=("$suite"); fi
done

# Le validateur officiel ne vérifie que ce que sa cible nomme : la racine est
# la marketplace locale, plugin.json le manifeste, skills/ les composants.
printf '\n== claude plugin validate\n'
if command -v claude > /dev/null 2>&1; then
  for cible in . .claude-plugin/plugin.json skills; do
    if sortie=$(claude plugin validate "$cible" --strict 2>&1); then
      printf '  ok     %s\n' "$cible"
      reussies+=("claude plugin validate $cible --strict")
    else
      printf '  ÉCHEC  %s\n%s\n' "$cible" "$sortie"
      echouees+=("claude plugin validate $cible --strict")
    fi
  done
else
  printf '  sauté  claude absent du PATH\n'
  bloquees+=("claude plugin validate (claude absent)")
fi

printf '\n== bilan\n'
printf 'réussies : %d\n' "${#reussies[@]}"
printf 'échouées : %d\n' "${#echouees[@]}"
for x in ${echouees[@]+"${echouees[@]}"}; do printf '  - %s\n' "$x"; done
printf 'bloquées : %d\n' "${#bloquees[@]}"
for x in ${bloquees[@]+"${bloquees[@]}"}; do printf '  - %s\n' "$x"; done
((${#echouees[@]} == 0))
