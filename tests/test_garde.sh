#!/usr/bin/env bash
# Les variables posées ici sont lues par les conditions que « attendre » évalue,
# et par les suites qui sourcent lib.sh : shellcheck ne suit ni l'un ni l'autre.
# shellcheck disable=SC2034
# Le garde NixOS — hooks/garde-nixos.sh.
#
# Il est servi à TOUTE session de la machine. Un garde a deux façons d'échouer,
# et posé globalement la seconde change de nature :
#   il laisse passer ce qu'il devait refuser ;
#   il refuse ce qui ne le regardait pas — et change alors le comportement de
#   sessions qui n'ont rien à voir avec NixOS.
# La seconde famille de cas est donc la moitié de ce fichier : « inerte hors
# NixOS » n'est pas une intention, c'est une propriété qu'on mesure.
#
# Les cas repris du dépôt nixos-config (tests/gardes-nixos.bats et les seize
# chemins de traverse de tests/gardes.bats) y gardent leur formulation.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SUITE=test_garde

echo "# activer le système reste un geste humain"
refuse "nixos-rebuild switch"
refuse "nixos-rebuild boot"
refuse "nixos-rebuild test --flake .#pc"
refuse "nixos-rebuild dry-activate"
refuse "nixos-rebuild switch --flake /home/u/nixos#pc --impure"
refuse "nixos-rebuild-ng switch"
refuse "nixos-rebuild"
refuse "nixos-rebuild --flake .#pc"
refuse "/run/current-system/bin/switch-to-configuration switch"
refuse "nixos-install --root /mnt"
refuse "nixos-generate-config"
refuse "sudo nixos-generate-config --force"

echo "# les seize chemins de traverse"
refuse "/run/current-system/sw/bin/nixos-rebuild switch"
refuse "/run/wrappers/bin/sudo nixos-rebuild switch"
refuse "env NIX_PATH=/etc/nixos nixos-rebuild switch"
refuse "NIXOS_CONFIG=/tmp/x.nix nixos-rebuild switch"
refuse "command nixos-rebuild switch"
refuse "exec nixos-rebuild switch"
refuse "time nixos-rebuild switch"
refuse "echo switch | xargs nixos-rebuild"
refuse 'eval "nixos-rebuild switch"'
refuse 'sh -c "nixos-rebuild switch"'
refuse "bash -c 'nixos-rebuild switch'"
refuse "if true; then nixos-rebuild switch; fi"
refuse "for i in 1; do nixos-rebuild switch; done"
refuse "{ nixos-rebuild switch; }"
refuse "x=nixos-rebuild; \$x switch"
refuse '"nixos-rebuild" switch'
refuse "\\nixos-rebuild switch"

