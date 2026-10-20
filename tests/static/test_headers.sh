#!/usr/bin/env bash
# Skill and agent headers, read by a deliberately strict parser (tests/headers.sh). A plugin agent
# whose frontmatter does not parse loads with every field ignored, hence with every tool and no
# message, and the official validator accepts it: this test is the guard. Structure only: known
# keys, name, tools declared and known, never Agent, a reviewer without Write nor Edit, the
# report format, 1 536 characters, under 500 lines, no $0-$9.
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
SUITE=test_headers
HEADERS="$PLUGIN_ROOT/tests/headers.sh"

if [[ ! -f $HEADERS ]]; then
  fail "tests/headers.sh présent" "absent : $HEADERS"
  finish
  exit
fi
# shellcheck source=../headers.sh
source "$HEADERS"

echo "# l'analyseur strict refuse les en-têtes cassés"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
printf -- '---\nname: ok\ndescription: Un en-tête valide.\ntools: Read, Grep\n---\nCorps\n' >"$work/valid.md"
printf -- '---\nname: x\ndescription: [unclosed\n---\n' >"$work/bracket.md"
printf -- '---\nname: x\ndescription: Use when: anything\n---\n' >"$work/colon.md"
printf -- '---\nname: x\ntools:\n  - Read\n---\n' >"$work/list.md"
printf -- '---\nname: x\nname: y\n---\n' >"$work/duplicate.md"
printf -- '---\nname: x\ndescription: "unbalanced\n---\n' >"$work/quote.md"
printf -- '---\nname: x\ndescription: no end\n' >"$work/unclosed.md"
printf -- 'name: x\n---\n' >"$work/noopen.md"
read_frontmatter "$work/valid.md" && [[ ${FM[tools]} == "Read, Grep" ]] \
  && pass "un en-tête valide est lu" || fail "un en-tête valide est lu" "$FM_ERROR"
for broken in bracket colon list duplicate quote unclosed noopen; do
  if read_frontmatter "$work/$broken.md"; then fail "refuse $broken"; else pass "refuse $broken ($FM_ERROR)"; fi
done

echo "# skills et agents du plugin"
shopt -s nullglob
for file in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
  errors=$(skill_structure_errors "$file")
  [[ -z $errors ]] && pass "${file#"$PLUGIN_ROOT"/}" || fail "${file#"$PLUGIN_ROOT"/}" "$(tr '\n' ' ' <<<"$errors")"
done
for file in "$PLUGIN_ROOT"/agents/*.md; do
  errors=$(agent_structure_errors "$file")
  [[ -z $errors ]] && pass "${file#"$PLUGIN_ROOT"/}" || fail "${file#"$PLUGIN_ROOT"/}" "$(tr '\n' ' ' <<<"$errors")"
done
shopt -u nullglob

finish
