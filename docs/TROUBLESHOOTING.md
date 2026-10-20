# Dépannage — plugin-nixos

| Symptôme | Cause probable | Que faire |
| --- | --- | --- |
| Le serveur MCP annonce « disponible à la session suivante » | Premier démarrage : `mcp-nixos` se construit | Voir [le serveur MCP au premier démarrage](../README.md#le-serveur-mcp-au-premier-démarrage) |
| `claude plugin validate` inconnu | Claude Code de nixpkgs 25.05 (1.0.85) | Voir [installer](../README.md#installer) |
| `bash tests/run-all.sh` sort en 2 | `jq` ou `claude` absent du PATH | Les prendre dans un shell éphémère, comme à l'installation |
