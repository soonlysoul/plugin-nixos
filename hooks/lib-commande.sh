#!/usr/bin/env bash
# Aide du garde de commandes — sourcée, jamais exécutée.
#
# Reprise de la bibliothèque du dépôt nixos-config (plugin/hooks/lib-commande.sh,
# 2026-10-15), avec quatre écarts, chacun motivé là où il est écrit :
#
#   lire_commande   ne dépend plus de jq : un NixOS fraîchement installé n'en a
#                   pas, et c'est précisément là que ce plugin doit servir ;
#   lire_commande   juge aussi l'outil Monitor, qui lance une commande comme Bash ;
#   executeur       « nix run », « nix shell » et « nix develop » lancent ce
#                   qu'on leur passe, comme « nix-shell --run » ;
#   executeur       run0, pkexec, systemd-run, flock, chroot, tmux… aussi.
#
# Et une correction : chaque test passe le texte à grep par une here-string, et
# non par « printf | grep -q ». grep -q s'arrête au premier résultat ; sur un
# texte qui dépasse le tampon d'un tube (64 Kio), printf reçoit alors SIGPIPE,
# et sous « set -o pipefail » le tube entier rend FAUX — une invocation trouvée
# devenait une invocation manquée, et le garde laissait passer.
#
# Contrat : le sourceur a lu stdin dans $entree (le JSON de l'appel d'outil).
# lire_commande pose $commande, decouper la découpe ; les autres fonctions
# lisent le résultat. Rien ici ne refuse : juger est affaire du sourceur.

# Le contenu d'un heredoc est une DONNÉE, pas une commande : un message de commit
# qui parle de « nixos-rebuild switch » n'exécute rien. Sans ce filtre, écrire de
# la documentation sur les commandes gardées deviendrait impossible — le garde
# bloquerait sa propre description.
#
# La ligne qui OUVRE le heredoc est conservée : c'est bien une commande.
filtrer_heredocs() {
  awk '
    BEGIN { dans_heredoc = 0; marqueur = "" }
    {
      if (dans_heredoc) {
        ligne = $0
        sub(/^[[:space:]]+/, "", ligne)
        if (ligne == marqueur) { dans_heredoc = 0 }
        next
      }
      if (match($0, /<<-?[[:space:]]*['"'"'"]?[A-Za-z_][A-Za-z0-9_]*['"'"'"]?/)) {
        m = substr($0, RSTART, RLENGTH)
        sub(/^<<-?[[:space:]]*/, "", m)
        gsub(/['"'"'"]/, "", m)
        marqueur = m
        dans_heredoc = 1
      }
      print
    }
  '
}

