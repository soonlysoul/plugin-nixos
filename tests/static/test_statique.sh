#!/usr/bin/env bash
# Les variables posées ici sont lues par les conditions que « attendre » évalue,
# et par les suites qui sourcent lib.sh : shellcheck ne suit ni l'un ni l'autre.
# shellcheck disable=SC2034
# Ce qui se vérifie sans rien lancer : manifestes, frontmatter des skills,
# chemins que les skills et les hooks citent, syntaxe des scripts.
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
SUITE=test_statique
# Portage au harnais du modèle (plugin-plugin, phase 14) : les cas
# d'origine, mot pour mot, sur les aides de tests/lib.sh.
attendre() { if eval "$2"; then pass "$1"; else fail "$1" "condition fausse : $2"; fi; }
NIXCONF="$PLUGIN_ROOT/scripts/nixconf"

PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
MARKET_JSON="$PLUGIN_ROOT/.claude-plugin/marketplace.json"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"
MCP_JSON="$PLUGIN_ROOT/.mcp.json"

# verifier_json <libellé> <filtre jq rendant true> <fichier>
verifier_json() {
  if jq -e "$2" "$3" > /dev/null 2>&1; then
    pass "$1"
  else
    fail "$1" "$(jq -c "$2" "$3" 2>&1 | head -c 200)"
  fi
}

echo "# plugin.json"
verifier_json "JSON valide" '.' "$PLUGIN_JSON"
verifier_json "nom en kebab-case" '.name | test("^[a-z0-9]+(-[a-z0-9]+)*$")' "$PLUGIN_JSON"
verifier_json "version SemVer" '.version | test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")' "$PLUGIN_JSON"
verifier_json "description, auteur, licence MIT" '(.description | length > 0) and (.author.name | length > 0) and .license == "MIT"' "$PLUGIN_JSON"
verifier_json "aucune adresse électronique publiée" '[.. | strings | select(test("@[a-z0-9-]+\\."))] | length == 0' "$PLUGIN_JSON"
verifier_json "seulement des champs connus" '(keys - ["name", "version", "description", "author", "license", "keywords", "homepage", "repository"]) == []' "$PLUGIN_JSON"
# Le dépôt GitHub porte le nom du plugin : soonlysoul/<name>.
verifier_json "homepage et repository : le dépôt soonlysoul/<name>" '.homepage == "https://github.com/soonlysoul/\(.name)" and .repository == .homepage' "$PLUGIN_JSON"

echo "# marketplace.json (locale, pour l'essayer depuis une copie)"
verifier_json "JSON valide, une entrée qui pointe sur la racine" '(.plugins | length == 1) and .plugins[0].source == "./"' "$MARKET_JSON"
verifier_json "l'entrée ne répète pas la version" '.plugins[0] | has("version") | not' "$MARKET_JSON"
nom_plugin=$(jq -r .name "$PLUGIN_JSON")
nom_entree=$(jq -r '.plugins[0].name' "$MARKET_JSON")
attendre "l'entrée porte le nom du plugin ($nom_entree)" '[ "$nom_plugin" = "$nom_entree" ]'

echo "# hooks.json et .mcp.json"
verifier_json "hooks.json : un PreToolUse sur Bash|Monitor" '.hooks.PreToolUse[0].matcher == "Bash|Monitor"' "$HOOKS_JSON"
# La forme exec du modèle — Claude Code 2.1.295 au moins — et onFailure block :
# le garde est fail-closed.
verifier_json "hooks.json : forme exec, le garde dans args, onFailure block" '.hooks.PreToolUse[0].hooks[0] | .command == "bash" and .args == ["${CLAUDE_PLUGIN_ROOT}/hooks/scripts/garde-nixos.sh"] and .onFailure == "block"' "$HOOKS_JSON"
while IFS= read -r cible; do
  chemin="$PLUGIN_ROOT/${cible#\$\{CLAUDE_PLUGIN_ROOT\}/}"
  attendre "le hook cite un fichier qui existe : ${cible}" '[ -f "$chemin" ]'
