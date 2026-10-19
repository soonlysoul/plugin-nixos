# Pourquoi le plugin est bâti ainsi

Le plugin est né du plugin `nixos` du dépôt `nixos-config`, posé le 2026-10-15
pour porter les règles de ce dépôt à toutes les sessions de la machine. Celui-là
ne servait qu'un poste. Il codait `~/Nixos` en dur, supposait `conf-nixos/`, la
commande `nixos-up`, un manuel et ses tables, et il exigeait `jq` et
`mcp-nixos` installés. Sur un PC neuf, presque rien de cela n'existe.

Ce document dit ce qui a été repris, ce qui a changé, et la mesure derrière
chaque changement. Les détails vivent en tête de chaque fichier ; ici, la raison
et l'endroit.

## La configuration se trouve, et ne se devine pas

**Mesuré le 2026-10-19 sur le poste d'origine :** deux clones du même dépôt,
`~/Nixos` et `~/Documents/Nixos`. Le premier a neuf commits de retard. La
commande `nixos-up` installée porte le premier en dur. Le plugin d'origine,
qui nommait `~/Nixos`, faisait donc éditer le clone en retard depuis toute
session ouverte hors du dépôt, sans rien en dire.

D'où `nixconf localiser`. Il essaie sept sources dans un ordre fixe : la
variable explicite, le répertoire courant, le choix retenu, `nixos-up`, le lien
`/etc/nixos`, les emplacements usuels, puis `/etc/nixos`. Deux points le
gouvernent :

- **À deux candidats de même rang, il ne choisit pas.** `genre=ambigu`, les
  deux nommés, et `nixconf choisir` pour trancher une fois pour toutes. Deviner
  juste la plupart du temps, c'est éditer le mauvais dépôt le reste du temps.
- **Il dit ce qu'il n'a pas retenu.** Chaque `candidat=` est listé, et un
  `avertissement=` signale le piège ci-dessus quand il se présente.

L'hôte à construire suit la même règle que dans `nixos-config` : jamais deviné
depuis le nom de la machine. Sans argument, `verifier` construit toutes les
configurations du dépôt.

→ `scripts/nixconf`, bloc *DÉTECTION*.

## Une seule définition de « vérifié » — et celle du dépôt prime

