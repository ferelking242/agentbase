# Règles pour Watchtower

Ces règles s'appliquent à tout agent qui travaille sur le code source d'AgentBase (le projet lui-même, pas un projet tiers géré via l'app).

1. **Un changement à la fois.** Traiter les demandes une par une, "doucement" : ne pas mélanger plusieurs fonctionnalités non liées dans le même lot de modifications.
2. **Cohérence visuelle.** Réutiliser les composants et motifs déjà présents (`AppButton`, `AppCard`, `AppInput`, etc.) plutôt que d'en recréer de nouveaux. Respecter la palette de couleurs et l'espacement existants.
3. **Pas de coins imbriqués mal alignés.** Ne jamais placer un élément à coins arrondis directement contre le bord d'un conteneur dont le rayon est plus petit que son padding — toujours vérifier que les rayons s'emboîtent proprement (comme dans le pattern de la barre de saisie du Chat).
4. **Toujours documenter dans Transcription.** Après chaque modification livrée, ajouter une entrée de transcription claire et compréhensible par un non-développeur.
5. **Contexte à jour.** Si un changement modifie la structure ou le fonctionnement général de l'app, mettre à jour `context.md` en conséquence.
6. **Pousser via l'API GitHub.** Toute modification doit être poussée sur le dépôt `ferelking242/agentbase` via l'API Contents/Git de GitHub (jamais via un token autre que celui fourni de façon sécurisée).
7. **Vérifier avant de pousser.** En l'absence de SDK Flutter local, relire attentivement le code Dart modifié (syntaxe, imports, types) avant de le pousser, et s'appuyer sur la CI GitHub Actions comme filet de sécurité.
8. **Rester simple.** Préférer une solution simple et lisible à une solution complexe, surtout dans une base de code sans tests automatisés Flutter actifs.
