---
name: installe
description: "Équipe un poste NixOS pour que sa configuration se modifie depuis Claude Code : trouve la configuration, ou clone le dépôt de configuration existant, ou reprend /etc/nixos dans un dépôt git à soi, ajoute ce poste au dépôt s'il en décrit plusieurs, vérifie sans privilège et finit sur la commande à lancer soi-même. Utilise sur /plugin-nixos:installe, « nouveau PC NixOS », « je viens d'installer NixOS », « prépare ce poste NixOS », « mets ma config NixOS dans un dépôt git », « clone ma config NixOS sur ce PC », ou quand « nixconf localiser » répond genre=aucun, genre=ambigu ou inscriptible=non. Ne vise que la configuration du système, jamais un projet applicatif."
argument-hint: "[url du dépôt de configuration]"
---

# /plugin-nixos:installe

Le premier geste sur un poste NixOS. À la fin, la configuration vit dans un
dépôt git qu'on édite sans privilège, une construction a prouvé qu'elle tient,
et l'utilisateur a sous les yeux la commande qui l'appliquera — qu'il lance
lui-même.

Demande : $ARGUMENTS

Deux règles tiennent pendant toute la skill :

- **Rien ne s'écrit dans `/etc/nixos`.** Il appartient à root ; on le lit, on le
  copie, on ne le modifie pas.
- **Rien ne s'applique.** Ni `sudo`, ni `nixos-rebuild switch` : le garde du
  plugin les refuse, et le contourner n'est pas une option.

## 1. Le diagnostic

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nixconf" localiser
```

Montrer la sortie, puis la lire :

| Ce qu'elle dit | Ce qu'on fait |
|---|---|
| `nixos=non` | s'arrêter : ce plugin gère un système NixOS, et ce poste n'en est pas un |
| `genre=flake`, `inscriptible=oui` | le poste est déjà équipé : passer à l'étape 4 |
| `genre=ambigu` | montrer les `candidat=`, demander lequel fait foi, puis `nixconf choisir <répertoire>` |
| `genre=classique` ou `inscriptible=non` | la configuration n'est que dans `/etc/nixos` : étape 2 |
| `genre=aucun` | aucun `configuration.nix` : le poste n'est pas installé normalement, le dire et s'arrêter |
| `avertissement=` | le lire à l'utilisateur tel quel : il nomme un piège réel de ce poste |

## 2. D'où viendra la configuration

Demander à l'utilisateur, sans trancher à sa place :

- **Il a déjà un dépôt de configuration** (un autre poste, GitHub) — c'est le cas
  à préférer : ce poste rejoint la même source. L'URL est dans `$ARGUMENTS`, ou
  la lui demander. Étape 3a.
- **Il n'en a pas** — on reprend ce que l'installation a produit. Étape 3b.

## 3a. Cloner le dépôt existant

```bash
git clone <url> <destination>      # ~/Nixos par défaut — demander
```

Un dépôt privé demande des identifiants : c'est à l'utilisateur de lancer
`gh auth login` (interactif) s'il n'en a pas. Ne jamais lui demander de coller un
jeton dans la conversation.

Puis **lire les règles du dépôt, en entier** : `CLAUDE.md`, `README.md`, et les
documents qu'ils désignent. Elles priment sur cette skill — si le dépôt a sa
propre commande de vérification ou sa propre procédure pour « équiper une
nouvelle machine », c'est elle qu'on suit.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nixconf" choisir <destination>
```

## 3b. Reprendre /etc/nixos dans un dépôt à soi

Le nom de la configuration est **explicite** : proposer celui de la machine
(`uname -n`), et le faire confirmer.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nixconf" adopter <destination> <nom>
```

Ce qu'elle fait, et qu'il faut dire : elle copie `/etc/nixos` sauf la
description matérielle, qui reste à sa place et s'importe par son chemin
absolu ; elle enveloppe la configuration dans un flake qui épingle le canal du
système installé ; elle fait `git init` et `git add`, sans commit ; elle retient
la destination comme configuration de ce poste. `/etc/nixos` n'est pas modifié.

Relire ses avertissements (`⚠`) : un fichier illisible sans privilège n'a pas été
copié, un import par canal (`<…>`) est à convertir en entrée du flake.

## 4. Ce poste dans le dépôt

Un dépôt qui décrit **plusieurs** postes (un répertoire `machines/`, `hosts/`…)
n'a pas encore celui-ci. L'ajouter **selon la procédure du dépôt**, lue à
l'étape 3a, avec quatre invariants qu'aucune procédure ne lève :

- **`system.stateVersion` est celle de CE poste** — lue dans le
  `/etc/nixos/configuration.nix` produit à l'installation, jamais recopiée d'un
  autre poste. Elle fige le format des données sur disque.
- **La description matérielle reste dans `/etc/nixos`** et s'importe de là : elle
  porte les identifiants de disques de ce poste.
- **L'architecture vient de ce poste** : `uname -m`, ou `nixpkgs.hostPlatform` de
  sa description matérielle.
- **Aucun secret** — ni clé privée, ni jeton, ni mot de passe — n'entre dans le
  dépôt. Une clé SSH *publique* peut y entrer ; la privée jamais.

Montrer le fichier écrit avant de passer à la suite.

## 5. Vérifier

Invoquer `/plugin-nixos:verifie` sur la configuration de ce poste. La première
construction télécharge nixpkgs : plusieurs minutes, c'est normal — le dire
avant de lancer.

## 6. Ce que le plugin attend de la configuration

`localiser` a listé `outils_absents` et `flakes`. Proposer — sans l'imposer — de
les **déclarer** dans la configuration, par `/plugin-nixos:modifie` :

- `nix.settings.experimental-features = [ "nix-command" "flakes" ];` si
  `flakes=non` : sans cela, chaque commande d'application devra le rappeler ;
- `jq` et `git` : le garde du plugin lit plus vite avec `jq`, et git porte le dépôt ;
- `nixfmt`, `statix`, `deadnix`, `nvd` : les relectures de `/plugin-nixos:verifie` ;
- `mcp-nixos` : le serveur MCP du plugin démarre alors instantanément. Il n'est
  pas dans nixpkgs stable — `nixconf paquet mcp-nixos` le dira — et passe donc
  par un overlay de nixpkgs-unstable.

Jamais par `nix-env -i` ni `nix profile install` : le garde les refuse, et un
paquet posé ainsi ne figure nulle part dans la configuration.

## 7. Finir sans agir

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nixconf" proposer <nom>
```

Afficher les commandes qu'elle imprime, rappeler qu'un commit du dépôt est le
bon moment avant d'appliquer, et **s'arrêter là**. L'utilisateur applique
lui-même.