echo "# les enveloppes qui élèvent, isolent ou lancent ailleurs"
# Mesuré le 2026-10-19 : chacune laissait passer « nixos-rebuild switch », ici
# comme dans le garde de nixos-config. run0 et pkexec élèvent par polkit, sans
# sudo ; tmux et screen lancent la commande dans un autre terminal.
refuse "run0 nixos-rebuild switch"
refuse "pkexec nixos-rebuild switch"
refuse "systemd-run --user nixos-rebuild switch"
refuse "systemd-run -t -p User=root nixos-rebuild switch"
refuse "systemd-inhibit nixos-rebuild switch"
refuse "systemd-nspawn -D /srv/x nixos-rebuild switch"
refuse "flock /tmp/verrou nixos-rebuild switch"
refuse "chroot / nixos-rebuild switch"
refuse "setpriv --reuid=0 nixos-rebuild switch"
refuse "runuser -u root -- nixos-rebuild switch"
refuse "unshare -r nixos-rebuild switch"
refuse "nsenter -t 1 -m nixos-rebuild switch"
refuse "taskset -c 0 nixos-rebuild switch"
refuse "chrt -f 10 nixos-rebuild switch"
refuse "prlimit --nofile=1024 nixos-rebuild switch"
refuse "setarch x86_64 nixos-rebuild switch"
refuse "sg wheel -c 'nixos-rebuild switch'"
refuse "capsh -- -c 'nixos-rebuild switch'"
refuse "strace -f nixos-rebuild switch"
refuse "ltrace nixos-rebuild switch"
refuse "firejail nixos-rebuild switch"
refuse "bwrap --bind / / nixos-rebuild switch"
refuse "fakeroot nixos-rebuild switch"
refuse "faketime yesterday nixos-rebuild switch"
refuse "tmux new-session -d 'nixos-rebuild switch'"
refuse "tmux send-keys 'nixos-rebuild switch' Enter"
refuse "screen -dm nixos-rebuild switch"
refuse "busybox sh -c 'nixos-rebuild switch'"
refuse "steam-run nixos-rebuild switch"
refuse "run0 home-manager switch"
refuse "pkexec nix-collect-garbage -d"
refuse "systemd-run --user nix profile install nixpkgs#helix"
passe "systemd-run --user nixos-rebuild build"
passe "run0 systemctl restart nginx"
passe "flock /tmp/verrou make"
passe "strace -f -o trace.log nix-store -q --references /run/current-system"
passe "tmux new-session -d 'flutter run'"

echo "# construire sans activer passe : sur un poste neuf, c'est la seule preuve"
passe "nixos-rebuild build"
passe "nixos-rebuild build --flake .#pc"
passe "nixos-rebuild dry-build --flake .#pc"
passe "nixos-rebuild build-vm --flake .#pc"
passe "nixos-rebuild list-generations"
passe "nixos-rebuild --help"
passe "nixos-generate-config --show-hardware-config"
passe "nix build --no-link .#nixosConfigurations.pc.config.system.build.toplevel"
passe "bash /home/u/.claude/plugins/cache/soon/nixos/0.1.0/scripts/nixconf verifier pc"
passe "bash /home/u/.claude/plugins/cache/soon/nixos/0.1.0/scripts/nixconf proposer pc"

echo "# nixos-up — l'outil du dépôt nixos-config"
refuse "nixos-up pc"
refuse "nixos-up --appliquer pc"
refuse "nixos-up --forcer pc"
refuse "nixos-up --rapatrier pc"
refuse "/run/current-system/sw/bin/nixos-up pc"
refuse "nixos-up --verifier pc ; nixos-up pc"
refuse "nixos-up --verifier pc && nixos-up --appliquer pc"
passe "nixos-up --verifier pc"
passe "nixos-up --help"
passe "nixos-up -v pc"

echo "# nh — l'enveloppe"
refuse "nh os switch ."
refuse "nh os boot -H pc"
refuse "nh os test"
refuse "nh home switch"
refuse "nh clean all --keep 3"
refuse "nix run nixpkgs#nh -- os switch"
passe "nh os build ."
passe "nh search firefox"
passe "nh search clean"

echo "# home-manager"
refuse "home-manager switch"
refuse "home-manager switch --flake .#soon"
refuse "home-manager --flake . switch"
refuse 'sh -c "home-manager switch"'
refuse "sudo -u soon home-manager switch"
refuse "nix run nixpkgs#home-manager -- switch"
refuse "nix shell nixpkgs#home-manager -c home-manager switch"
passe "home-manager generations"
passe "home-manager build --flake .#soon"
passe "home-manager packages"
passe "home-manager generations ; echo switch"
passe "nix eval --raw nixpkgs#home-manager.version"

