# Watchtower — Contexte du projet

## Qu'est-ce que Watchtower ?
**Watchtower** est une app Flutter open-source (fork Mangayomi) qui lit **manga, anime, séries, musique et novels** via des extensions JavaScript. Gratuite, cross-platform (Android, iOS, Windows, macOS, Linux), avec un serveur headless déployable sur cloud.

---

## Repos

| Repo | Rôle | Tech |
|---|---|---|
| `ferelking242/watchtower` | App principale — tout y vit | Flutter + Rust + Go + Node.js |
| `ferelking242/watchtower-real` | UI TikTok-style (feed vertical) | Flutter — se fusionne dans watchtower |
| `ferelking242/watchtower-website` | Site docs | VitePress, hébergé sur Vercel |
| `ferelking242/watchtower-extensions` | Extensions JS sources | JavaScript |
| `ferelking242/watchtower-sdk-dart` | SDK Dart pour extensions | Dart |

---

## Architecture — repo `watchtower`

```
watchtower/
├── lib/
│   ├── modules/        ← UI par média (anime, manga, music, novels, player, history…)
│   ├── eval/           ← Moteur JS/Dart (QuickJS) — exécute les extensions
│   ├── remote/         ← Serveur HTTP embarqué (shelf) — port 4567
│   ├── services/       ← Réseau, téléchargements (Aria2), anti-bot, trackers
│   ├── ffi/            ← Serveur torrent Go (bindings C)
│   └── src/rust/       ← Bindings Rust (EPUB, image, TLS custom)
├── server/             ← Serveur Node.js headless (cloud)
│   ├── server.js       ← Express + QuickJS VM + bridges
│   ├── src/bridges/    ← HTTP, DOM (Cheerio), crypto, prefs
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── railway.toml
│   └── .env.example
├── deployment/         ← Guides + configs (Railway, Render, Docker, Colab, HF, RunPod)
├── rust/               ← Bibliothèque Rust (flutter_rust_bridge)
└── go/                 ← Client BitTorrent + streaming HTTP
```

---

## Deux modes serveur, même API

| Mode | Où | Comment |
|---|---|---|
| **Embarqué** | `lib/remote/` | shelf HTTP — l'app expose le port 4567 |
| **Headless** | `server/` | Node.js autonome — cloud (Railway, Render, Docker…) |

Les deux exécutent les mêmes extensions JS et exposent la même API REST.

### API REST
| Endpoint | Description |
|---|---|
| `GET /api/ping` | Health check |
| `GET /api/sources` | Liste des sources |
| `GET /api/sources/:id/popular` | Contenu populaire |
| `GET /api/sources/:id/latest` | Dernières mises à jour |
| `GET /api/sources/:id/search?q=` | Recherche |
| `GET /api/sources/:id/detail?url=` | Détail d'un item |
| `GET /api/sources/:id/videos?url=` | URLs de streaming vidéo |
| `GET /api/sources/:id/pages?url=` | Pages manga |

Auth : `X-Api-Key: <clé>` ou `Authorization: Bearer <clé>`

---

## Stack complet

| Couche | Tech |
|---|---|
| App UI principale | Flutter 3.38+, Dart 3.10+ |
| State management | Riverpod 3.x |
| DB locale | Isar (community fork) |
| Prefs | Hive 2.x |
| Video | media_kit (kodjodevf fork) |
| Navigation | GoRouter 17.x |
| Extensions JS | QuickJS (via ffi) |
| Réseau | Dart http 1.x + shelf |
| Rust | flutter_rust_bridge 2.x |
| Go | torrent (Aria2 + streaming) |
| Serveur headless | Node.js 20 + Express + QuickJS VM |
| CI | GitHub Actions |
| Docs | VitePress + Vercel |

---

## Architecture — repo `watchtower-real` (UI Reel/TikTok)

```
watchtower-real/app/watchtower-real/lib/
├── main.dart              ← MediaKit.ensureInitialized() + Hive + Riverpod
├── app.dart               ← ReelApp (MaterialApp.router)
├── shell.dart             ← Export public : ReelShell (entry pour watchtower)
├── router/router.dart     ← GoRouter
├── core/theme/            ← tokens, thème dark
├── remote/                ← RemoteApiClient HTTP → serveur watchtower
└── features/feed/
    ├── feed_screen.dart   ← PageView + pool de Players media_kit
    ├── providers/feed_provider.dart
    ├── models/feed_item.dart
    └── widgets/           ← feed_page, feed_header, feed_sidebar, feed_overlay_bottom
```

Keystore APK : alias `reel`, passwords `reelwatchtower`. Secrets CI requis : `KEYSTORE_BASE64`, `KEY_PASSWORD`, `STORE_PASSWORD`.

---

## Déploiement rapide — Docker

```bash
git clone https://github.com/ferelking242/watchtower.git
cd watchtower/server
cp .env.example .env   # remplis API_KEY
docker compose up -d
curl http://localhost:8080/api/ping  # → {"status":"ok","version":"0.1.0"}
```

One-click : Railway, Render, Google Colab (boutons dans le README).