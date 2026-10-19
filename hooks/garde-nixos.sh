#!/usr/bin/env bash
# Le garde NixOS — refuse, dans TOUTE session, les gestes qui changent la machine
# hors de sa configuration déclarée.
#
# CE QU'IL REFUSE — quatre familles, et seulement elles :
#
#   activer le système      nixos-rebuild switch|boot|test|dry-activate,
#                           switch-to-configuration, nh os switch|boot|test|rollback,
#                           nixos-install, nixos-generate-config qui écrit,
#                           nixos-up sans --verifier (l'outil du dépôt nixos-config)
#   activer l'utilisateur   home-manager switch|init|uninstall, nh home switch
#   installer impérativement  nix-env -i/-u/-e…, nix profile install|add|remove|upgrade
#                           — un paquet posé ainsi survit à tous les rebuilds sans
#                           figurer nulle part dans la configuration
#   détruire des générations  nix-collect-garbage, nix store gc|delete,
#                           nix-store --gc|--delete, nh clean,
#                           nix-env --delete-generations, nix profile wipe-history,
#                           home-manager expire-generations|remove-generations
#
# nixos-rebuild, nh et home-manager sont jugés sur LISTE BLANCHE : une
# sous-commande inconnue ou masquée (« sw\itch ») est refusée.
#
# CE QU'IL LAISSE PASSER, ET C'EST DÉLIBÉRÉ. Construire sans activer —
# « nixos-rebuild build », « nh os build », « nix build » — n'élève rien et ne
# change pas la machine. Sur un poste neuf il n'existe pas d'autre moyen de
# prouver qu'une configuration tient : le dépôt nixos-config refusait tout
# nixos-rebuild parce que nixos-up --verifier y tenait ce rôle, et un PC neuf
# n'a pas nixos-up.
#
# CE QU'IL NE REFUSE PAS : rien de générique. Ni sudo seul, ni rm -rf, ni
# git push --force. Posé par un plugin, il tourne dans toutes les sessions de la
# machine, et un refus générique changerait le comportement de projets qui
# n'ont rien à voir avec NixOS. Il doit rester inerte hors des commandes Nix.
#
# Un plugin ne distribue pas de permissions : le hook est la seule forme sous
# laquelle ce refus voyage.
#
# PreToolUse / matcher Bash|Monitor. Sortie : 0 laisse passer, 2 refuse et
# renvoie stderr à Claude.
#
# Testable sans Claude :
#   echo '{"tool_name":"Bash","tool_input":{"command":"nixos-rebuild switch"}}' | bash garde-nixos.sh
set -uo pipefail

# stdin en pur bash : ni cat, ni fork.
IFS= read -r -d '' entree || true

# Pré-filtre. Ce garde tourne sur CHAQUE appel Bash de CHAQUE session : la
# quasi-totalité ne nomme aucun outil gardé, et celle-là sort ici, sans fork.
# Écrit en pur bash (« [[ =~ ]] ») et non avec grep : un pré-filtre qui appelle
# un binaire absent échoue, et « échoue donc sort en 0 » est exactement un garde
# qui s'éteint sans le dire.
#
# Il doit être un SUR-ENSEMBLE de ce que les règles jugent. « nix » est donc
# cherché seul, et non « nix store » : le pré-filtre du dépôt nixos-config
# laissait passer « nix --option a b store gc », où les deux mots ne se touchent
# pas (mesuré le 2026-10-19). « nh » exige une frontière après lui, sans quoi
# « enhance » ou « nhost » réveilleraient le garde pour rien.
_gardes='nixos-rebuild|nixos-up|nixos-install|nixos-generate-config|switch-to-configuration|home-manager|nix-collect-garbage|nix-store|nix-env|nix([^A-Za-z0-9_.-]|$)|nh([^A-Za-z0-9_.-]|$)'
[[ "$entree" =~ $_gardes ]] || exit 0

