#!/usr/bin/env bash
# Les variables posées ici sont lues par les conditions que « attendre » évalue,
# et par les suites qui sourcent lib.sh : shellcheck ne suit ni l'un ni l'autre.
# shellcheck disable=SC2034
# Aides communes aux suites : bash + jq, sans réseau, sans session Claude.
# Sourcer depuis une suite, poser SUITE, appeler les assertions, finir par terminer.

# NIXOS_PLUGIN_RACINE fait juger une copie modifiée du plugin — c'est ainsi qu'on
# vérifie qu'un test discrimine : un garde qui laisse tout passer doit faire
# échouer les « refuse ».
RACINE=${NIXOS_PLUGIN_RACINE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
GARDE="$RACINE/hooks/garde-nixos.sh"
NIXCONF="$RACINE/scripts/nixconf"
OK=0
KO=0
SAUTE=0

# Une suite ne dépend pas de la session qui la lance.
unset CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA NIXOS_CONF NIX_CONFIG

reussi() {
  OK=$((OK + 1))
  printf '  ok     %s\n' "$1"
}
echoue() {
  KO=$((KO + 1))
  printf '  ÉCHEC  %s\n' "$1"
  if [ -n "${2:-}" ]; then printf '         %s\n' "$2"; fi
}
saute() {
  SAUTE=$((SAUTE + 1))
  printf '  sauté  %s (%s)\n' "$1" "$2"
}

# L'entrée PreToolUse que Claude Code passerait au garde.
entree_outil() {
  jq -nc --arg c "$1" --arg t "${2:-Bash}" \
    '{session_id: "test", hook_event_name: "PreToolUse", cwd: "/tmp",
      tool_name: $t, tool_input: {command: $c}}'
}

# juger <commande> [outil] — pose STATUT et SORTIE (le stderr du garde).
juger() {
  local err
  err=$(mktemp)
  entree_outil "$1" "${2:-Bash}" | bash "$GARDE" 2> "$err" > /dev/null
  STATUT=$?
  SORTIE=$(< "$err")
  rm -f "$err"
}

passe() {
  juger "$1" "${2:-Bash}"
  if [ "$STATUT" -eq 0 ]; then
    reussi "passe   : $1"
  else
    echoue "passe   : $1" "refusé à tort (sortie $STATUT) : ${SORTIE:0:300}"
  fi
}

refuse() {
  juger "$1" "${2:-Bash}"
  if [ "$STATUT" -eq 2 ] && [ -n "$SORTIE" ]; then
    reussi "refuse  : $1"
  else
    echoue "refuse  : $1" "laissé passer (sortie $STATUT)"
  fi
}

# Un répertoire de PATH qui ne contient QUE les outils nommés : c'est ainsi
# qu'on simule un poste où il manque jq, ou tout. Affiche le répertoire.
chemin_restreint() {
  local rep outil
  rep=$(mktemp -d)
  for outil in "$@"; do
    if command -v "$outil" > /dev/null 2>&1; then
      ln -s "$(command -v "$outil")" "$rep/$outil"
    fi
  done
  printf '%s' "$rep"
}

# attendre <libellé> <condition shell> — une assertion libre.
attendre() {
  if eval "$2"; then reussi "$1"; else echoue "$1" "condition fausse : $2"; fi
}

terminer() {
  printf '%s : %d réussis, %d échoués, %d sautés\n' "$SUITE" "$OK" "$KO" "$SAUTE"
  [ "$KO" -eq 0 ]
}
