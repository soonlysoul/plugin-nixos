# Journal des versions

## [0.2.0] — 2026-10-20

Réécrit au modèle de plugin-flutter par plugin-plugin, depuis 0.1.2 : mêmes
skills, même garde, même serveur MCP, et chaque cas des suites d'origine garde
son équivalent.

- Claude Code **2.1.295 ou plus** requis : le garde est déclaré en forme exec
  (`command` « bash », le script dans `args`), avec `"onFailure": "block"`. Un
  garde qui plante, est introuvable ou dépasse ses 15 secondes bloque
  désormais la commande, au lieu de la laisser passer. Sur un poste resté à la
  2.1.223 de NixOS 26.05, le garde n'est plus garanti.
- Le garde et sa bibliothèque passent sous `hooks/scripts/`, le gabarit
  `flake.nix` sous `scripts/modeles/`.
- Les tests passent au harnais du modèle, sous `tests/hooks/` et
  `tests/static/`, avec les contrôles d'en-têtes, de manifeste, de chemins et
  du serveur MCP.
- `PROGRESS.md` et `docs/` : installation, usage, sécurité, dépannage.

Coût en contexte permanent : ~1126 tokens — installe ~300, modifie ~270, verifie ~280, cherche ~280.

## [0.1.2] — 2026-10-19

- `home-manager` et `nh` sont jugés sur liste blanche, comme `nixos-rebuild`.
  `home-manager expire-generations`, `remove-generations`, `uninstall` et
  `init` sont refusés, ainsi que toute sous-commande masquée (`sw\itch`) ou
  inconnue. Seul `switch` l'était avant.

## [0.1.1] — 2026-10-19

- Le garde refuse aussi `nixos-rebuild switch` (et les autres gestes gardés)
  lancé par une enveloppe : `run0`, `pkexec`, `systemd-run`, `flock`, `chroot`,
  `setpriv`, `tmux`, et une vingtaine d'autres. Les dix-neuf présentes sur le
  poste de mesure laissaient passer, comme dans le garde de `nixos-config`.
- L'installation d'un poste neuf prend Claude Code à la révision de
  nixpkgs-unstable que le serveur MCP épingle déjà, soit la 2.1.296.
  `nixpkgs#claude-code` suit le registre du poste, et nixpkgs 25.05 fournit la
  1.0.85, qui ne connaît pas les plugins. Un test vérifie que les deux
  révisions restent la même.

## [0.1.0] — 2026-10-19

Première version, tirée du plugin `nixos` du dépôt `nixos-config` et rendue
indépendante d'une machine.

- Skills `installe`, `cherche`, `modifie`, `verifie`.
- Script `nixconf` : `localiser`, `choisir`, `hotes`, `verifier`, `option`,
  `paquet`, `ecart`, `lints`, `proposer`, `adopter`.
- Hook `garde-nixos` sur Bash et Monitor : activation, installation impérative,
  destruction de générations.
- Serveur MCP `nixos` (`mcp-nixos`), construit une fois s'il n'est pas déclaré.
- Corrigé par rapport au garde d'origine : un pré-filtre qui laissait passer
  `nix --option … store gc` ; un faux négatif au-delà de 64 Kio (SIGPIPE sous
  `pipefail`) ; un jugement de plus de deux minutes sur une longue commande ; le
  refus de `nix-store --gc --print-roots`.
