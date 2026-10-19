# Journal des versions

## 0.1.2 — 2026-10-19

- `home-manager` et `nh` sont jugés sur liste blanche, comme `nixos-rebuild`.
  `home-manager expire-generations`, `remove-generations`, `uninstall` et
  `init` sont refusés, ainsi que toute sous-commande masquée (`sw\itch`) ou
  inconnue. Seul `switch` l'était avant.

## 0.1.1 — 2026-10-19

- Le garde refuse aussi `nixos-rebuild switch` (et les autres gestes gardés)
  lancé par une enveloppe : `run0`, `pkexec`, `systemd-run`, `flock`, `chroot`,
  `setpriv`, `tmux`, et une vingtaine d'autres. Les dix-neuf présentes sur le
  poste de mesure laissaient passer, comme dans le garde de `nixos-config`.
- L'installation d'un poste neuf prend Claude Code à la révision de
  nixpkgs-unstable que le serveur MCP épingle déjà, soit la 2.1.296.
  `nixpkgs#claude-code` suit le registre du poste, et nixpkgs 25.05 fournit la
  1.0.85, qui ne connaît pas les plugins. Un test vérifie que les deux
  révisions restent la même.

## 0.1.0 — 2026-10-19

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