# Pose $_outil et $_brute depuis $entree.
#
# jq d'abord ; à défaut, l'évaluateur de Nix, présent sur tout NixOS. Mesuré le
# 2026-10-19 sur Nix 2.28 : 49 ms, et le même texte que jq au caractère près
# (guillemets, antislashs, \n, \t, échappements \uXXXX). Le JSON passe par un
# fichier et non par une variable d'environnement : une variable est bornée à
# 128 Kio, et un heredoc qui écrit un module les dépasse. /dev/stdin ne convient
# pas non plus — builtins.readFile refuse un tube (mesuré : « opening file
# /proc/…/pipe »).
#
# Retourne 2 si l'entrée est illisible, 3 si aucun des deux lecteurs n'existe.
#
# $entree vient du sourceur (voir le contrat en tête) : shellcheck ne peut pas
# le voir, d'où la directive.
# shellcheck disable=SC2154
lire_json() {
  if command -v jq > /dev/null 2>&1; then
    _outil=$(printf '%s' "$entree" | jq -r '.tool_name // ""' 2> /dev/null) || return 2
    _brute=$(printf '%s' "$entree" | jq -r '.tool_input.command // ""' 2> /dev/null) || return 2
    return 0
  fi
  if command -v nix > /dev/null 2>&1; then
    local fichier sortie statut
    fichier=$(mktemp) || return 2
    printf '%s' "$entree" > "$fichier"
    sortie=$(nix --extra-experimental-features nix-command eval --impure --raw --expr "
      let e = builtins.fromJSON (builtins.readFile \"$fichier\");
      in (e.tool_name or \"\") + \"\n\" + (e.tool_input.command or \"\")" 2> /dev/null)
    statut=$?
    rm -f "$fichier"
    [ "$statut" -eq 0 ] || return 2
    _outil=${sortie%%$'\n'*}
    _brute=${sortie#*$'\n'}
    return 0
  fi
  return 3
}

# Pose $commande depuis l'appel de $entree, heredocs retirés.
#
# Retourne 0 si une commande est à juger ; 1 s'il n'y a rien à juger (autre
# outil, commande vide) ; 2 si l'entrée est illisible ; 3 si aucun lecteur JSON
# n'est disponible. Les deux derniers cas ne doivent jamais laisser passer : le
# sourceur n'arrive ici qu'après un pré-filtre qui a vu le nom d'un outil gardé.
#
# Monitor est jugé comme Bash : son champ « command » est une commande shell,
# lancée en arrière-plan — mais lancée.
lire_commande() {
  local _outil="" _brute="" statut
  lire_json
  statut=$?
  [ "$statut" -eq 0 ] || return "$statut"
  case "$_outil" in
    Bash | Monitor) ;;
    *) return 1 ;;
  esac
  [ -n "$_brute" ] || return 1
  commande=$(printf '%s\n' "$_brute" | filtrer_heredocs)
  [ -n "$commande" ] || return 1
}

# ─── Lire n'est pas exécuter ──────────────────────────────────────────────────
# Un motif nu cherche une CHAÎNE ; un garde doit chercher une INVOCATION. Le
# dépôt nixos-config a essayé trois formulations le 2026-09-10, et les deux
# premières ont échoué de façons opposées :
#
#   1. Motif nu. Refusait « grep -n 'nixos-rebuild' fichier » : le garde
#      empêchait de LIRE la configuration.
#   2. Motif ancré en début de commande. Seize invocations passaient alors —
#      chemin absolu, env X=1, command/exec/time/xargs, eval, sh -c, mot-clé,
#      guillemets, antislash, variable.
#   3. Liste blanche de lecteurs. Refusait « shellcheck fichier » : un outil qui
#      prend le fichier en argument n'est pas un lecteur listé.
#
# Ce qui suit pose la question juste : le NOM DE COMMANDE de l'un des segments
# est-il l'outil ? On retire les affectations d'environnement et les enrobages
# neutres, on prend le basename, on déshabille les guillemets. Deux prises
# indirectes restent couvertes à part : les exécuteurs, qui lancent ce qu'on
# leur passe, et l'affectation à une variable suivie d'une indirection.
#
# CE QUE CE GARDE NE PRÉTEND PAS ÊTRE. Il refuse des formes, et une forme se
# contourne — « find -exec », un alias, un script intermédiaire. Il protège d'un
# geste distrait, pas d'une intention.

# Neutralise les séparateurs de commande SITUÉS ENTRE GUILLEMETS : le contenu
# entre guillemets est une donnée. Sans cela, « grep -v 'a\|nixos-up' » se
# découpait sur le « | » de sa propre expression régulière (mesuré le
# 2026-09-10). Seuls les séparateurs sont remplacés : « sh -c "nixos-rebuild
# switch" » doit encore montrer son mot à la règle des exécuteurs.
neutraliser_guillemets() {
  awk '
    {
      sortie = ""; guillemet = ""
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (guillemet == "") {
          if (c == "\047" || c == "\"") { guillemet = c }
          sortie = sortie c
        } else if (c == guillemet) {
          guillemet = ""; sortie = sortie c
        } else if (index(";&|(){}`", c) > 0) {
          sortie = sortie "\001"
        } else {
          sortie = sortie c
        }
      }
      print sortie
    }
  '
}

# Découpe la commande en segments, UNE fois, dans _PREMIERS (le nom de commande
# résolu) et _SEGMENTS (le segment, préfixes neutres retirés). Le garde la
# découpait à chaque outil jugé, soit douze fois : mesuré le 2026-10-19, une
# commande de 12 000 lignes prenait alors plus de deux minutes — bien au-delà
# du délai du hook, où la commande passe sans avoir été jugée.
#
# _NU est la commande sans guillemets ni antislashs : invoque() y cherche le nom
# de l'outil avant tout, et « "nixos-rebuild" switch » ou « \nixos-rebuild »
# doivent l'y montrer.
_PREMIERS=()
_SEGMENTS=()
_NU=""
decouper() {
  local seg mot premier
  _PREMIERS=()
  _SEGMENTS=()
  _NU="${commande//[\"\'\\]/}"
  while IFS= read -r seg; do
    while :; do
      seg="${seg#"${seg%%[![:space:]]*}"}"
      mot="${seg%%[[:space:]]*}"
      [ -n "$mot" ] || break
      case "$mot" in
        [A-Za-z_]*=*) ;;
        env | command | exec | time | nohup | builtin | if | then | else | elif | while | until | do | !) ;;
        *) break ;;
      esac
      case "$seg" in
        *[[:space:]]*) seg="${seg#*[[:space:]]}" ;;
        *) seg="" ;;
      esac
    done
    premier="${seg%%[[:space:]]*}"
    premier="${premier##*/}"
    premier="${premier//\"/}"
    premier="${premier//\'/}"
    premier="${premier//\\/}"
    _PREMIERS+=("$premier")
    _SEGMENTS+=("$seg")
  done <<< "$(printf '%s' "$commande" | neutraliser_guillemets | tr ';&|(){}`' '\n\n\n\n\n\n\n\n')"
}

