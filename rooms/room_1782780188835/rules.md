# Règles pour Watchtower

## Setup obligatoire — première chose à faire

**OBLIGATOIRE** : avant tout travail de code, cloner les deux dépôts en local à la racine du workspace. Ne jamais modifier de fichiers via l'API GitHub sans avoir d'abord le code en local pour le lire. Ne jamais deviner la structure — toujours lire le fichier existant avant d'écrire.

```
workspace/
├── watchtower/              ← github.com/ferelking242/watchtower
└── watchtower-extensions/   ← github.com/ferelking242/watchtower-extensions
```

## Références externes (lecture seule)

Pour s'inspirer ou copier du code d'un projet tiers (fork sœur, lib upstream, exemple d'implémentation — ex. `mangayomi`, `mangayomi-extensions`), le cloner dans `external_projects/` à la racine du workspace plutôt que de lire des fragments épars sur le web. Ces clones sont **strictement lecture seule** : on y copie du code vers `watchtower/` ou `watchtower-extensions/`, on n'y pousse jamais.

## Règles absolues

1. **Push immédiat.** Dès qu'une modification est complète, pousser immédiatement sur `main`. Une tâche finie = un push.
2. **Surveiller le build après chaque push.** Suivre `Build Flutter Web` jusqu'à sa conclusion. En cas d'échec : lire les logs, corriger, repousser, resurveiller.
3. **Pas de mock, pas de placeholder.** Aucun code factice, aucun TODO laissé en place.
4. **Vérifier avant de déclarer terminé.** Relire l'historique et confirmer que chaque tâche demandée a bien été poussée avant de dire que c'est fini.
5. **Toujours demander la suite.** Une fois une tâche terminée et poussée, demander explicitement quelle est la prochaine priorité.
6. **Format des commits obligatoire** : `type: description courte en anglais`.

   | Type | Quand l'utiliser |
   |---|---|
   | `feat:` | Nouvelle fonctionnalité |
   | `change:` | Changement de comportement existant |
   | `improve:` | Amélioration sans nouveau comportement (perf, UX, refactor) |
   | `fix:` | Correction de bug |
   | `remove:` | Suppression de code/feature/fichier |

   Interdit : messages génériques (`update`, `fix stuff`, `wip`, `changes`).

7. **Pousser via l'API GitHub uniquement.** Le git commit/push direct n'est pas disponible dans le sandbox de l'agent ; utiliser l'API Contents/Git avec le token stocké en secret d'environnement (jamais un token en clair dans un fichier, un commit ou un message).
8. **Toujours documenter dans Transcription.** Après chaque modification livrée, ajouter une entrée claire et compréhensible par un non-développeur.
9. **Contexte à jour.** Si un changement modifie la structure ou le fonctionnement général du projet, mettre à jour `context.md` en conséquence.

## Note de sécurité

La v1 de ce contexte vivait dans un gist GitHub public, qui contenait un token d'accès personnel en clair. **Ce token doit être révoqué immédiatement** (Paramètres GitHub → Developer settings → Personal access tokens) et ne doit plus jamais être réutilisé ni republié où que ce soit. Toute automatisation doit utiliser exclusivement le secret d'environnement configuré pour ce workspace.