`nixconf verifier` refait, dans le même ordre et avec les mêmes codes de
sortie, ce que fait `nixos-up --verifier`. Il refuse d'abord tout fichier non
enregistré (`4`), puis une description matérielle absente (`1`), puis il
construit `config.system.build.toplevel` sans lien et sans privilège (`2` en
cas d'échec). Il ne dépend pas de `nixos-up`. Sur le poste d'origine, le
`nixos-up` installé ignore `--verifier` (mesuré le 2026-10-19 : le système actif
précède l'arrivée du drapeau), et un PC neuf n'en a aucun.

Quand un dépôt documente sa propre commande, c'est elle qui fait foi : la skill
`verifie` le dit en tête. Deux définitions qui divergent valent moins qu'une.

**La preuve du 2026-10-19.** `/etc/nixos` du poste d'origine a été adopté dans un
dépôt jetable (`nixconf adopter`), puis vérifié. La construction a rendu
**exactement** le chemin de `/run/current-system`. L'adoption ne change donc
rien à ce que la configuration déclare.

## Pure d'abord, impure si la configuration l'exige

`--impure` partout aurait été plus simple. Mais `nixos-rebuild --flake` évalue en
mode pur : vérifier en impur masquerait une erreur que l'application
rencontrerait. Le repérage cherche ce qui lit hors du dépôt : un import par
chemin absolu (`/etc/nixos/…`), `<nixpkgs>`, `builtins.getEnv`. Il décide d'un
`--impure`, et la commande proposée le porte aussi. Ce que le repérage manque,
la construction le rattrape : sur une erreur de pureté, elle réessaie en impur
et le dit.

La description matérielle n'entre jamais dans le dépôt. Elle porte les
identifiants de disques du poste, et c'est la règle de `nixos-config` que ce
plugin garde. `adopter` la laisse donc dans `/etc/nixos` et en réécrit l'import.

## Le garde : repris, élargi, et deux défauts corrigés

`hooks/lib-commande.sh` et `hooks/garde-nixos.sh` reprennent ceux de
`nixos-config`. Le garde juge une invocation, pas une chaîne, couvre les seize
chemins de traverse, n'exempte un argument que dans **son** segment, et ne porte
aucun refus générique. Ce qui a changé :

**Construire passe.** `nixos-config` refusait tout `nixos-rebuild`, parce que
`nixos-up --verifier` y tenait le rôle de preuve. Sur un PC neuf, il n'existe pas
d'autre preuve que `nixos-rebuild build`. Seules les sous-commandes qui
activent sont refusées. Une sous-commande inconnue ou illisible l'est aussi.

**Quatre familles au lieu de trois.** S'ajoutent `nh`,
`switch-to-configuration`, `nixos-install` et `nixos-generate-config` qui écrit.
S'ajoute surtout l'installation impérative (`nix-env -i`, `nix profile
install`) : un paquet posé ainsi survit à tous les rebuilds sans figurer nulle
part dans la configuration.

**Sans jq, il lit encore.** Un NixOS neuf n'a pas `jq`. Le garde d'origine
refusait alors toute commande qui nommait un outil gardé, ce qui était sûr mais
inutilisable. Le repli passe par l'évaluateur de Nix : 49 ms, et le même texte
que `jq` au caractère près (mesuré le 2026-10-19). Sans `jq` ni `nix`, il refuse
encore plutôt que de s'éteindre.

**Défaut 1 — le pré-filtre avait un trou.** Il cherchait `nix store` d'un bloc,
et `nix --option a b store gc` passait (mesuré le 2026-10-19). Il cherche
désormais `nix` seul. Le pré-filtre doit être un sur-ensemble de ce que les
règles jugent.

**Défaut 2 — au-delà de 64 Kio, le garde laissait passer.** Ses tests passaient
par `printf … | grep -q`, sous `set -o pipefail`. `grep -q` s'arrête au premier
résultat ; sur un texte plus grand que le tampon d'un tube, `printf` reçoit
SIGPIPE et le tube entier rend faux. Mesuré le 2026-10-19 sur une commande de
192 Kio qui commençait par `x=nixos-rebuild; $x switch` : le garde de
`nixos-config` sort en **0** trois fois sur trois, celui-ci en **2** trois fois sur
trois. Tous les tests passent maintenant par une here-string. La même mesure
montrait une durée de plus de deux minutes, au-delà du délai du hook, où la
commande passe sans avoir été jugée. La commande est désormais découpée **une**
fois, et non une fois par outil : 1,6 s.

**Monitor est jugé.** Son champ `command` est une commande shell, lancée en
arrière-plan, mais lancée.

**`nix-store --gc --print-roots` passe.** Les drapeaux `--print-*` font de `--gc`
une requête qui ne collecte rien. Le garde d'origine refusait la seule manière
de voir ce qui enracine un chemin.

→ les en-têtes des deux fichiers ; les cas dans `tests/test_garde.sh`.

## Le serveur MCP : construit une fois, enraciné

`mcp-nixos` est absent de nixpkgs stable (mesuré le 2026-10-19 sur la 25.05). Le
lanceur prend celui du système s'il est déclaré. Sinon, il en construit une
copie depuis une révision **épinglée** de nixpkgs-unstable. Une branche mouvante
ferait retélécharger nixpkgs à chaque déplacement.

Le premier `nix run` n'avait pas fini en 4 min 40 s (mesuré le 2026-10-19 : une
fermeture Python entière à télécharger). Claude Code abandonne un serveur bien
avant, et le tue, téléchargement compris. La construction part donc
**détachée**, une fois. Le lanceur l'attend vingt secondes, puis s'efface en
disant que le serveur sera là à la session suivante.

Elle écrit un `--out-link` dans `~/.local/state/plugin-nixos/`, qui est une
racine du ramasse-miettes (vérifié dans `/nix/var/nix/gcroots/auto`). C'est la
leçon de `nixos-config` : un chemin du store nommé dans une configuration n'est
pas enraciné, et son serveur `playwright` en est mort sans que rien ne le
signale.

Démarrage mesuré ensuite : 5 à 16 s sur un poste à charge 21, à mesure que les
caches se remplissent.

## Compatible avec le Claude Code de nixpkgs stable

Un PC neuf a le `claude-code` de son canal stable. `nixos-config` mesurait 2.1.223
en 26.05 le 2026-09-20, en retard sur la série courante. `hooks/hooks.json` s'en
tient donc à la forme la plus ancienne, une chaîne `command`, sans `args` ni
`onFailure`, et `tests/test_statique.sh` l'impose. Hypothèse, non mesurée : ces
champs récents seraient refusés ou ignorés par une version plus ancienne. La
forme ancienne, elle, fonctionne partout.

## Ce qui a été écarté, et pour quelle raison propre

- **Une skill « appliquer ».** Le garde refuse l'activation : elle ne pourrait
  qu'imprimer une commande, ce que `nixconf proposer` fait déjà.
- **Un contexte injecté au démarrage de chaque session.** Le plugin tourne dans
  toutes les sessions, Flutter et web compris ; il y coûterait du contexte pour
  rien. Les descriptions des skills exigent le vocabulaire NixOS et excluent
  les projets applicatifs.
- **Le formatage automatique des `.nix`.** Un dépôt formaté par un autre outil
  serait réécrit en entier. `nixconf lints` relit, il ne réécrit pas, et seulement
  les fichiers touchés.
- **`nix flake lock` dans `adopter`.** Il demande le réseau à l'étape où l'on
  veut seulement copier. La première construction verrouille, et `verifier`
  signale le `flake.lock` neuf, à enregistrer.
- **Des permissions.** Un plugin ne peut pas en distribuer (seules `agent` et
  `subagentStatusLine` d'un `settings.json` de plugin prennent effet). Le refus
  voyage par le hook, et chaque appel à `nixconf` demande confirmation jusqu'à ce
  que l'utilisateur dise de ne plus demander.

## Ce que le dispositif ne garantit pas

Le garde refuse des **formes**, et une forme se contourne : un alias, un script
intermédiaire, `find -exec`. Il protège d'un geste distrait, pas d'une
intention. Ce qui tient vraiment est ailleurs : `sudo` qui demande un mot de
passe, et les droits du noyau sur `/nix/var/nix/profiles`.

`nixconf verifier` prouve qu'une configuration s'évalue et se construit. Il ne
prouve pas que ses services démarrent : cela ne se voit qu'à l'activation.
