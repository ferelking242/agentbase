# Règles — WATCHTOWER

## Règle 1 : Clone par nom
Avant tout travail, cloner les repos qui correspondent à la room par leur nom exact.

```bash
git clone https://<GITHUB_PAT>@github.com/ferelking242/watchtower.git
git clone https://<GITHUB_PAT>@github.com/ferelking242/watchtower-real.git
git clone https://<GITHUB_PAT>@github.com/ferelking242/watchtower-website.git

cd watchtower       && git config user.email "agent@replit.com" && git config user.name "Replit Agent" && cd ..
cd watchtower-real  && git config user.email "agent@replit.com" && git config user.name "Replit Agent" && cd ..
cd watchtower-website && git config user.email "agent@replit.com" && git config user.name "Replit Agent" && cd ..
```

## Règle 2 : Code proprement
- Commits atomiques : un changement logique = un commit avec un message clair.
- Respecter l'architecture existante : `lib/modules/`, `lib/eval/`, `lib/remote/`, `lib/services/`, `server/`.
- `flutter analyze` doit passer à **0 erreur** avant chaque push.
- Pas de code mort, pas de TODO flottant sans contexte.
- Les extensions JS restent dans `watchtower-extensions` — ne jamais les écrire directement dans l'app.
- Ne jamais casser l'API REST du serveur headless (`server/`) sans mettre à jour les clients.

## Règle 3 : Push le contenu, pas le dossier
- Déposer les fichiers **directement à leur place** dans le repo — ne pas créer de sous-dossier superflu.
- Ne jamais committer : `attached_assets/`, `.env`, secrets en clair, tokens, clés API.
- Si un fichier contient un PAT ou une clé → le push sera bloqué par GitHub. Supprimer le fichier du commit avant de pusher.
- Utiliser `git rm --cached <fichier>` pour retirer un fichier du staging sans le supprimer localement.