# shellcheck shell=bash disable=SC2034  # FM and FM_ERROR are read by the caller
# Strict reading of skill and agent headers, and the rules they follow. Shared by plugin-plugin's
# scripts/pp.sh and by the test suite of every plugin it creates, where it is copied as is.
# Structure rules hold for every plugin of the model, plugin-flutter included; style rules are
# the house style plugin-plugin applies to the components it adds.

KNOWN_TOOLS=" Read Grep Glob Bash Write Edit NotebookEdit WebFetch WebSearch TodoWrite Skill Monitor "

# read_frontmatter <file>: fills FM (key -> value), or sets FM_ERROR and returns 1.
# Accepted: line 1 is ---, then single-line `key: value` lines, then ---. An unquoted value
# contains neither ": " nor " #" and does not start with a YAML indicator; a quoted value is
# enclosed in matching quotes. Keys are unique.
read_frontmatter() {
  local file=$1 line key value closed=0 n=0
  declare -gA FM=()
  FM_ERROR=""
  while IFS= read -r line || [[ -n $line ]]; do
    n=$((n + 1))
    if ((n == 1)); then
      [[ $line == --- ]] || { FM_ERROR="la ligne 1 n'est pas ---"; return 1; }
      continue
    fi
    if [[ $line == --- ]]; then closed=1; break; fi
    if [[ ! $line =~ ^([a-zA-Z][a-zA-Z0-9_-]*):\ (.+)$ ]]; then
      FM_ERROR="la ligne $n n'est pas un « clé: valeur » sur une ligne : $line"; return 1
    fi
    key=${BASH_REMATCH[1]} value=${BASH_REMATCH[2]}
    [[ -z ${FM[$key]+set} ]] || { FM_ERROR="clé $key en double"; return 1; }
    case $value in
      \"*) [[ $value =~ ^\"[^\"]*\"$ ]] || { FM_ERROR="guillemets doubles déséquilibrés dans $key"; return 1; }; value=${value:1:-1} ;;
      \'*) [[ $value =~ ^\'[^\']*\'$ ]] || { FM_ERROR="guillemets simples déséquilibrés dans $key"; return 1; }; value=${value:1:-1} ;;
      [\[\]\{\}\&\*\!\|\>%@\`]*) FM_ERROR="$key commence par un indicateur YAML : $value"; return 1 ;;
      *': '* | *' #'*) FM_ERROR="$key non cité contient « : » ou « # » : $value"; return 1 ;;
    esac
    FM[$key]=$value
  done <"$file"
  ((closed)) || { FM_ERROR="l'en-tête n'est pas refermé par ---"; return 1; }
}

# body_of <file>: the Markdown after the frontmatter.
body_of() { awk 'n >= 2 { print } /^---$/ { n++ }' "$1"; }

# skill_structure_errors <SKILL.md>: one line per broken structure rule; nothing when it holds.
skill_structure_errors() {
  local file=$1 dir key listing lines
  dir=$(basename "$(dirname "$file")")
  read_frontmatter "$file" || { echo "en-tête illisible par l'analyseur strict : $FM_ERROR"; return; }
  for key in "${!FM[@]}"; do
    case $key in
      name | description | argument-hint | when_to_use | disable-model-invocation | user-invocable) ;;
      allowed-tools) echo "allowed-tools accorde des outils sans demander et ne restreint rien : à retirer" ;;
      *) echo "clé inconnue : $key" ;;
    esac
  done
  [[ ${FM[name]-} == "$dir" ]] || echo "le nom « ${FM[name]-} » n'est pas celui du dossier « $dir »"
  [[ -n ${FM[description]-} ]] || echo "description absente"
  listing="${FM[description]-}${FM[when_to_use]-}"
  ((${#listing} <= 1536)) || echo "description et when_to_use font ${#listing} caractères, au-delà de 1 536"
  lines=$(wc -l <"$file")
  ((lines < 500)) || echo "$lines lignes : 500 lignes ou plus, détails à mettre dans reference/"
  if grep -qE '\$[0-9]' "$file"; then
    echo "\$0-\$9 présent, substitué comme argument du skill : $(grep -nE '\$[0-9]' "$file" | head -n 1)"
  fi
}

# skill_style_errors <SKILL.md>: one line per broken rule of the house style.
skill_style_errors() {
  local key
  read_frontmatter "$1" || return 0
  for key in argument-hint when_to_use; do
    [[ -n ${FM[$key]-} ]] || echo "$key absent"
  done
  [[ ${FM[description]-} == *"Use when"* ]] || echo "la description ne dit pas « Use when … »"
  [[ ${FM[description]-} == *"not for"* ]] || echo "la description ne dit pas « not for … »"
  [[ ${FM[description]-} =~ «\ [^»]+\ » ]] || echo "la description ne cite aucune phrase de déclenchement en français (« … »)"
}

# agent_structure_errors <agents/NAME.md>: one line per broken structure rule.
agent_structure_errors() {
  local file=$1 name key tool body field
  local -a tools
  name=$(basename "$file" .md)
  read_frontmatter "$file" || { echo "en-tête illisible par l'analyseur strict : $FM_ERROR (l'agent recevrait tous les outils)"; return; }
  for key in "${!FM[@]}"; do
    case $key in name | description | tools | model | color) ;; *) echo "clé inconnue : $key" ;; esac
  done
  [[ ${FM[name]-} == "$name" ]] || echo "le nom « ${FM[name]-} » n'est pas celui du fichier « $name »"
  [[ -n ${FM[description]-} ]] || echo "description absente"
  [[ -n ${FM[model]-} ]] || echo "model absent"
  if [[ -z ${FM[tools]-} ]]; then
    echo "tools absent : sans lui, l'agent hérite de tous les outils"
  else
    IFS=',' read -ra tools <<<"${FM[tools]}"
    for tool in "${tools[@]}"; do
      tool=${tool// /}
      if [[ $tool == Agent ]]; then echo "outil Agent interdit : un agent du plugin ne lance pas d'agent"
      elif [[ $KNOWN_TOOLS != *" $tool "* ]]; then echo "outil inconnu : $tool"
      elif [[ $name == *review* && $tool =~ ^(Write|Edit|NotebookEdit)$ ]]; then echo "un relecteur n'a ni Write ni Edit : $tool"
      fi
    done
  fi
  body=$(body_of "$file")
  for field in STATUS FILES_CHANGED COMMANDS_RUN OPEN_QUESTIONS; do
    [[ $body == *"$field"* ]] || echo "format de rapport incomplet : $field absent"
  done
}

# agent_style_errors <agents/NAME.md>: one line per broken rule of the house style.
agent_style_errors() {
  local file=$1 name description body section
  read_frontmatter "$file" || return 0
  name=$(basename "$file" .md)
  description=${FM[description]-}
  [[ $name =~ ^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$ ]] \
    || echo "nom « $name » : 3 à 50 caractères, commençant et finissant par une lettre ou un chiffre"
  [[ $description == "Use this agent when"* ]] || echo "la description ne commence pas par « Use this agent when »"
  [[ $description == *"not for"* ]] || echo "la description ne dit pas « not for … »"
  ((${#description} >= 200 && ${#description} <= 1000)) || echo "description de ${#description} caractères ; 200 à 1 000 attendus"
  body=$(body_of "$file")
  for section in Responsibilities Approach "Output format"; do
    grep -qx "## $section" <<<"$body" || echo "corps sans section « ## $section »"
  done
}