echo "# installer hors de la configuration"
refuse "nix-env -iA nixpkgs.helix"
refuse "nix-env -i helix"
refuse "nix-env --install helix"
refuse "nix-env -u"
refuse "nix-env -e helix"
refuse "nix-env --rollback"
refuse "/run/current-system/sw/bin/nix-env -iA nixpkgs.helix"
refuse "env FOO=1 nix-env -iA nixpkgs.helix"
refuse "echo nixpkgs.helix | xargs nix-env -iA"
refuse "nix profile install nixpkgs#helix"
refuse "nix profile add nixpkgs#helix"
refuse "nix profile remove helix"
refuse "nix --extra-experimental-features 'nix-command flakes' profile install nixpkgs#helix"
passe "nix-env -q"
passe "nix-env -qaP hello"
passe "nix-env -qa --description helix"
passe "nix-env --list-generations"
passe "nix-env -I nixpkgs=/x -qa hello"
passe "nix profile list"
passe "nix profile history"
passe "nix-channel --list"
passe "nix search nixpkgs helix"
passe "nix shell nixpkgs#statix -c statix check conf-nixos"

echo "# détruire des générations"
refuse "nix-collect-garbage"
refuse "nix-collect-garbage -d"
refuse "nix-collect-garbage --delete-older-than 7d"
refuse "nix-collect-garbage --dry-run"
refuse "sudo nix-collect-garbage -d"
refuse "nix store gc"
refuse "nix store gc --dry-run"
refuse "nix store delete /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-x"
refuse "nix-store --gc"
refuse "nix-store --delete /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-x"
refuse "nix-env --delete-generations old"
refuse "nix profile wipe-history"
refuse 'sh -c "nix store gc"'
refuse "bash -c 'nix-store --gc'"
refuse 'sh -c "nix-collect-garbage -d"'
# Le pré-filtre du dépôt nixos-config cherchait « nix store » d'un bloc : une
# option glissée entre les deux mots le contournait (mesuré le 2026-10-19).
refuse "nix --option keep-outputs true store gc"
refuse "nix --extra-experimental-features nix-command store gc"

echo "# lire n'est pas exécuter"
passe "grep -n 'nixos-rebuild' conf-nixos/nixos-up"
passe "rg home-manager conf-nixos/"
passe "grep -rn nix-collect-garbage docs/"
passe "rg 'nix store gc' docs/MANUEL.md"
passe "sed -n '/nixos-up --appliquer/p' docs/MANUEL.md"
passe "grep -n 'nixos\\b' tests/portabilite.bats | grep -v 'conf-nixos\\|nixos-up\\|/etc/nixos'"
passe "rg 'nixos-rebuild|nixos-up|home-manager' docs/"
passe "shellcheck -S warning conf-nixos/nixos-up"
passe "nixfmt --check conf-nixos/nixos-up"
passe "git diff --cached -- conf-nixos/nixos-up"
passe "git commit -F - <<'EOF'
Documenter nixos-rebuild switch et nix-collect-garbage
EOF"
passe "nix store ls --store daemon /run/current-system"
passe "nix store diff-closures /run/current-system ./result"
passe "nix-store -q --references /run/current-system"
passe "nix-store --gc --print-roots"
passe "nix-store --gc --print-dead"
refuse "nix-store --gc --print-roots ; nix-store --gc"
passe "nvd diff /run/current-system ./result"
passe "nix eval --raw nixpkgs#hello.version"
passe "nix eval --raw nixpkgs#nixos-rebuild.version"

echo "# inerte hors NixOS"
passe "flutter test"
passe "dart format --set-exit-if-changed ."
passe "git status"
passe "git push origin feature/x"
passe "gh pr create --fill"
passe "npm test"
passe "sudo systemctl restart nginx"
passe "rm -rf /tmp/build"
passe "git push --force origin feature/x"
passe "pip install requests"
passe "echo enhance the nhost config"

echo "# Monitor lance une commande : il est jugé comme Bash"
refuse "nixos-rebuild switch" Monitor
passe "tail -f /var/log/app.log" Monitor

echo "# un autre outil n'est jamais jugé"
statut=$(jq -nc '{tool_name: "Write", tool_input: {file_path: "/tmp/x", content: "nixos-rebuild switch"}}' \
  | bash "$GARDE" 2> /dev/null; echo $?)
