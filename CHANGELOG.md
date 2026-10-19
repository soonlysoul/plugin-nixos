# Journal des versions

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
