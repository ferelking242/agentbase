# Watchtower — Contexte du projet

## Qu'est-ce que Watchtower ?

Watchtower est une application **Flutter** (fork de Mangayomi) de catalogue/lecture de contenus (animés, séries, docs) avec un système d'extensions séparé pour le scraping des sources.

## Repos

- **App** : `ferelking242/watchtower`
- **Extensions** : `ferelking242/watchtower-extensions`

## Stack & architecture

- **Flutter** stable · **Dart** · **Rust** (`flutter_rust_bridge`) · **Android NDK 27**
- CI :
  - `build_web.yml` — build Flutter Web → GitHub Pages, preview sur `https://ferelking242.github.io/watchtower/`
  - `build-arm64-debug.yml` — APK debug ARM64
- Fichiers générés `*.g.dart` / `*.freezed.dart` : **ne jamais éditer à la main**, ils sont régénérés automatiquement.
- Extensions écrites en JS (ex. `dotriv.js`, renommé `Dospiv` en v0.1.8), exposent `getCustomLists()` (sections de la home : Derniers ajouts, Top 15 Tendances, Animations, Docs & Spectacles) et `getCustomList(listId)`.

## Dernier état connu (24 juin 2026)

- `dotriv.js` → renommé Dospiv, v0.1.8, domaine `https://dospiv.com/fed960f`.
- `watch_home_screen.dart` → redesign complet : 3 tabs (Accueil, Popular, Latest), carousel responsive (max 50% de la hauteur écran), Top 15 avec grands numéros de classement, catalogue en grille à défilement infini en bas de la home, espacement des en-têtes de section réduit (24→14px).
- Version app : `8.1.157+157`.

## Instructions pour l'onglet Transcription (Watchtower)

Chaque agent qui travaille sur le code de Watchtower doit journaliser dans Transcription :
- **Demande** exacte formulée.
- **Actions** : fichiers/écrans modifiés, résumé compréhensible (pas de jargon Rust/Dart brut).

Une entrée par lot de travail cohérent (pas une par fichier), jamais de secret/token dedans.

## Historique

Ce projet utilisait auparavant un gist GitHub privé comme mémoire de contexte (v1). Cette room "Watchtower" dans AgentBase remplace ce gist : elle est maintenant la source de vérité pour le contexte et les règles de Watchtower.
