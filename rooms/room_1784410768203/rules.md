# Règles — SCOLARIS

## Règle 1 : Clone par nom
Avant tout travail, cloner les repos correspondant à la room.

```bash
git clone https://<GITHUB_PAT>@github.com/ferelking242/scolaris.git
git clone https://<GITHUB_PAT>@github.com/ferelking242/scolaris-landing.git

cd scolaris         && git config user.email "agent@replit.com" && git config user.name "Replit Agent" && cd ..
cd scolaris-landing && git config user.email "agent@replit.com" && git config user.name "Replit Agent" && cd ..
```

## Règle 2 : Code proprement
- Respecter l'architecture Clean : UI → Provider → UseCase → Repository → Service. L'UI ne contient jamais de logique métier.
- Toujours utiliser `context.cInk`, `context.cCard`, `context.cBorder`, etc. — jamais de couleur neutre codée en dur.
- `flutter analyze` doit passer à **0 erreur** avant chaque push.
- Ne jamais réintroduire la clé `service_role` Supabase dans le client. Création de comptes → Edge Function uniquement.
- Commits atomiques et clairs.

## Règle 3 : Push le contenu, pas le dossier
- Pousser les fichiers **directement à leur place** dans le repo — ne pas créer de sous-dossier superflu.
- Ne jamais committer : `.env`, secrets, clés API, tokens, `attached_assets/`.
- Si un fichier contient un secret → le retirer du staging (`git rm --cached`) avant de pusher.