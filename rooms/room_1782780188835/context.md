# Watchtower — Contexte du projet

## Qu'est-ce qu'AgentBase ?

AgentBase est une application mobile (Flutter) qui sert de **hub de coordination pour des agents IA travaillant sur des projets de développement**. Chaque "room" représente un projet ou un espace de travail distinct. À l'intérieur d'une room, on retrouve :

- **Accueil** — vue d'ensemble du projet (stack, stats, accès rapides).
- **Contexte** — la mémoire longue durée du projet : à quoi il sert, son état, ses objectifs. Doit être tenu à jour.
- **Règles** — les contraintes et conventions que tout agent intervenant sur ce projet doit respecter.
- **Chat** — discussion en direct entre agents/humains sur la room.
- **Transcription** — journal des interventions des agents : ce qui a été demandé, ce qui a été fait.
- **Prompts** — file d'attente de tâches à envoyer aux agents.

Tout est stocké sous forme de fichiers Markdown/JSON dans un dépôt GitHub (`ferelking242/agentbase`), sous `rooms/{roomId}/`. AgentBase n'a pas de backend dédié : GitHub est la base de données.

## La room "Watchtower"

Watchtower est la room **meta** : elle sert à superviser le développement d'AgentBase lui-même. C'est ici que les agents qui travaillent sur le code d'AgentBase (bugfixes, nouvelles fonctionnalités, refonte visuelle) documentent leur travail, discutent des priorités, et suivent l'avancement.

Objectifs de cette room :
1. Garder une trace claire de ce qui a été demandé par le propriétaire du projet et de ce qui a été livré.
2. Centraliser les règles de qualité et de style à respecter dans le code d'AgentBase.
3. Servir de point de repère pour tout nouvel agent qui reprend le travail : en lisant ce contexte et les règles, il doit comprendre immédiatement le projet sans avoir à tout redécouvrir.

## Instructions pour l'onglet Transcription

Chaque agent qui effectue une modification sur AgentBase doit ajouter une entrée de transcription résumant :
- **Demande** : la demande exacte formulée (en une ou deux phrases claires).
- **Actions** : les fichiers modifiés et la nature du changement (bugfix, nouvelle fonctionnalité, refonte UI…), sans détail technique excessif — l'objectif est qu'un humain non-technique puisse comprendre ce qui a changé.

Ne pas transcrire de contenu sensible (tokens, secrets). Une entrée par lot de travail cohérent, pas une entrée par fichier.

## État actuel

Le projet est fonctionnel et en amélioration continue, avancée "doucement", un point à la fois, suivant les demandes du propriétaire (francophone). Le code est vérifié manuellement (pas de SDK Flutter disponible dans l'environnement de l'agent) puis validé par la CI GitHub Actions.
