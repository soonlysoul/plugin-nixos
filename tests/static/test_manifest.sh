#!/usr/bin/env bash
# plugin.json and marketplace.json at the model of plugin-flutter, and the files every plugin
# of the model carries at its root: LICENSE, README, CHANGELOG, .gitignore, no CLAUDE.md.
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
SUITE=test_manifest
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
MARKET_JSON="$PLUGIN_ROOT/.claude-plugin/marketplace.json"
NAME=plugin-nixos
REPOSITORY="https://github.com/soonlysoul/$NAME"

# check <label> <jq filter returning true> <file>
check() {
  if jq -e "$2" "$3" >/dev/null 2>&1; then pass "$1"; else fail "$1" "$(jq -c "$2" "$3" 2>&1 | head -c 200)"; fi
}

echo "# plugin.json"
if [[ ! -f $PLUGIN_JSON ]]; then
  fail "plugin.json présent" "manifeste absent : .claude-plugin/plugin.json"
elif ! jq -e . "$PLUGIN_JSON" >/dev/null 2>&1; then
  fail "plugin.json est du JSON valide" "$PLUGIN_JSON"
else
  pass "plugin.json est du JSON valide"
  check "name est $NAME" ".name == \"$NAME\"" "$PLUGIN_JSON"
  check "name suit plugin-<domaine>" '.name | type == "string" and test("^plugin-[a-z0-9]+(-[a-z0-9]+)*$")' "$PLUGIN_JSON"
  check "version est SemVer" '.version | type == "string" and test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$")' "$PLUGIN_JSON"
  check "description non vide" '.description | type == "string" and length > 0' "$PLUGIN_JSON"
  check "author.name est Soon" '.author.name == "Soon"' "$PLUGIN_JSON"
  check "author sans e-mail" '.author | keys == ["name"]' "$PLUGIN_JSON"
  check "license est MIT" '.license == "MIT"' "$PLUGIN_JSON"
  check "homepage est le dépôt GitHub" ".homepage == \"$REPOSITORY\"" "$PLUGIN_JSON"
  check "repository est le dépôt GitHub" ".repository == \"$REPOSITORY\"" "$PLUGIN_JSON"
  check "aucun champ inconnu" '(keys - ["name", "version", "description", "author", "license", "keywords", "homepage", "repository"]) == []' "$PLUGIN_JSON"
  grep -q '@' "$PLUGIN_JSON" && fail "aucune adresse e-mail dans plugin.json" "$(grep -n '@' "$PLUGIN_JSON")" \
    || pass "aucune adresse e-mail dans plugin.json"
fi

echo "# marketplace.json"
if [[ ! -f $MARKET_JSON ]]; then
  fail "marketplace.json présent" "manifeste absent : .claude-plugin/marketplace.json"
elif ! jq -e . "$MARKET_JSON" >/dev/null 2>&1; then
  fail "marketplace.json est du JSON valide" "$MARKET_JSON"
else
  pass "marketplace.json est du JSON valide"
  check "name, owner.name, description et plugins présents" \
    '(.name | type == "string") and (.owner.name | type == "string") and (.description | type == "string") and (.plugins | type == "array")' "$MARKET_JSON"
  check "owner.name est Soon" '.owner.name == "Soon"' "$MARKET_JSON"
  check "une seule entrée" '.plugins | length == 1' "$MARKET_JSON"
  check "l'entrée pointe sur la racine du plugin" '.plugins[0].source == "./"' "$MARKET_JSON"
  check "l'entrée ne répète pas la version" '.plugins[0] | has("version") | not' "$MARKET_JSON"
  plugin_name=$(jq -r '.name // empty' "$PLUGIN_JSON" 2>/dev/null)
  entry_name=$(jq -r '.plugins[0].name // empty' "$MARKET_JSON")
  [[ -n $plugin_name && $plugin_name == "$entry_name" ]] && pass "le nom de l'entrée est celui de plugin.json ($entry_name)" \
    || fail "le nom de l'entrée est celui de plugin.json" "plugin.json : $plugin_name, entrée : $entry_name"
fi

echo "# fichiers à la racine"
[[ -f $PLUGIN_ROOT/LICENSE ]] && grep -q '^MIT License' "$PLUGIN_ROOT/LICENSE" && grep -q 'Copyright (c) [0-9]* Soon$' "$PLUGIN_ROOT/LICENSE" \
  && pass "LICENSE MIT au nom de Soon" || fail "LICENSE MIT au nom de Soon" "$PLUGIN_ROOT/LICENSE"
[[ -s $PLUGIN_ROOT/README.md ]] && pass "README.md présent" || fail "README.md présent"
version=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)
if [[ -f $PLUGIN_ROOT/CHANGELOG.md ]] && grep -q '^# Journal des versions' "$PLUGIN_ROOT/CHANGELOG.md"; then
  pass "CHANGELOG.md en français"
  [[ -n $version ]] && grep -qF "## [$version]" "$PLUGIN_ROOT/CHANGELOG.md" \
    && pass "CHANGELOG.md a une entrée pour la version $version" \
    || fail "CHANGELOG.md a une entrée pour la version de plugin.json" "version : ${version:-illisible}"
else
  fail "CHANGELOG.md en français" "absent, ou sans titre « # Journal des versions »"
fi
for pattern in 'build/' 'evals/**/results/'; do
  grep -qxF "$pattern" "$PLUGIN_ROOT/.gitignore" 2>/dev/null && pass ".gitignore ignore $pattern" \
    || fail ".gitignore ignore $pattern"
done
[[ ! -e $PLUGIN_ROOT/CLAUDE.md ]] && pass "aucun CLAUDE.md à la racine (non chargé, signalé)" \
  || fail "aucun CLAUDE.md à la racine (non chargé, signalé)"

finish
