# Installation — plugin-nixos

Claude Code **2.1.295 ou plus** requis : les hooks sont en forme exec. La procédure, première
session d'un poste neuf comprise, est dans le [README](../README.md#installer).

## Portée du garde

Installé pour le compte, le plugin pose son garde, `hooks/scripts/garde-nixos.sh`, dans toutes
les sessions de la machine, Flutter et web comprises. Il y reste inerte hors des commandes Nix :
voir [ce que le garde refuse](../README.md#ce-que-le-garde-refuse).