# Cherche la bibliothèque à côté de ce fichier, que le plugin soit lancé depuis
# son cache ou depuis une copie du dépôt.
case "${BASH_SOURCE[0]}" in
  */*) ici="${BASH_SOURCE[0]%/*}" ;;
  *) ici="." ;;
esac
if [ ! -r "$ici/lib-commande.sh" ]; then
  printf 'BLOQUÉ par garde-nixos.sh : lib-commande.sh introuvable à côté du garde.\n' >&2
  exit 2
fi
# shellcheck source=lib-commande.sh
. "$ici/lib-commande.sh"

# Un garde qui se désactive en silence est le pire des deux mondes. Arrivé ici,
# l'entrée nomme un outil gardé : si on ne sait pas la lire, on refuse plutôt
# que de laisser passer sans le dire.
lire_commande
case $? in
  0) ;;
  1) exit 0 ;;
  3)
    printf 'BLOQUÉ par garde-nixos.sh : ni jq ni nix ne sont disponibles, la commande ne peut pas être jugée.\n' >&2
    printf "Elle nomme un outil NixOS gardé ; la proposer à l'utilisateur.\n" >&2
    exit 2
    ;;
  *)
    printf "BLOQUÉ par garde-nixos.sh : l'appel d'outil est illisible, la commande ne peut pas être jugée.\n" >&2
    exit 2
    ;;
esac
decouper

verifier_cmd="bash ${ici%/hooks}/scripts/nixconf verifier"

# $commande est posée par lire_commande (lib-commande.sh) : shellcheck ne suit
# pas un fichier sourcé dynamiquement, d'où la directive.
# shellcheck disable=SC2154
refuser() {
  printf 'BLOQUÉ par garde-nixos.sh (plugin-nixos) : %s\n\n' "$1" >&2
  printf 'Commande : %s\n\n' "$commande" >&2
  printf 'Activer une configuration, installer un paquet hors de la configuration ou\n' >&2
  printf 'détruire des générations est un geste humain. Proposer la commande à\n' >&2
  printf "l'utilisateur, qui la lance lui-même dans son terminal ; ne pas la reformuler\n" >&2
  printf 'pour contourner ce garde.\n' >&2
  exit 2
}

# Vrai si l'un des mots de l'alternative $2 figure dans le segment $1.
mot_parmi() {
  grep -Eq -- "(^|[^A-Za-z0-9_.-])($2)([^A-Za-z0-9_.-]|\$)" <<< "$1"
}

# ─── Activer le système ───────────────────────────────────────────────────────
# Refus par défaut : une sous-commande inconnue, ou illisible (« x=nixos-rebuild;
# $x switch »), est refusée. Ne passe que ce qui construit sans activer. Un mot
# d'activation présent n'importe où dans le segment l'emporte : refuser au doute
# coûte une confirmation, laisser passer au doute coûte une génération.
for _outil in nixos-rebuild nixos-rebuild-ng; do
  invoque "$_outil" || continue
  _vu=0
  while IFS= read -r _seg; do
    _vu=1
    if mot_parmi "$_seg" 'switch|boot|test|dry-activate'; then
      refuser "$_outil active une génération.
       Pour PROUVER qu'une configuration tient, sans privilège et sans rien
       changer au système :
         $verifier_cmd [hôte]"
    fi
    mot_parmi "$_seg" 'build|dry-build|dry-run|build-vm|build-vm-with-bootloader|build-image|list-generations|repl|--help|-h' \
      || refuser "$_outil sans sous-commande de construction reconnue.
       Ne passent que build, dry-build, build-vm, build-image, list-generations,
       repl et --help."
  done < <(segments_invoquant "$_outil")
  [ "$_vu" -eq 1 ] || refuser "$_outil invoqué de façon indirecte : la sous-commande ne peut pas être jugée."
done

if invoque 'switch-to-configuration'; then
  refuser "switch-to-configuration active une génération."
fi

if invoque 'nixos-install'; then
  refuser "nixos-install installe un système sur un disque."
fi

# --show-hardware-config imprime sans rien écrire ; le reste écrit dans
# /etc/nixos — et --force y écrase configuration.nix.
if invoque 'nixos-generate-config'; then
  _vu=0
  while IFS= read -r _seg; do
    _vu=1
    mot_parmi "$_seg" '--show-hardware-config|--help|-h' \
      || refuser "nixos-generate-config écrit une configuration (dans /etc/nixos, ou
       dans --dir) — et --force y écrase configuration.nix.
       Pour lire la description matérielle sans rien écrire :
         nixos-generate-config --show-hardware-config"
  done < <(segments_invoquant 'nixos-generate-config')
  [ "$_vu" -eq 1 ] || refuser "nixos-generate-config invoqué de façon indirecte."
fi

# nixos-up — l'outil du dépôt nixos-config. Elle n'écrit pas « sudo » sur sa
# ligne de commande : elle l'appelle en interne pour copier dans /etc/nixos,
# puis pour activer. --verifier et --help restent libres, et l'exemption se juge
# SEGMENT PAR SEGMENT : sans cela, « nixos-up --verifier pc ; nixos-up pc »
# serait exempté en entier par sa première moitié.
if invoque 'nixos-up'; then
  _sur=0
  _vu=0
  while IFS="$(printf '\t')" read -r _premier _seg; do
    nomme 'nixos-up' "$_seg" || continue
    _vu=1
    grep -Eq -- '(--verifier|--help|[[:space:]]-[a-z]*[vh]([[:space:]]|$))' <<< "$_seg" && continue
    _sur=1
  done < <(segments_resolus)
  if [ "$_sur" -eq 1 ] || [ "$_vu" -eq 0 ]; then
    refuser "nixos-up dépose dans /etc/nixos et appelle sudo pour cela.
       Pour vérifier sans rien déposer : nixos-up --verifier <fiche>"
  fi
fi

# nh — l'enveloppe de nixos-rebuild et de home-manager. Liste blanche, comme
# nixos-rebuild : la liste noire d'avant laissait passer « nh os sw\itch »
# (mesuré le 2026-10-19). « nh search » ne fait que chercher : ses arguments
# sont des mots quelconques, jamais jugés.
if invoque 'nh'; then
  _vu=0
  while IFS= read -r _seg; do
    _vu=1
    mot_parmi "$_seg" 'search' && continue
    if grep -Eq '(^|[^A-Za-z0-9_.-])(os|home|darwin)[[:space:]]+(switch|boot|test|rollback)([^A-Za-z0-9_.-]|$)' <<< "$_seg"; then
      refuser "nh active une génération.
       Pour construire sans activer : nh os build"
    fi
    mot_parmi "$_seg" 'clean' && refuser "nh clean détruit des générations."
    grep -Eq '(^|[^A-Za-z0-9_.-])(os|home|darwin)[[:space:]]+(build|build-vm|repl|info)([^A-Za-z0-9_.-]|$)' <<< "$_seg" \
      || mot_parmi "$_seg" '--help|-h|--version|-V|completions' \
      || refuser "nh sans sous-commande de construction reconnue.
       Ne passent que os, home ou darwin suivis de build, build-vm, repl ou info ;
       search ; et --help."
  done < <(segments_invoquant 'nh')
  [ "$_vu" -eq 1 ] || refuser "nh invoqué de façon indirecte : la sous-commande ne peut pas être jugée."
fi

# ─── Activer ou détruire l'environnement utilisateur ──────────────────────────
# Liste blanche, comme nixos-rebuild. La liste noire d'avant ne refusait que
# switch : expire-generations, remove-generations et uninstall, qui détruisent,
# passaient, et « sw\itch » aussi (mesuré le 2026-10-19). Ne passe que ce qui
# lit ou construit sans activer.
if invoque 'home-manager'; then
  _vu=0
  while IFS= read -r _seg; do
    _vu=1
    if mot_parmi "$_seg" 'switch'; then
      refuser "home-manager switch active une génération.
       Pour PROUVER qu'une configuration tient : home-manager build"
    fi
    if mot_parmi "$_seg" 'expire-generations|remove-generations|uninstall'; then
      refuser "home-manager détruit des générations, ou se désinstalle.
       Le nettoyage se déclare dans la configuration (nix.gc.automatic)."
    fi
    mot_parmi "$_seg" 'build|instantiate|generations|packages|news|option|help|--help|-h|--version' \
      || refuser "home-manager sans sous-commande de lecture reconnue.
       Ne passent que build, instantiate, generations, packages, news, option
       et --help."
  done < <(segments_invoquant 'home-manager')
  [ "$_vu" -eq 1 ] || refuser "home-manager invoqué de façon indirecte : la sous-commande ne peut pas être jugée."
fi

# ─── Installer impérativement, détruire des générations ───────────────────────
# Refusé sous toutes ses formes, y compris --dry-run : un refus qui dépendrait
# du drapeau se contourne par l'ordre des arguments.
if invoque 'nix-collect-garbage'; then
  refuser "nix-collect-garbage détruit des générations. Le ramasse-miettes se
       déclare dans la configuration (nix.gc.automatic)."
fi

# --print-roots, --print-live et --print-dead font de --gc une requête : elle
# liste, et ne collecte rien. Le garde du dépôt nixos-config refusait
# « nix-store --gc --print-roots » (mesuré le 2026-10-19) — la seule manière de
# voir ce qui enracine un chemin.
if invoque 'nix-store'; then
  while IFS= read -r _seg; do
    mot_parmi "$_seg" '--print-roots|--print-live|--print-dead' && continue
    if grep -Eq -- '(^|[[:space:]])--(gc|delete)([^A-Za-z0-9_.-]|$)' <<< "$_seg"; then
      refuser "nix-store --gc / --delete détruit des chemins du store."
    fi
  done < <(segments_invoquant 'nix-store')
fi

# nix-env : une opération par appel, nommée par un drapeau long ou par une lettre
# d'un groupe court. Les lettres i, u, e, G, S sont les opérations qui écrivent
# (install, upgrade, uninstall, switch-generation, switch-profile) ; celles de
# --query (-a, -s, -P, -c) n'en font pas partie, et -I est une option distincte.
if invoque 'nix-env'; then
  _vu=0
  while IFS= read -r _seg; do
    _vu=1
    if mot_parmi "$_seg" '--install|--upgrade|--uninstall|--set|--set-flag|--switch-generation|--switch-profile|--rollback|--delete-generations' \
      || grep -Eq -- '(^|[[:space:]])-[A-Za-z]*[iueGS][A-Za-z]*([[:space:]]|$)' <<< "$_seg"; then
      refuser "nix-env modifie un profil hors de la configuration.
       Un paquet se déclare dans la configuration. Pour l'essayer sans
       l'installer : nix shell nixpkgs#<paquet> -c <commande>"
    fi
  done < <(segments_invoquant 'nix-env')
  [ "$_vu" -eq 1 ] || refuser "nix-env invoqué de façon indirecte : l'opération ne peut pas être jugée."
fi

if invoque 'nix'; then
  while IFS= read -r _seg; do
    if grep -Eq "(^|[^A-Za-z0-9_.-])store[[:space:]]+[\"']?(gc|delete)([^A-Za-z0-9_.-]|\$)" <<< "$_seg"; then
      refuser "nix store gc / delete détruit des chemins du store."
    fi
    if grep -Eq "(^|[^A-Za-z0-9_.-])profile[[:space:]]+[\"']?(install|add|remove|upgrade|rollback|wipe-history)([^A-Za-z0-9_.-]|\$)" <<< "$_seg"; then
      refuser "nix profile modifie un profil hors de la configuration.
       Un paquet se déclare dans la configuration. Pour l'essayer sans
       l'installer : nix shell nixpkgs#<paquet> -c <commande>"
    fi
  done < <(segments_invoquant 'nix')
fi

exit 0
