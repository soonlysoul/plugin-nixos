---
name: verifie
description: "Prouve qu'une configuration NixOS tient — sans privilège et sans rien changer au système : enregistrement git, construction de CHAQUE configuration du dépôt, lints des fichiers touchés, tests du dépôt, et ce que le changement ferait à la machine paquet par paquet. Utilise sur /plugin-nixos:verifie, « vérifie ma config NixOS », « ma configuration NixOS construit-elle ? », « prouve que ma config NixOS tient », ou dès qu'un fichier .nix d'une configuration NixOS a été modifié. Ne dépose rien, n'applique rien : elle finit sur la commande à proposer. Ne vise que la configuration du système, jamais le build d'un projet applicatif."
argument-hint: "[hôte]"
---

# /plugin-nixos:verifie

La boucle qui donne le droit de dire « j'ai vérifié ». Chaque étape produit une
sortie, et **cette sortie doit être montrée** : une étape dont on rapporte le
résultat sans l'avoir affichée n'a pas eu lieu.

Aucune étape n'élève les privilèges. Si l'une échoue, s'arrêter là et le dire :
une vérification interrompue laisse la question ouverte, ce qui vaut mieux
qu'une réponse supposée.

Hôte demandé : $ARGUMENTS

**Le dépôt d'abord.** S'il documente sa propre commande de vérification — dans
son `CLAUDE.md` ou son manuel (`regles=` de `localiser`) — c'est elle qui fait
foi, et les étapes ci-dessous ne la remplacent pas : deux définitions de
« vérifié » qui divergent valent moins qu'une.

## 1. Construire — chaque configuration, pas seulement celle de ce poste

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nixconf" verifier [hôte…]
```

Sans argument, elle construit **toutes** les configurations du dépôt : c'est le
seul contrôle qui prouve qu'une retouche commune ne casse pas l'autre poste.
Elle construit l'assemblage exact (`config.system.build.toplevel`), sans lien
dans le dépôt et sans privilège.

Lire le code de sortie :

| Code | Sens | Geste |
|---|---|---|
| `0` | tout tient | étape 2 |
| `4` | un fichier n'est pas enregistré dans git | montrer la liste, puis le `git add` qu'elle donne, et relancer — **jamais l'inverse** : vérifier avant d'enregistrer prouve autre chose que ce qu'on vient d'écrire |
| `2` | une configuration est invalide | lire la sortie, corriger, relancer |
| `1` | poste pas prêt (configuration ambiguë, description matérielle absente) | suivre ce qu'elle dit ; ce qui demande `sudo` se propose |

Une première construction écrit `flake.lock` : elle le signale, et il est à
enregistrer comme le reste. Si elle a dû passer en `--impure`, elle le dit ; la
commande d'application devra le porter aussi.

## 2. Ce que ça changerait

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nixconf" ecart <chemin affiché à l'étape 1>
```

« Ça construit » n'est pas « voici ce qui va bouger ». C'est cette sortie qui
permet à l'utilisateur de décider. Le chemin n'a pas de racine dans le store :
s'il a disparu, relancer l'étape 1 plutôt que de conclure à une erreur.

## 3. La forme

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nixconf" lints
```

`nixfmt`, `statix` et `deadnix` sur les seuls fichiers `.nix` modifiés depuis le
dernier commit — un dépôt qui n'a jamais été passé à ces outils signalerait
tout. Un outil absent est dit, avec la commande pour l'essayer sans
l'installer. Distinguer ce que ce travail a introduit de ce qui était déjà là :
seul le premier est à corriger ici.

## 4. Les tests du dépôt

Si le dépôt a un harnais (`tests/`, une cible `nix flake check`), le lancer
quand un script, un test ou un document qu'il relit a changé — ses règles disent
lequel. Montrer la sortie.

## 5. Conclure, sans agir

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nixconf" proposer [hôte]
```

Afficher la séquence qu'elle imprime, et **s'arrêter là**. Ce qu'elle ne prouve
pas, le dire aussi : la construction montre que la configuration s'évalue et se
construit, pas que ses services démarrent — cela ne se voit qu'à l'activation.
