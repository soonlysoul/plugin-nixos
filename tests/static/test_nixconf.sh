#!/usr/bin/env bash
# Les variables posées ici sont lues par les conditions que « attendre » évalue,
# et par les suites qui sourcent lib.sh : shellcheck ne suit ni l'un ni l'autre.
# shellcheck disable=SC2034
# scripts/nixconf — détection, vérification, proposition, adoption.
#
# Sans réseau et sans le vrai Nix : un nix simulé, dans un PATH restreint,
# répond aux évaluations et aux constructions et consigne ses arguments. Un
# sudo piégé prouve qu'aucune sous-commande ne l'appelle, et le PATH ne contient
# ni le nixos-up ni le jq de la machine qui lance les tests.
# shellcheck source=../lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
SUITE=test_nixconf
# Portage au harnais du modèle (plugin-plugin, phase 14) : les cas
# d'origine, mot pour mot, sur les aides de tests/lib.sh.
attendre() { if eval "$2"; then pass "$1"; else fail "$1" "condition fausse : $2"; fi; }
NIXCONF="$PLUGIN_ROOT/scripts/nixconf"
# Une suite ne dépend pas de la configuration Nix de la session qui la lance.
unset NIXOS_CONF NIX_CONFIG

BAC=$(mktemp -d)
FAUX="$BAC/faux"
mkdir -p "$FAUX" "$BAC/home"

