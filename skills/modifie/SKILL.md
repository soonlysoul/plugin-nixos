---
name: modifie
description: "Modifie la configuration NixOS de ce poste depuis n'importe quelle session : trouve le dépôt de configuration (jamais /etc/nixos), y écrit, prouve sans appliquer, et finit sur la commande que l'utilisateur lance lui-même. Utilise sur /plugin-nixos:modifie, « ajoute le paquet X à ma config NixOS », « active le service Y sur NixOS », « modifie ma configuration NixOS », « installe Z sur mon NixOS », « change une option de ma machine NixOS », ou dès qu'une tâche demande d'écrire dans une configuration NixOS. Ne vise que la configuration du système : jamais un projet applicatif, même quand il tourne sous NixOS."
argument-hint: "[ce qu'il faut changer]"
---

# /plugin-nixos:modifie

La porte d'entrée de toute modification de la configuration du système, depuis
n'importe quelle session — y compris celle d'un projet applicatif qui a besoin
d'un paquet ou d'un service.

Demande : $ARGUMENTS

## 1. Trouver la configuration, et ses règles

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nixconf" localiser
```

- `genre=ambigu`, `aucun`, `classique` ou `inscriptible=non` : passer par
  `/plugin-nixos:installe`. On n'édite pas `/etc/nixos`.
- `avertissement=` : le lire à l'utilisateur avant d'aller plus loin.
- `regles=` : **lire chacun de ces fichiers en entier** avant la première
  écriture. Une session ouverte hors du dépôt n'a rien chargé de lui — ni son
  `CLAUDE.md`, ni ses permissions. Ses règles priment sur cette skill.

Trois règles valent partout, parce que leur oubli est silencieux ou
irréversible :

- **On édite le dépôt, jamais `/etc/nixos`.** Ni par `sudo`, ni par `tee`.
- **Un fichier neuf s'enregistre dans git avant toute construction.** Nix ne lit
  d'un dépôt git que ce qui y est enregistré : un module neuf non ajouté est
  absent de la construction, et la construction passe au vert sans lui.
- **Appliquer est un geste humain.** Le garde du plugin refuse
  `nixos-rebuild switch`, `home-manager switch` et leurs semblables ; le
  contourner n'est pas une option.

## 2. Chercher avant d'écrire

Invoquer `/plugin-nixos:cherche`. L'option ou le paquet est prouvé dans la révision
que la configuration épingle, et sa place est lue dans les règles du dépôt.

## 3. Écrire

Avant la première écriture :

```bash
git -C <depot> status --short
```

Le dépôt peut porter des changements **d'une autre tâche**. Ne pas les écraser,
ne pas les ranger dans ce travail sans le dire, et **ne pas changer de
branche** : deux sessions sur un même dépôt partagent le même `HEAD`.

- Un paquet **se déclare** dans un module. Ni `nix-env -i`, ni
  `nix profile install`, ni `pip`/`npm -g` : un paquet posé impérativement survit
  à tous les rebuilds sans figurer nulle part. Pour l'essayer sans l'installer :
  `nix shell nixpkgs#<paquet> -c <commande>`.
- `system.stateVersion` ne change jamais, même en montant de version.
- Aucun secret n'entre dans le dépôt.
- Hors du dépôt, Claude Code demande une confirmation par écriture : c'est
  normal.

Un fichier créé : `git -C <depot> add <fichier>` tout de suite. Le commit peut
attendre.

## 4. Prouver

Invoquer `/plugin-nixos:verifie`. Ne jamais annoncer qu'une configuration tient sans
avoir montré la sortie de la construction.

## 5. Finir sans agir

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nixconf" proposer [hôte]
```

Afficher ce qu'elle imprime, et s'arrêter. L'utilisateur applique lui-même.
