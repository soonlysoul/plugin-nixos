# plugin-nixos

Plugin Claude Code qui gère la configuration NixOS d'un poste. Il trouve la
configuration, ou la reprend de `/etc/nixos` dans un dépôt git à soi. Il prouve
une option avant de l'écrire, vérifie sans privilège et s'arrête sur la commande
qui applique : c'est l'utilisateur qui la lance. Un garde refuse, dans toutes
les sessions, d'activer une configuration, d'installer un paquet hors de la
configuration et de détruire des générations.

Rien n'y est propre à une machine. Installé sur un PC neuf, il sert tout de
suite, sans `jq`, sans flakes activés et sans `mcp-nixos` déclaré.

Version **0.2.0**. Testé avec Claude Code 2.1.296 sur NixOS 25.05 ; Claude Code
2.1.295 ou plus requis (forme exec des hooks).

## Ce qu'il apporte

| Composant | Rôle |
| --- | --- |
| Skill `installe` | Équipe le poste : trouve la configuration, clone le dépôt existant ou reprend `/etc/nixos` dans un dépôt git, ajoute ce poste au dépôt, vérifie, propose |
| Skill `cherche` | Trouve une option ou un paquet et le **prouve** dans la révision que la configuration épingle, overlays compris ; dit où l'écrire |
| Skill `modifie` | Écrit dans le dépôt (jamais dans `/etc/nixos`), en suivant les règles du dépôt, puis vérifie et propose |
| Skill `verifie` | Construit chaque configuration sans privilège, montre ce qui changerait, relit les fichiers touchés, puis propose |
| Hook `garde-nixos` | Refuse d'activer, d'installer impérativement et de détruire des générations ; inerte sur tout le reste |
| Serveur MCP `nixos` | `mcp-nixos` : options et paquets interrogeables plutôt que devinés |
| Script `nixconf` | Ce que les skills appellent : `localiser`, `verifier`, `option`, `paquet`, `ecart`, `lints`, `proposer`, `adopter`, `choisir` |

## Installer

Prérequis : NixOS, un Claude Code qui connaît les plugins, et `git`. `jq` est
recommandé mais pas requis. Celui de nixpkgs 25.05 ne convient pas : c'est la
1.0.85, qui n'a pas de commande `plugin` (mesuré le 2026-10-19).

**Sur un NixOS fraîchement installé**, Claude Code et git ne sont pas encore
déclarés. Un shell éphémère suffit pour la première session : il n'installe
rien, et la configuration les déclarera ensuite.

```bash
rev=github:NixOS/nixpkgs/7fd4004d0511991fff3a0524856a9be09e28c5f0
NIXPKGS_ALLOW_UNFREE=1 nix --extra-experimental-features 'nix-command flakes' \
  shell --impure "$rev#claude-code" "$rev#git"
```

Il fournit Claude Code 2.1.296, la version testée, pris à la révision de
nixpkgs-unstable que le serveur MCP épingle déjà. Le raccourci `nixpkgs#…`, lui,
suivrait le registre du poste, qui peut désigner le canal stable. claude-code
n'étant pas libre, le cache binaire ne l'a pas : la première fois, Nix le
construit sur place à partir du binaire publié.

Puis, depuis la marketplace `soon` :

```bash
claude plugin marketplace add soonlysoul/claude-plugins
claude plugin install plugin-nixos@soon --scope user
```

Sans clé SSH GitHub sur le poste, exporter d'abord
`CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1`.

Pour l'essayer depuis une copie du dépôt, sans l'installer :
`claude --plugin-dir /chemin/vers/plugin-nixos`.

## Premier usage

Ouvrir Claude Code n'importe où, puis :

```
/plugin-nixos:installe
```

Ou, si la configuration est déjà dans un dépôt :
`/plugin-nixos:installe https://github.com/<vous>/<config>`.

Ensuite, dans n'importe quelle session — y compris celle d'un projet qui a
besoin d'un paquet : « ajoute ripgrep à ma config NixOS », « active SSH sur
NixOS », « vérifie ma config NixOS ».

## Où il cherche la configuration

Dans cet ordre, et le premier qui répond l'emporte :

1. `$NIXOS_CONF` ;
2. le répertoire courant et ses parents ;
3. le choix retenu par `nixconf choisir <répertoire>` (dans `~/.config/nixconf/`) ;
4. le dépôt que porte la commande `nixos-up` installée, s'il y en a une ;
5. la cible de `/etc/nixos`, si c'est un lien ;
6. les emplacements usuels (`~/Nixos`, `~/nixos-config`, `~/.config/nixos`…),
   **seulement s'il n'y en a qu'un** — à deux, il ne choisit pas et le dit ;
7. `/etc/nixos` lui-même.