attendre "Write qui parle de nixos-rebuild : passe" '[ "$statut" = 0 ]'

echo "# le garde ne se désactive jamais en silence"
statut=$(printf '' | bash "$GARDE" 2> /dev/null; echo $?)
attendre "entrée vide : passe" '[ "$statut" = 0 ]'
statut=$(printf 'pas du json' | bash "$GARDE" 2> /dev/null; echo $?)
attendre "entrée illisible sans outil gardé : passe" '[ "$statut" = 0 ]'
statut=$(printf '{"tool_name":"Bash","tool_input":{"command":"nixos-rebuild switch"' | bash "$GARDE" 2> /dev/null; echo $?)
attendre "entrée illisible qui nomme un outil gardé : refusée" '[ "$statut" = 2 ]'

bash_=$(command -v bash)
vide=$(mktemp -d)
sortie=$(env PATH="$vide" "$bash_" "$GARDE" <<< '{"tool_name":"Bash","tool_input":{"command":"nixos-rebuild switch"}}' 2>&1)
statut=$?
attendre "sans AUCUN binaire, un outil gardé est refusé, pas ignoré" '[ "$statut" = 2 ] && [[ "$sortie" == *"ni jq ni nix"* ]]'
statut=$(env PATH="$vide" "$bash_" "$GARDE" <<< '{"tool_name":"Bash","tool_input":{"command":"flutter test"}}' > /dev/null 2>&1; echo $?)
attendre "sans AUCUN binaire, une commande sans outil gardé passe" '[ "$statut" = 0 ]'
rmdir "$vide"

# Le cas d'un NixOS fraîchement installé : nix est là, jq non.
if command -v nix > /dev/null 2>&1; then
  sans_jq=$(chemin_restreint nix awk grep tr mktemp rm)
  for cas in "nixos-rebuild switch:2" "nixos-rebuild build:0" 'sh -c "home-manager switch":2' "nix-env -iA nixpkgs.jq:2" "nix-env -q:0"; do
    cmd=${cas%:*}
    attendu=${cas##*:}
    statut=$(entree_outil "$cmd" | env PATH="$sans_jq" "$bash_" "$GARDE" > /dev/null 2>&1; echo $?)
    attendre "sans jq, lu par nix : « $cmd » → $attendu" '[ "$statut" = "$attendu" ]'
  done
  rm -rf "$sans_jq"
else
  saute "sans jq, lu par nix" "nix absent"
fi

copie=$(mktemp -d)
cp "$GARDE" "$copie/garde-nixos.sh"
sortie=$(entree_outil "nixos-rebuild switch" | bash "$copie/garde-nixos.sh" 2>&1)
statut=$?
attendre "la bibliothèque absente fait refuser, pas passer" '[ "$statut" = 2 ] && [[ "$sortie" == *"lib-commande.sh"* ]]'
rm -rf "$copie"

echo "# une commande longue est jugée, et vite"
# Mesuré le 2026-10-19 : au-delà de 64 Kio, « printf | grep -q » sous pipefail
# rendait faux, et le garde du dépôt nixos-config laissait passer ce cas trois
# fois sur trois ; le découpage refait par outil le faisait durer plus de deux
# minutes.
longue=$(mktemp)
{
  printf 'x=%s; $x switch\n' "nixos-""rebuild"
  for i in $(seq 1 12000); do printf 'echo ligne%05d\n' "$i"; done
} > "$longue"
debut=$SECONDS
statut=$(jq -Rsc '{tool_name: "Bash", tool_input: {command: .}}' "$longue" | bash "$GARDE" > /dev/null 2>&1; echo $?)
duree=$((SECONDS - debut))
attendre "192 Kio, indirection en tête : refusée" '[ "$statut" = 2 ]'
attendre "192 Kio jugés en moins de 10 s (mesuré : ${duree} s)" '[ "$duree" -lt 10 ]'
rm -f "$longue"

terminer
