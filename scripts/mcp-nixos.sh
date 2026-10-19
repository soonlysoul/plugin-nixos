#!/usr/bin/env bash
# Lance le serveur MCP mcp-nixos : celui du système s'il est déclaré, sinon une
# copie construite une fois pour toutes depuis une révision épinglée de
# nixpkgs-unstable.
#
# Pourquoi épinglée : mcp-nixos est absent de nixpkgs stable — mesuré le
# 2026-10-19, « nix eval nixpkgs#mcp-nixos.version » échoue sur la 25.05. Une
# branche mouvante ferait retélécharger nixpkgs à chaque déplacement ; une
# révision fixe ne se télécharge qu'une fois. Celle-ci porte mcp-nixos 3.0.1.
#
# Pourquoi construite à part, et pas « nix run » à chaque démarrage : mesuré le
# 2026-10-19, le premier « nix run » télécharge toute une fermeture Python et
# n'avait pas fini en 4 min 40 s. Claude Code abandonne un serveur bien avant,
# et le tue — téléchargement compris — à chaque session. La construction part
# donc DÉTACHÉE, une fois ; le lanceur l'attend un peu, et sinon s'efface en le
# disant : le serveur sera là à la session suivante.
#
# Pourquoi un --out-link : c'est une racine du ramasse-miettes. Une chaîne de
# configuration qui nomme un chemin du store n'en est pas une — c'est ainsi que
# le dépôt nixos-config a perdu un serveur MCP, sans que rien ne le signale.
#
# Déclarer mcp-nixos dans la configuration rend tout ceci inutile.
set -u
readonly REVISION="7fd4004d0511991fff3a0524856a9be09e28c5f0"
readonly ATTENTE="${NIXOS_PLUGIN_ATTENTE_MCP:-20}"

etat="${XDG_STATE_HOME:-$HOME/.local/state}/plugin-nixos"
lien="$etat/mcp-nixos-${REVISION:0:12}"

if command -v mcp-nixos > /dev/null 2>&1; then
  exec mcp-nixos "$@"
fi
if [ -x "$lien/bin/mcp-nixos" ]; then
  rm -f "$lien.construction"
  exec "$lien/bin/mcp-nixos" "$@"
fi
if ! command -v nix > /dev/null 2>&1; then
  printf 'mcp-nixos : ni le binaire ni nix ne sont disponibles sur ce poste.\n' >&2
  exit 1
fi

mkdir -p "$etat"
verrou="$lien.construction"
if ! { [ -f "$verrou" ] && kill -0 "$(cat "$verrou" 2> /dev/null)" 2> /dev/null; }; then
  setsid nohup nix --extra-experimental-features 'nix-command flakes' \
    build --out-link "$lien" "github:NixOS/nixpkgs/$REVISION#mcp-nixos" \
    > "$lien.journal" 2>&1 < /dev/null &
  printf '%s\n' "$!" > "$verrou"
fi

for _ in $(seq 1 "$ATTENTE"); do
  if [ -x "$lien/bin/mcp-nixos" ]; then
    rm -f "$verrou"
    exec "$lien/bin/mcp-nixos" "$@"
  fi
  sleep 1
done

printf 'mcp-nixos se construit (premier démarrage) : disponible à la session suivante.\n' >&2
printf 'Journal : %s\n' "$lien.journal" >&2
exit 1
