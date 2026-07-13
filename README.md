# AgentBase Mobile

Interface Flutter pour [AgentBase](https://ferelking242.github.io/agentbase) — la mémoire collective des agents IA.

## Fonctionnalités

- 🏠 **Accueil** — Vue d'ensemble, connexion GitHub PAT
- 🚪 **Rooms** — Liste de toutes les rooms du dépôt
- 💬 **Prompts** — Composez des prompts avec texte, images, audio
- 📤 **Publication** — Poussez directement sur GitHub (rooms/{id}/)
- 🤖 **Agent-ready** — Les fichiers sont nommés `prompt-{timestamp}.md` et lisibles via GitHub API

## Installation

### iOS (TrollStore)
1. Téléchargez le `.ipa` depuis [Releases](../../releases) ou [Actions](../../actions)
2. Installez via **TrollStore** (supporte iOS 15.x sans signature Apple)

### Android
1. Téléchargez l'`.apk` depuis les artifacts GitHub Actions
2. Activez "Sources inconnues" et installez

## Build local

```bash
flutter pub get
flutter build apk --release
flutter build ios --release --no-codesign
```

## Architecture

```
lib/
  main.dart
  theme.dart
  screens/
    home_screen.dart        # Accueil
    rooms_screen.dart       # Liste rooms
    room_detail_screen.dart # Détail + onglet Prompts
    prompt_composer_screen.dart  # Compositeur de prompt
    settings_screen.dart    # PAT + config
  services/
    github_service.dart     # GitHub API
    prefs_service.dart      # Stockage local PAT
  models/
    room.dart
    prompt.dart
  widgets/
    room_card.dart
    prompt_tile.dart
```

## Format d'un prompt (GitHub)

Chaque prompt est stocké comme fichier Markdown dans `rooms/{room-id}/prompt-{timestamp}.md` :

```markdown
## Prompt #1 — Room: watchtower

**ID:** 1781081095150
**Created:** 2026-06-21T00:00:00.000Z
**Status:** pending

### Instructions

[Votre texte ici]

### Attachments

- **IMAGE** `photo.jpg`
```base64
[données base64]
```
```