# Rend « nom_résolu<TAB>segment » pour chaque segment.
segments_resolus() {
  local i
  for i in "${!_SEGMENTS[@]}"; do
    printf '%s\t%s\n' "${_PREMIERS[$i]}" "${_SEGMENTS[$i]}"
  done
}

# Vrai si le segment $2, dont le nom de commande est $1, lance ce qu'on lui passe.
#
# « nix » ne l'est qu'avec run, shell ou develop : « nix eval
# nixpkgs#nixos-rebuild.version » lit un attribut, il ne lance rien.
#
# La liste de nixos-config s'arrêtait à la première clause. Les suivantes
# laissaient toutes passer « nixos-rebuild switch », ici comme là-bas (mesuré le
# 2026-10-19, sur les dix-neuf présentes sur le poste de mesure) — run0 et
# pkexec en tête, qui élèvent sans sudo.
executeur() {
  case "$1" in
    eval | sh | bash | zsh | dash | ksh | xargs | sudo | doas | watch | timeout | script | setsid | nice | ionice | stdbuf | su | ssh | nix-shell | parallel)
      return 0
      ;;
    # Élèvent par polkit ou changent d'identité.
    run0 | pkexec | systemd-run | runuser | setpriv | capsh | sg) return 0 ;;
    # Isolent : la commande tourne quand même, ailleurs.
    chroot | unshare | nsenter | systemd-nspawn | bwrap | firejail | steam-run | busybox) return 0 ;;
    # Ajustent un réglage, puis lancent.
    flock | taskset | chrt | prlimit | setarch | systemd-inhibit | strace | ltrace | fakeroot | faketime) return 0 ;;
    # Lancent dans un autre terminal.
    tmux | screen) return 0 ;;
    nix)
      grep -Eq '(^|[[:space:]])(run|shell|develop)([[:space:]]|$)' <<< "$2"
      ;;
    *) return 1 ;;
  esac
}

# Vrai si « $1 » figure comme mot dans le segment $2 — frontière : tout sauf
# lettre, chiffre, « _ », « . », « - ». Un guillemet ferme le mot, comme dans
# « sh -c "home-manager switch" », et « # » aussi, comme dans
# « nix run nixpkgs#home-manager ».
nomme() {
  grep -Eq "(^|[^A-Za-z0-9_.-])${1}([^A-Za-z0-9_.-]|\$)" <<< "$2"
}

# Vrai si la commande invoque réellement « $1 ». decouper() doit avoir tourné.
invoque() {
  local nom="$1" i
  # Sans le nom nulle part, aucune invocation possible — et la plupart des
  # outils jugés sortent ici, sans parcourir un seul segment.
  [[ "$_NU" == *"$nom"* ]] || return 1
  # Capture dans une variable, puis indirection : « x=nixos-rebuild; $x switch ».
  grep -Eq "[A-Za-z_][A-Za-z0-9_]*=[\"']?${nom}([^A-Za-z0-9_.-]|\$)" <<< "$commande" && return 0
  for i in "${!_SEGMENTS[@]}"; do
    [ "${_PREMIERS[$i]}" = "$nom" ] && return 0
    if executeur "${_PREMIERS[$i]}" "${_SEGMENTS[$i]}" && nomme "$nom" "${_SEGMENTS[$i]}"; then
      return 0
    fi
  done
  return 1
}

# Rend, un par ligne, les segments où « $1 » est invoqué — même règle
# qu'invoque, mais en donnant le segment plutôt qu'un oui. C'est ce qui permet
# de juger les ARGUMENTS d'une invocation (« home-manager switch » refusé,
# « home-manager generations » libre) sans les chercher ailleurs dans la
# commande : « home-manager generations ; echo switch » ne doit pas être refusé.
segments_invoquant() {
  local nom="$1" i
  for i in "${!_SEGMENTS[@]}"; do
    if [ "${_PREMIERS[$i]}" = "$nom" ]; then
      printf '%s\n' "${_SEGMENTS[$i]}"
    elif executeur "${_PREMIERS[$i]}" "${_SEGMENTS[$i]}" && nomme "$nom" "${_SEGMENTS[$i]}"; then
      printf '%s\n' "${_SEGMENTS[$i]}"
    fi
  done
}
