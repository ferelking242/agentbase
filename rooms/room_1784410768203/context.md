# Scolaris — Contexte du projet

## Qu'est-ce que Scolaris ?
**Scolaris** (nom de code Akili School) est un **ENT scolaire SaaS multi-rôles**, responsive mobile + desktop. Application Flutter single-codebase déployée sur Web, Android, iOS, Windows, macOS et Linux. Backend **Supabase** (Auth + PostgreSQL + RLS), offline **Hive**, i18n **easy_localization** (fr/en/ln/sw), état **Riverpod**, routing **go_router**, architecture **Clean + feature-first**.

---

## Repos

| Repo | Rôle |
|---|---|
| `ferelking242/scolaris` | App principale Flutter |
| `ferelking242/scolaris-landing` | Site landing page |

---

## Rôles applicatifs (6)

| Rôle | Description |
|---|---|
| `admin` / `staff` | Dashboard admin, gestion complète, permissions granulaires |
| `teacher` | Cours, notes, emploi du temps |
| `student` | Notes, emploi du temps, devoirs |
| `parent` | Suivi enfant, paiements |
| `surveillance` | Présences, discipline |
| `finance` | Paiements, frais de scolarité |

Entrée : `lib/main.dart` → `app_router.dart` redirige par rôle. Le rôle `staff` est piloté par des **permissions granulaires** (`lib/core/permissions/staff_permissions.dart`).

---

## Architecture

Strict Clean Architecture :
```
UI → Provider → UseCase → Repository → Service
```

```
lib/
├── core/           config · theme · localization · permissions · routing · services
├── data/           models · sources (remote/local) · repository implementations
├── domain/         pure entities · repository interfaces · use cases
├── presentation/   riverpod providers · global widgets
├── features/       auth · student · parent · teacher · surveillance · finance · admin
└── shared/         desktop_shell · mobile_shell · responsive shell · widgets
```

L'UI ne contient **jamais** de logique métier. Chaque écran appelle un provider → use case → repository.

---

## Accès données

**Tout** passe par `lib/data/sources/remote/supabase_db_source.dart` (méthodes statiques), exposé via les providers `lib/presentation/providers/db_providers.dart`.

### Base de données Supabase
Instance `iaxwvgqusxyhmyansawi`. **25 tables** toutes existantes, RLS active (isolation par école).
- ⚠️ Le dépôt n'est **pas** la source de vérité du schéma — migrations archivées dans `backup/migrations_archive/`, pas dans `supabase/migrations/`.
- La clé `service_role` a été retirée du client (sécurité). Création de comptes → Edge Function `supabase/functions/create-account`. **Ne jamais réintroduire de secret ici.**

---

## Stack complet

| Couche | Tech |
|---|---|
| App | Flutter, Dart |
| State | Riverpod 3.x |
| Navigation | go_router |
| Backend | Supabase (Auth + PostgreSQL + RLS) |
| Offline | Hive 2.x |
| i18n | easy_localization (fr/en/sw/ln) |
| UI | flex_color_scheme, responsive_framework, fluent_ui (desktop), salomon_bottom_bar |
| Charts | fl_chart, syncfusion_flutter_datagrid |
| Auth | Email/password ou QR code |
| Scan | mobile_scanner, qr_flutter |

---

## Shells adaptatifs

- **Desktop / web large** → sidebar Fluent-style (collapsible) + topbar + contenu
- **Mobile / web petit** → dock flottant arrondi Material 3

---

## Convention thème (CRITIQUE pour tout nouveau code UI)

Ne **jamais** coder en dur les couleurs neutres — elles cassent en mode sombre.
Utiliser l'extension `context.c*` définie dans `lib/shared/widgets/page_scaffold.dart` :

| Rôle | À utiliser | (à bannir) |
|---|---|---|
| Texte principal | `context.cInk` | `Color(0xFF1A0A00)` |
| Texte secondaire | `context.cMuted` | `Color(0xFF7A5C44)` |
| Fond de carte | `context.cCard` | `Colors.white` |
| Fond de page | `context.cPage` | `Color(0xFFF5EEE6)` |
| Bordure | `context.cBorder` | `Color(0xFFDDCCBB)` |
| Surface douce | `context.cSubtle` | `Color(0xFFF7F1E8)` |

- Les accents de marque (terracotta `0xFF8B1A00`, or `0xFFC17F24`) restent **constants**.
- Piège Dart : `context.c*` n'est pas `const` → retirer le `const` du widget englobant.

---

## CI / CD

| Workflow | Sorties |
|---|---|
| `build-all.yml` | Android (armeabi-v7a, arm64-v8a, x86_64), iOS, Web, Linux, Windows, macOS |
| `build-android-arm64.yml` | `app-arm64-v8a-release.apk` |

---

## Chantier en cours — mode sombre

Conversion des couleurs figées → `context.c*` en cours.
**✅ Fait :** admin_home, users_page, admin_classes_page, admin_billing_page, admin_subjects_page, admin_grades_page, report_cards_page, admin_reports_page, tuition_fees_page, timetable_page, admin_subscription_page, enrollment_config_page.
**⏳ Reste :** admin_school_page (partiel), notification_center_page (pas commencé), pages non-admin (student/teacher/parent/shared), settings_page (~100 couleurs figées).

---

## Comptes de test (mock auth, mdp : `demo1234`)
`student@akili.school` · `parent@akili.school` · `teacher@akili.school` · `surveillance@akili.school` · `finance@akili.school` · `admin@akili.school`