# ─── Les doublures ────────────────────────────────────────────────────────────
cat > "$FAUX/nix" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_JOURNAL"
args="$*"
case " $args " in
  *" eval "*)
    if [[ $args == *attrNames* ]]; then printf '%b' "${STUB_HOTES:-alpha}"; exit 0; fi
    if [[ $args == *".options."* ]]; then printf 'type        : boolean\n'; exit 0; fi
    if [[ $args == *".config."* ]]; then printf 'false'; exit 0; fi
    printf 'version     : 1.0\n'
    exit 0
    ;;
  *" build "*)
    if [ "${STUB_PUR_ECHOUE:-0}" = 1 ] && [[ $args != *--impure* ]]; then
      echo "error: access to absolute path '/etc/nixos/hardware-configuration.nix' is forbidden in pure evaluation mode (use '--impure' to override)" >&2
      exit 1
    fi
    for h in ${STUB_CASSES:-}; do
      if [[ $args == *"nixosConfigurations.$h."* ]]; then echo "error: undefined variable 'pkgz'" >&2; exit 1; fi
    done
    h=${args##*nixosConfigurations.}
    h=${h%%.*}
    echo "/nix/store/00000000000000000000000000000000-nixos-system-$h"
    exit 0
    ;;
esac
exit 0
EOF
cat > "$FAUX/nix-build" << 'EOF'
#!/usr/bin/env bash
printf 'nix-build %s\n' "$*" >> "$STUB_JOURNAL"
echo "/nix/store/11111111111111111111111111111111-nixos-system-classique"
EOF
cat > "$FAUX/sudo" << 'EOF'
#!/usr/bin/env bash
printf 'SUDO %s\n' "$*" >> "$STUB_JOURNAL"
exit 99
EOF
chmod +x "$FAUX"/*

OUTILS=$(restricted_path bash git grep sed awk cut head tail sort find readlink dirname basename \
  mktemp rm mkdir cp ls uname cat env tr wc sha256sum chmod)
export PATH="$FAUX:$OUTILS"
export HOME="$BAC/home"
export XDG_CONFIG_HOME="$HOME/.config"
export NIXCONF_ETC="$BAC/etc-nixos"
export NIXCONF_CHOIX="$BAC/choix"
export NIXCONF_NIX_CONF="$BAC/nix.conf"
export NIXCONF_SYSTEME_ACTUEL="$BAC/current-system"
export NIXCONF_VERSION="25.05.20260102.ac62194"
export STUB_JOURNAL="$BAC/journal"
export GIT_CONFIG_GLOBAL="$BAC/gitconfig"
git config --global user.email test@exemple.test
git config --global user.name test
git config --global init.defaultBranch main
: > "$STUB_JOURNAL"

# nixconf <args…> — pose STATUT, SORTIE (stdout) et ERREUR (stderr), depuis $ICI.
ICI="$BAC/home"
nixconf() {
  local o e
  o=$(mktemp)
  e=$(mktemp)
  (cd "$ICI" && bash "$NIXCONF" "$@") > "$o" 2> "$e"
  STATUT=$?
  SORTIE=$(< "$o")
  ERREUR=$(< "$e")
  rm -f "$o" "$e"
}

# Un dépôt git contenant un flake NixOS, à la disposition voulue.
#   faire_flake <répertoire> [conf-nixos] [impur]
faire_flake() {
  local d="$1" c="$1"
  [ "${2:-}" = conf-nixos ] && c="$1/conf-nixos"
  mkdir -p "$c/machines"
  printf '{ outputs = _: { nixosConfigurations = { }; }; }\n' > "$c/flake.nix"
  if [ "${3:-}" = impur ]; then
    printf '{ imports = [ /etc/nixos/hardware-configuration.nix ]; }\n' > "$c/machines/alpha.nix"
  else
    printf '{ imports = [ ]; }\n' > "$c/machines/alpha.nix"
  fi
  git -C "$d" init -q
  git -C "$d" add -A
  git -C "$d" commit -qm init
}

champ() { printf '%s\n' "$SORTIE" | grep -m1 "^$1=" | cut -d= -f2-; }

echo "# localiser — trouver sans deviner"
nixconf localiser
attendre "rien nulle part : genre=aucun, sortie 1" '[ "$STATUT" = 1 ] && [ "$(champ genre)" = aucun ]'

mkdir -p "$NIXCONF_ETC"
printf '{ ... }: { system.stateVersion = "25.05"; }\n' > "$NIXCONF_ETC/configuration.nix"
nixconf localiser
attendre "/etc/nixos classique : genre=classique" '[ "$STATUT" = 0 ] && [ "$(champ genre)" = classique ] && [ "$(champ configuration)" = "$NIXCONF_ETC" ]'

faire_flake "$HOME/Nixos" conf-nixos impur
nixconf localiser
attendre "un seul emplacement usuel : retenu" '[ "$(champ configuration)" = "$HOME/Nixos/conf-nixos" ] && [ "$(champ source)" = "emplacement usuel" ]'
attendre "il passe avant /etc/nixos, qui reste candidat" '[[ "$SORTIE" == *"candidat=$NIXCONF_ETC"* ]]'
attendre "dépôt git reconnu" '[ "$(champ depot)" = "$HOME/Nixos" ]'
attendre "import de /etc/nixos/… : évaluation impure" '[ "$(champ evaluation)" = impure ]'
attendre "description matérielle exigée et absente : signalée" '[[ "$(champ materiel)" == ABSENTE* ]]'

faire_flake "$HOME/nixos-config"
nixconf localiser
attendre "deux emplacements usuels : genre=ambigu, sortie 1" '[ "$STATUT" = 1 ] && [ "$(champ genre)" = ambigu ]'
attendre "les deux sont nommés" '[[ "$SORTIE" == *"candidat=$HOME/Nixos/conf-nixos"* ]] && [[ "$SORTIE" == *"candidat=$HOME/nixos-config"* ]]'
nixconf verifier
attendre "ambigu : verifier refuse de choisir (sortie 1)" '[ "$STATUT" = 1 ] && [[ "$ERREUR" == *"plusieurs configurations"* ]]'

ICI="$HOME/nixos-config/machines"
nixconf localiser
attendre "le répertoire courant tranche, même en sous-répertoire" '[ "$(champ configuration)" = "$HOME/nixos-config" ] && [ "$(champ source)" = "répertoire courant" ]'
attendre "dépôt sans import absolu : évaluation pure" '[ "$(champ evaluation)" = pure ]'
ICI="$HOME"

NIXOS_CONF="$HOME/nixos-config" nixconf localiser
attendre "NIXOS_CONF tranche" '[ "$(champ source)" = NIXOS_CONF ]'
NIXOS_CONF="$BAC/nulle-part" nixconf localiser
attendre "NIXOS_CONF invalide : sortie 1" '[ "$STATUT" = 1 ]'

nixconf choisir "$HOME/Nixos"
attendre "choisir accepte un dépôt à conf-nixos/" '[ "$STATUT" = 0 ] && [ "$(cat "$NIXCONF_CHOIX")" = "$HOME/Nixos/conf-nixos" ]'
nixconf localiser
attendre "le choix retenu tranche l'ambiguïté" '[ "$STATUT" = 0 ] && [ "$(champ configuration)" = "$HOME/Nixos/conf-nixos" ] && [[ "$(champ source)" == choix* ]]'
nixconf choisir "$BAC/nulle-part"
attendre "choisir un répertoire sans configuration : sortie 1" '[ "$STATUT" = 1 ]'

# La commande nixos-up du dépôt nixos-config porte son dépôt en dur.
rm -f "$NIXCONF_CHOIX"
printf '#!/usr/bin/env bash\ndepot="${NIXOS_UP_DEPOT:-%s}"\n' "$HOME/nixos-config" > "$FAUX/nixos-up"
chmod +x "$FAUX/nixos-up"
nixconf localiser
attendre "le dépôt baké dans nixos-up tranche" '[ "$(champ configuration)" = "$HOME/nixos-config" ] && [ "$(champ source)" = nixos-up ]'
ICI="$HOME/Nixos"
nixconf localiser
attendre "un dépôt que nixos-up ne dépose pas : pas d'avertissement" '[ -z "$(champ avertissement)" ]'
printf 'x\n' > "$HOME/Nixos/conf-nixos/nixos-up"
git -C "$HOME/Nixos" add -A
git -C "$HOME/Nixos" commit -qm nixos-up
nixconf localiser
attendre "nixos-up déposerait un autre dépôt que celui-ci : averti" '[[ "$(champ avertissement)" == *"$HOME/nixos-config"* ]]'
ICI="$HOME"
rm -f "$FAUX/nixos-up"

: > "$NIXCONF_NIX_CONF"
nixconf localiser
attendre "flakes non déclarés : flakes=non" '[ "$(champ flakes)" = non ]'
printf 'experimental-features = nix-command flakes\n' > "$NIXCONF_NIX_CONF"
nixconf localiser
attendre "flakes déclarés, sans nix.conf utilisateur : flakes=oui" '[ "$(champ flakes)" = oui ]'

echo "# verifier — prouver sans privilège"
export NIXOS_CONF="$HOME/Nixos"
printf '{ }\n' > "$HOME/Nixos/conf-nixos/machines/neuf.nix"
nixconf verifier
attendre "un fichier non enregistré : sortie 4, nommé, avec le git add" '[ "$STATUT" = 4 ] && [[ "$ERREUR" == *"machines/neuf.nix"* ]] && [[ "$ERREUR" == *"git -C $HOME/Nixos add -- conf-nixos"* ]]'
git -C "$HOME/Nixos" add -A

nixconf verifier
attendre "description matérielle absente : sortie 1, avec la commande à proposer" '[ "$STATUT" = 1 ] && [[ "$ERREUR" == *"nixos-generate-config --show-hardware-config"* ]]'
printf '{ }\n' > "$NIXCONF_ETC/hardware-configuration.nix"

: > "$STUB_JOURNAL"
STUB_HOTES='alpha\nbeta' nixconf verifier
attendre "sans argument : toutes les configurations sont construites" '[ "$STATUT" = 0 ] && [[ "$SORTIE" == *"✓ alpha"* ]] && [[ "$SORTIE" == *"✓ beta"* ]]'
attendre "construites sans lien ni privilège, en impur" 'grep -q "build --no-link --print-out-paths --impure" "$STUB_JOURNAL" && ! grep -q SUDO "$STUB_JOURNAL"'
attendre "le chemin et la suite sont donnés" '[[ "$SORTIE" == *"ecart /nix/store/"* ]] && [[ "$SORTIE" == *"proposer alpha"* ]]'

STUB_HOTES='alpha\nbeta' STUB_CASSES=beta nixconf verifier
attendre "une configuration cassée : sortie 2, et l'autre est quand même construite" '[ "$STATUT" = 2 ] && [[ "$SORTIE" == *"✓ alpha"* ]] && [[ "$SORTIE" == *"✗ beta"* ]] && [[ "$ERREUR" == *"undefined variable"* ]]'

: > "$STUB_JOURNAL"
NIXOS_CONF="$HOME/nixos-config" STUB_PUR_ECHOUE=1 nixconf verifier alpha
attendre "erreur de pureté : nouvel essai en impur, dit, et réussi" '[ "$STATUT" = 0 ] && [[ "$ERREUR" == *"nouvel essai avec --impure"* ]] && grep -q -- "--impure" "$STUB_JOURNAL"'
attendre "la sortie le rappelle pour la commande d'application" '[[ "$SORTIE" == *"Évaluation impure"* ]]'

: > "$STUB_JOURNAL"
NIXOS_CONF="$NIXCONF_ETC" nixconf verifier
attendre "classique : nix-build sur configuration.nix" '[ "$STATUT" = 0 ] && grep -q "nix-build <nixpkgs/nixos> -A system --no-out-link -I nixos-config=$NIXCONF_ETC/configuration.nix" "$STUB_JOURNAL"'

echo "# option et paquet — évalués dans la configuration elle-même"
STUB_HOTES='alpha\nbeta' nixconf option services.openssh.enable
attendre "deux configurations sans hôte : sortie 1, les deux nommées" '[ "$STATUT" = 1 ] && [[ "$ERREUR" == *alpha* ]] && [[ "$ERREUR" == *beta* ]]'
: > "$STUB_JOURNAL"
STUB_HOTES='alpha\nbeta' nixconf option services.openssh.enable beta
attendre "option : nixosConfigurations.<hôte>.options.<chemin>" '[ "$STATUT" = 0 ] && grep -q "conf-nixos#nixosConfigurations.beta.options.services.openssh.enable" "$STUB_JOURNAL"'
attendre "option : la valeur courante suit" '[[ "$SORTIE" == *"valeur      : false"* ]]'
: > "$STUB_JOURNAL"
nixconf paquet claude-code
attendre "paquet : un seul hôte, pris sans le nommer ; pkgs de la configuration" '[ "$STATUT" = 0 ] && grep -q "conf-nixos#nixosConfigurations.alpha --apply" "$STUB_JOURNAL" && grep -q "pkgs = c.pkgs; p = pkgs.claude-code;" "$STUB_JOURNAL"'
: > "$STUB_JOURNAL"
NIXOS_CONF="$NIXCONF_ETC" nixconf paquet hello
attendre "paquet, classique : <nixpkgs/nixos> sur configuration.nix" 'grep -q "import <nixpkgs/nixos> { configuration = /. + \"$NIXCONF_ETC/configuration.nix\"; }) --apply" "$STUB_JOURNAL"'

echo "# proposer — imprimer, jamais lancer"
: > "$STUB_JOURNAL"
: > "$NIXCONF_NIX_CONF"
nixconf proposer
attendre "flake impur, flakes non activés : NIX_CONFIG et --impure" '[ "$STATUT" = 0 ] && [[ "$SORTIE" == *"sudo NIX_CONFIG='"'"'experimental-features = nix-command flakes'"'"' nixos-rebuild switch --impure --flake $HOME/Nixos/conf-nixos#alpha"* ]]'
printf 'experimental-features = nix-command flakes\n' > "$NIXCONF_NIX_CONF"
NIXOS_CONF="$HOME/nixos-config" nixconf proposer
attendre "flake pur, flakes activés : la commande nue" '[[ "$SORTIE" == *"sudo nixos-rebuild switch --flake $HOME/nixos-config#alpha"* ]]'
STUB_HOTES='alpha\nbeta' nixconf proposer
attendre "deux configurations sans hôte : sortie 1" '[ "$STATUT" = 1 ]'
NIXOS_CONF="$NIXCONF_ETC" nixconf proposer
attendre "classique dans /etc/nixos : sudo nixos-rebuild switch" '[[ "$SORTIE" == *"  sudo nixos-rebuild switch"* ]] && [[ "$SORTIE" != *"-I nixos-config"* ]]'
mkdir -p "$BAC/ailleurs"
cp "$NIXCONF_ETC/configuration.nix" "$BAC/ailleurs/"
NIXOS_CONF="$BAC/ailleurs" nixconf proposer
attendre "classique déplacé : -I nixos-config=" '[[ "$SORTIE" == *"-I nixos-config=$BAC/ailleurs/configuration.nix"* ]]'
printf 'x\n' > "$HOME/Nixos/conf-nixos/nixos-up"
git -C "$HOME/Nixos" add -A
printf '#!/usr/bin/env bash\ndepot="${NIXOS_UP_DEPOT:-%s}"\n' "$HOME/ancien" > "$FAUX/nixos-up"
chmod +x "$FAUX/nixos-up"
nixconf proposer alpha
attendre "dépôt nixos-config : nixos-up puis /etc/nixos" '[[ "$SORTIE" == *"nixos-up alpha"* ]] && [[ "$SORTIE" == *"sudo nixos-rebuild switch --impure --flake $NIXCONF_ETC#alpha"* ]]'
attendre "nixos-up baké ailleurs : NIXOS_UP_DEPOT posé, et dit" '[[ "$SORTIE" == *"NIXOS_UP_DEPOT=$HOME/Nixos nixos-up alpha"* ]] && [[ "$SORTIE" == *"⚠"* ]]'
rm -f "$FAUX/nixos-up"
attendre "le retour en arrière est donné" '[[ "$SORTIE" == *"--rollback"* ]]'
attendre "aucune sous-commande n'a appelé sudo" '! grep -q SUDO "$STUB_JOURNAL"'
unset NIXOS_CONF

echo "# adopter — /etc/nixos dans un dépôt à soi, sans y toucher"
cat > "$NIXCONF_ETC/configuration.nix" << 'EOF'
{ ... }:
{
  imports = [ ./hardware-configuration.nix ./bureau.nix ];
  system.stateVersion = "25.05";
}
EOF
printf '{ }\n' > "$NIXCONF_ETC/bureau.nix"
empreinte_avant=$(cd "$NIXCONF_ETC" && find . -type f -exec sha256sum {} + | sort)

nixconf adopter "$HOME/neuf"
attendre "sans hôte : sortie 1, le nom de la machine suggéré" '[ "$STATUT" = 1 ] && [[ "$ERREUR" == *"$(uname -n)"* ]]'
nixconf adopter "$HOME/neuf" 'pas un nom'
attendre "nom invalide : sortie 1" '[ "$STATUT" = 1 ]'
nixconf adopter "$HOME/Nixos" portable
attendre "destination non vide : sortie 1, rien d'écrit" '[ "$STATUT" = 1 ] && [[ "$ERREUR" == *"pas vide"* ]]'

nixconf adopter "$HOME/neuf" portable
attendre "adoption : sortie 0" '[ "$STATUT" = 0 ]'
attendre "configuration.nix et ses modules copiés" '[ -f "$HOME/neuf/configuration.nix" ] && [ -f "$HOME/neuf/bureau.nix" ]'
attendre "la description matérielle reste dans /etc/nixos" '[ ! -e "$HOME/neuf/hardware-configuration.nix" ]'
attendre "son import pointe vers /etc/nixos" 'grep -q "/etc/nixos/hardware-configuration.nix ./bureau.nix" "$HOME/neuf/configuration.nix"'
attendre "stateVersion inchangée" 'grep -q "system.stateVersion = \"25.05\"" "$HOME/neuf/configuration.nix"'
attendre "flake posé : l'hôte, le canal du système, l'architecture" 'grep -q "nixosConfigurations.\"portable\"" "$HOME/neuf/flake.nix" && grep -q "github:NixOS/nixpkgs/nixos-25.05" "$HOME/neuf/flake.nix" && grep -q "\"$(uname -m)-linux\"" "$HOME/neuf/flake.nix"'
attendre "aucun motif @…@ laissé dans le flake" '! grep -q "@[A-Z]*@" "$HOME/neuf/flake.nix"'
attendre "tout est enregistré dans git, rien n'est commité" '[ -z "$(git -C "$HOME/neuf" ls-files --others --exclude-standard)" ] && ! git -C "$HOME/neuf" rev-parse -q --verify HEAD > /dev/null'
attendre "retenue comme configuration de ce poste" '[ "$(cat "$NIXCONF_CHOIX")" = "$HOME/neuf" ]'
attendre "/etc/nixos n'a pas changé d'un octet" '[ "$(cd "$NIXCONF_ETC" && find . -type f -exec sha256sum {} + | sort)" = "$empreinte_avant" ]'
ICI="$HOME/neuf"
nixconf localiser
attendre "la configuration adoptée est trouvée, flake, impure" '[ "$(champ genre)" = flake ] && [ "$(champ evaluation)" = impure ]'
ICI="$HOME"

echo "# ecart, lints, usage"
nixconf ecart /nix/store/00000000000000000000000000000000-absent
attendre "ecart sur un chemin disparu : sortie 1, et quoi faire" '[ "$STATUT" = 1 ] && [[ "$ERREUR" == *verifier* ]]'
NIXOS_CONF="$HOME/nixos-config" nixconf lints
attendre "lints sans fichier modifié : rien à relire, sortie 0" '[ "$STATUT" = 0 ] && [[ "$SORTIE" == *"Aucun fichier"* ]]'
nixconf
attendre "sans argument : l'usage, sortie 1" '[ "$STATUT" = 1 ] && [[ "$ERREUR" == *"nixconf localiser"* ]]'
nixconf inconnue
attendre "sous-commande inconnue : sortie 1" '[ "$STATUT" = 1 ]'

rm -rf "$BAC" "$OUTILS"
finish
