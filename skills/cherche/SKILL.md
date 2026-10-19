---
name: cherche
description: "Trouve une option NixOS ou un paquet nixpkgs, PROUVE qu'il existe dans la révision de nixpkgs que la configuration de ce poste épingle — overlays compris — et dit où l'écrire. Utilise sur /plugin-nixos:cherche, « quelle option NixOS pour… », « comment on active X sur NixOS », « le paquet Y existe-t-il dans nixpkgs », « quelle version de Z dans nixpkgs », « il me faut unstable pour ça ? », « où je mets cette option dans ma config NixOS », ou avant d'ajouter quoi que ce soit à une configuration NixOS. Remplace la devinette : une option inventée ne se voit qu'à la construction. Ne vise que NixOS et nixpkgs, jamais npm, pip ou pub.dev."
argument-hint: "[ce qu'on cherche]"
---

# /plugin-nixos:cherche

Une option NixOS ne se devine pas : elle existe ou non dans la révision de
nixpkgs que **cette** configuration épingle. Le savoir avant d'écrire coûte
quelques secondes ; une option inventée ne se voit qu'à la construction, dans un
message qui ne dit pas quoi mettre à la place.

Demande : $ARGUMENTS

**La découverte est en réseau, la preuve est locale.** Ne pas confondre les
deux : c'est tout le sujet de cette skill.

## 0. Quelle configuration

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nixconf" localiser
```

`genre=ambigu` ou `aucun` : passer par `/plugin-nixos:installe` d'abord. Plusieurs
configurations dans le dépôt : les preuves ci-dessous prennent le nom de
l'hôte — `nixconf hotes` les liste. Il ne se devine jamais depuis le nom de la
machine.

## 1. Découvrir — le serveur MCP

Le serveur MCP `nixos` du plugin expose ses outils (préfixés `mcp__…nixos…`)
qui interrogent search.nixos.org et d'autres sources. Préciser **le canal de la
configuration** — la version que `localiser` affiche, ou l'entrée `nixpkgs` du
`flake.nix` : une option qui n'existe qu'en unstable ne se construira pas sur une
configuration stable, et la proposer serait pire que ne rien trouver.

- une option : `action: "search"`, `source: "nixos"`, `type: "option"`
- son détail : `action: "info"` sur le nom exact
- un paquet : `type: "package"`

Si le serveur ne répond pas — hors ligne, ou premier démarrage qui télécharge
encore — le dire, et passer à l'étape 2 seule : elle ne dépend de rien.
Sans serveur, `nix search nixpkgs <mot>` cherche aussi, en local mais lentement
(la première fois évalue tout nixpkgs).

## 2. Prouver — dans la configuration elle-même

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nixconf" option <chemin.de.l.option> [hôte]
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nixconf" paquet <attribut> [hôte]
```

Ce n'est pas « nixpkgs en général » : `option` évalue
`nixosConfigurations.<hôte>.options.<chemin>` de cette configuration, `paquet`
évalue `nixosConfigurations.<hôte>.pkgs.<attribut>` — les paquets **tels que la
configuration les voit, overlays compris**. Un paquet pris à unstable par un
overlay y apparaît donc avec la version d'unstable, sans avoir à chercher dans
quelle révision le prendre.

Une option qui n'existe pas fait échouer l'évaluation (sortie 2) : c'est la
preuve. Un chemin qui désigne un ensemble d'options en liste les sous-options.

## 3. Placer — selon le dépôt, pas selon cette skill

Lire **les règles du dépôt** (`regles=` dans la sortie de `localiser`) : un dépôt
qui documente où écrire une option nouvelle — une table de domaines, un module
par sujet, une fiche par machine — fait foi. Ne pas la deviner, la lire.

À défaut de règle écrite, ce qui tient dans tout dépôt :

- ce qui n'a de sens que sur un poste (nom, architecture, matériel) va dans le
  fichier de ce poste ;
- le reste va dans le module qui porte déjà ce sujet — chercher l'option voisine
  (`grep -rn services.openssh <configuration>`) avant de créer un fichier ;
- un module neuf s'importe là où les autres le sont.

## 4. Stable ou unstable

Le paquet manque à la révision stable, ou y est trop ancien ? Il passe par un
**overlay** sur une entrée `nixpkgs-unstable` épinglée — si le dépôt en a déjà
une, suivre son motif. Les outils MCP de versions disent quelle révision de
nixpkgs porte la version voulue.

**Ne pas proposer `nix flake update` à la légère.** Il change toutes les
versions de la machine d'un coup. Le dépôt peut geler une entrée
délibérément — son `flake.nix` le dit alors. Mettre à jour est un geste séparé
et assumé, pas un moyen d'obtenir un paquet.

## Ce que cette skill ne fait pas

Elle ne modifie rien. Elle trouve, elle prouve, elle dit où — puis
`/plugin-nixos:modifie` écrit et `/plugin-nixos:verifie` montre que ce qui a été écrit tient.