Un flake est reconnu à sa sortie `nixosConfigurations`, à la racine ou dans un
sous-répertoire `conf-nixos/`. L'hôte à construire ne se devine jamais depuis le
nom de la machine : sans argument, `verifier` construit toutes les
configurations du dépôt.

## Ce que le garde refuse

| Famille | Commandes refusées | Ce qui reste libre |
| --- | --- | --- |
| Activer le système | `nixos-rebuild switch\|boot\|test\|dry-activate`, `switch-to-configuration`, `nh os switch\|boot\|test`, `nixos-install`, `nixos-generate-config` qui écrit, `nixos-up` sans `--verifier` | `nixos-rebuild build`, `dry-build`, `build-vm`, `list-generations` ; `nh os build` ; `nix build` |
| Activer l'utilisateur | `home-manager switch\|init\|uninstall`, `nh home switch` | `home-manager build`, `instantiate`, `generations`, `packages`, `news`, `option` ; `nh home build` |
| Installer hors configuration | `nix-env -i/-u/-e…`, `nix profile install\|add\|remove\|upgrade` | `nix-env -q`, `nix profile list`, `nix shell nixpkgs#x -c …` |
| Détruire des générations | `nix-collect-garbage`, `nix store gc\|delete`, `nix-store --gc\|--delete`, `nh clean`, `nix-env --delete-generations`, `home-manager expire-generations\|remove-generations` | `nix store diff-closures`, `nix-store -q` |

`nixos-rebuild`, `nh` et `home-manager` sont jugés sur liste blanche : une
sous-commande absente de la colonne de droite, ou masquée (`sw\itch`), est
refusée.

Il juge une **invocation**, pas une chaîne. `grep nixos-rebuild fichier` passe,
et un message de commit qui en parle aussi. Il couvre les chemins de traverse
(chemin absolu, `env`, `sudo`, `sh -c`, `xargs`, variable, `nix run …#home-manager`)
et les enveloppes qui élèvent ou lancent ailleurs (`run0`, `pkexec`,
`systemd-run`, `flock`, `chroot`, `tmux`…).
Il ne prétend pas arrêter une intention : il protège d'un geste distrait. Il ne
porte aucun refus générique (`rm -rf`, `sudo` seul, `git push --force`) : il
tourne dans toutes les sessions, et ces règles-là appartiennent aux projets qui
les veulent.

Une commande refusée se lance à la main, dans un terminal.

## Ce qu'il ne fait pas

- **Il n'applique jamais.** `nixconf proposer` imprime la commande ; c'est
  l'utilisateur qui la lance. Une skill « appliquer » ne pourrait rien faire de
  plus.
- **Il ne distribue pas de permissions.** Un plugin ne le peut pas. Chaque appel
  à `nixconf` demande donc une confirmation, jusqu'à ce que l'utilisateur
  réponde « oui, et ne plus demander ».
- **Il n'écrit rien dans `/etc/nixos`**, ni ailleurs hors du dépôt de
  configuration. Seules exceptions : son choix, dans `~/.config/nixconf/`, et la
  copie de `mcp-nixos`, dans `~/.local/state/plugin-nixos/`.

## Le serveur MCP au premier démarrage

`mcp-nixos` n'est pas dans nixpkgs stable. S'il n'est pas déclaré, le lanceur le
construit une fois, depuis une révision épinglée de nixpkgs-unstable, en arrière-plan.
Le premier démarrage peut donc annoncer « disponible à la session suivante ».
Ensuite, il démarre en quelques secondes, et un lien dans `~/.local/state` le
protège du ramasse-miettes. Le déclarer dans la configuration supprime cette attente :
`/plugin-nixos:installe` le propose.

Hors ligne, la découverte s'arrête et la preuve locale continue : aucune
vérification ne dépend du serveur.

## Serveurs MCP

Déclarés dans `.mcp.json`, sans rien installer : chaque valeur vient de l'environnement de l'utilisateur, en `${VAR}`. Un skill qui dépend d'un serveur a besoin d'une doublure dans `evals/mocks/<serveur>/` pour être évalué ; sans elle, le serveur n'est pas démarré pendant une évaluation.

- `nixos` — local, lancé par `scripts/mcp-nixos.sh` ; variables : aucune ; doublure d'évaluation : `evals/mocks/nixos/`.

## Tests

```bash
bash tests/run-all.sh
```

Les suites tournent en bash et `jq`, sans réseau, sans session Claude et sans
quota. Un `nix` simulé remplace les constructions, et un `sudo` piégé prouve
qu'aucune sous-commande ne l'appelle.

## Documentation

- [Architecture](ARCHITECTURE.md) : les décisions, et la mesure derrière chacune
- [Journal des versions](CHANGELOG.md)

## Licence

MIT — voir [LICENSE](LICENSE).