done < <(jq -r '.. | objects | (.command, .args[]?) | strings' "$HOOKS_JSON" | grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}/[^"]+')
verifier_json ".mcp.json : le serveur nixos passe par son lanceur" '.mcpServers.nixos.args[0] == "${CLAUDE_PLUGIN_ROOT}/scripts/mcp-nixos.sh"' "$MCP_JSON"

echo "# skills"
for skill in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
  nom=$(basename "$(dirname "$skill")")
  entete=$(awk 'NR == 1 && $0 == "---" { dans = 1; next } dans && $0 == "---" { exit } dans' "$skill")
  attendre "$nom : name = son répertoire" '[ "$(printf "%s\n" "$entete" | sed -n "s/^name: //p")" = "$nom" ]'
  attendre "$nom : une description" 'printf "%s\n" "$entete" | grep -q "^description: \"..*\"$"'
  attendre "$nom : la description reste sous 1024 caractères" '[ "$(printf "%s\n" "$entete" | sed -n "s/^description: //p" | wc -m)" -le 1024 ]'
  while IFS= read -r cible; do
    chemin="$PLUGIN_ROOT/${cible#\$\{CLAUDE_PLUGIN_ROOT\}/}"
    attendre "$nom cite un fichier qui existe : $cible" '[ -e "$chemin" ]'
  done < <(grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' "$skill" | sort -u)
  # Chaque sous-commande de nixconf citée par une skill doit exister.
  while IFS= read -r sous; do
    attendre "$nom cite « nixconf $sous », qui existe" 'grep -q "^  $sous) cmd_" "$NIXCONF"'
  done < <(grep -oE 'nixconf"? [a-z]+' "$skill" | awk '{ print $2 }' | sort -u)
done

echo "# le nom du plugin, là où l'utilisateur le tape"
# Le préfixe d'une skill est le nom du plugin : un « /ancien-nom:… » oublié
# après un renommage désigne une commande qui n'existe plus.
skills_connues=$(find "$PLUGIN_ROOT/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | paste -sd '|')
while IFS= read -r appel; do
  attendre "« $appel » porte le nom du plugin" '[ "${appel%%:*}" = "/$nom_plugin" ]'
done < <(grep -ohE "/[a-z0-9-]+:($skills_connues)\b" "$PLUGIN_ROOT"/skills/*/SKILL.md "$PLUGIN_ROOT"/README.md | sort -u)
while IFS= read -r installation; do
  attendre "« $installation » porte le nom du plugin" '[ "${installation#install }" = "$nom_plugin@soon" ]'
done < <(grep -ohE 'install [a-z0-9-]+@soon' "$PLUGIN_ROOT"/README.md | sort -u)

echo "# la première session d'un poste neuf"
# « nixpkgs#claude-code » suit le registre du poste, qui peut désigner le canal
# stable — et nixpkgs 25.05 fournit claude-code 1.0.85, qui n'a pas de
# commande « plugin » (mesuré le 2026-10-19). Le README le prend donc à la
# révision que le lanceur MCP épingle déjà : une seule révision à télécharger,
# et à faire avancer.
revision=$(sed -n 's/^readonly REVISION="\([0-9a-f]*\)"$/\1/p' "$PLUGIN_ROOT/scripts/mcp-nixos.sh")
attendre "le lanceur MCP épingle une révision ($revision)" '[[ "$revision" =~ ^[0-9a-f]{40}$ ]]'
attendre "le README prend claude-code à cette révision" 'grep -q "github:NixOS/nixpkgs/$revision" "$PLUGIN_ROOT/README.md"'
attendre "le README ne prend pas claude-code au registre du poste" '! grep -q "nixpkgs#claude-code" "$PLUGIN_ROOT/README.md"'

echo "# scripts"
for script in "$PLUGIN_ROOT"/hooks/scripts/*.sh "$PLUGIN_ROOT"/hooks/scripts/lib/*.sh "$PLUGIN_ROOT"/scripts/* "$PLUGIN_ROOT"/tests/*.sh "$PLUGIN_ROOT"/tests/*/*.sh; do
  [ -f "$script" ] || continue
  attendre "syntaxe bash : ${script#"$PLUGIN_ROOT"/}" 'bash -n "$script"'
done
for script in "$PLUGIN_ROOT"/hooks/scripts/garde-nixos.sh "$PLUGIN_ROOT"/scripts/nixconf "$PLUGIN_ROOT"/scripts/mcp-nixos.sh; do
  attendre "exécutable : ${script#"$PLUGIN_ROOT"/}" '[ -x "$script" ]'
done
if command -v shellcheck > /dev/null 2>&1; then
  for script in "$PLUGIN_ROOT"/hooks/scripts/*.sh "$PLUGIN_ROOT"/hooks/scripts/lib/*.sh "$PLUGIN_ROOT"/scripts/*; do
    [ -f "$script" ] || continue
    attendre "shellcheck : ${script#"$PLUGIN_ROOT"/}" 'shellcheck -S warning -x "$script" > /dev/null'
  done
else
  skip "shellcheck" "absent du PATH"
fi

echo "# ce qui ne doit pas être là"
attendre "pas de CLAUDE.md à la racine du plugin (il ne serait pas chargé)" '[ ! -e "$PLUGIN_ROOT/CLAUDE.md" ]'
attendre "aucun chemin personnel dans ce qui est distribué" '! grep -rnE "/home/[a-z]+/" "$PLUGIN_ROOT/skills" "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/.mcp.json"'

finish
