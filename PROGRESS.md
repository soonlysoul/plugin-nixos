# PROGRESS — plugin-nixos

Réécrit au modèle de plugin-flutter par plugin-plugin le 2026-10-20, depuis plugin-nixos 0.1.2 à
dc6ea53 ; remplace l'original à partir de 0.2.0.

## État courant

Charpente de plugin-plugin ; contenu métier de 0.1.2 gardé tel quel, sauf ce que le modèle
impose : forme exec des hooks, arborescence `hooks/scripts/`, harnais de tests. La suite portée
garde chaque cas d'origine, et `pp.sh check` n'y relève aucun écart. Claude Code 2.1.295 au moins.
