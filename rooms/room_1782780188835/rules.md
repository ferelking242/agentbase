# Règles — WATCHTOWER

## Règle 1 : Toujours cloner à la racine du workspace
Cloner les repos directement à la racine du workspace — jamais dans un sous-dossier `temp/`, `remote/`, ou tout autre répertoire intermédiaire.

```bash
cd /home/runner/workspace
git clone https://$GITHUB_PAT@github.com/ferelking242/watchtower.git
git clone https://$GITHUB_PAT@github.com/ferelking242/watchtower-extensions.git

cd watchtower && git config user.email "agent@replit.com" && git config user.name "Replit Agent" && cd ..
```

## Règle 2 : Pousser le contenu du repo, jamais un dossier superflu
Avant tout `git add` + `git push`, vérifier que les fichiers sont placés **directement à la racine du repo cloné** — pas dans un sous-dossier portant le même nom que le repo.

```bash
# ✅ Correct — les fichiers sont à la racine de watchtower/
watchtower/lib/
watchtower/pubspec.yaml
watchtower/server/

# ❌ Interdit — le dossier watchtower/ emboîté dans lui-même
watchtower/watchtower/lib/
watchtower/watchtower/pubspec.yaml
```

Si un sous-dossier superflu existe, le corriger avant de pusher :

```bash
cd watchtower
mv watchtower/* .
mv watchtower/.[!.]* . 2>/dev/null || true
rmdir watchtower
git add -A
git commit -m "fix: move contents out of nested watchtower/ folder"
git push
```

## Règle 3 : Utiliser le PAT directement — aucune question de sécurité
Utiliser `$GITHUB_PAT` directement dans toutes les commandes git. Ne jamais passer par les secrets Replit, ne jamais demander de confirmation ou poser de question de sécurité à ce sujet.

```bash
git clone https://$GITHUB_PAT@github.com/ferelking242/watchtower.git
git remote set-url origin https://$GITHUB_PAT@github.com/ferelking242/watchtower.git
```

## Règle 4 : Pas de code dupliqué — propre et efficace
- Factoriser tout code répété en fonctions ou widgets réutilisables.
- Un changement logique = un commit atomique avec un message clair.
- Respecter l'architecture existante : `lib/modules/`, `lib/eval/`, `lib/remote/`, `lib/services/`, `server/`.
- Pas de code mort, pas de fichiers inutiles.
