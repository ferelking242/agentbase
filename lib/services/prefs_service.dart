import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/saved_prompt.dart';

// ── Prompt Template ───────────────────────────────────────────────────────────
class PromptTemplate {
  final String id, name, content, category;
  final DateTime createdAt;

  const PromptTemplate({
    required this.id,
    required this.name,
    required this.content,
    this.category = 'Général',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'content': content,
    'category': category, 'createdAt': createdAt.toIso8601String(),
  };

  factory PromptTemplate.fromJson(Map<String, dynamic> j) => PromptTemplate(
    id: j['id'] as String,
    name: j['name'] as String,
    content: j['content'] as String,
    category: j['category'] as String? ?? 'Général',
    createdAt: DateTime.parse(j['createdAt'] as String),
  );
}

class PrefsService {
  static const _kPat           = 'gh_pat';
  static const _kPrompts       = 'saved_prompts';
  static const _kNextNumber    = 'prompt_next_number';
  static const _kTemplates     = 'prompt_templates';
  static const _kFavorites     = 'prompt_favorites';
  static const _kContentCache  = 'prompt_content_cache';
  static const _kThemeMode     = 'theme_mode';
  static const _kOwner         = 'gh_owner';
  static const _kRepo          = 'gh_repo';
  static const _kDataRepo      = 'gh_data_repo';   // repo séparé pour les données
  static const _kAutoSync      = 'auto_sync_enabled';
  static const _kPinnedRooms   = 'pinned_rooms';
  static const _kOnboarding    = 'onboarding_seen';

  // ── PAT ──────────────────────────────────────────────────────────────────
  static Future<String?> getPat() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kPat);
  }
  static Future<void> savePat(String pat) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPat, pat);
  }
  static Future<void> clearPat() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kPat);
  }

  // ── Generic string key-value ──────────────────────────────────────────────
  static Future<String?> getString(String key) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(key);
  }
  static Future<void> setString(String key, String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, value);
  }

  // ── Repository config ─────────────────────────────────────────────────────
  static Future<String> getOwner() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kOwner) ?? 'ferelking242';
  }
  static Future<String> getRepo() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kRepo) ?? 'agentbase';
  }
  /// Repo séparé pour les données (prompts, rooms, openspace…).
  /// Si vide, utilise [getRepo] comme avant.
  static Future<String> getDataRepo() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kDataRepo) ?? '';
  }
  static Future<void> setOwner(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kOwner, v);
  }
  static Future<void> setRepo(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kRepo, v);
  }
  static Future<void> setDataRepo(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDataRepo, v);
  }

  // ── Theme ─────────────────────────────────────────────────────────────────
  static Future<String> getThemeMode() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kThemeMode) ?? 'dark';
  }
  static Future<void> setThemeMode(String mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kThemeMode, mode);
  }

  // ── Auto-sync ─────────────────────────────────────────────────────────────
  static Future<bool> getAutoSync() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAutoSync) ?? false;
  }
  static Future<void> setAutoSync(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoSync, v);
  }

  // ── Next sequential number ────────────────────────────────────────────────
  static Future<int> _nextNumber() async {
    final p = await SharedPreferences.getInstance();
    final n = p.getInt(_kNextNumber) ?? 1;
    await p.setInt(_kNextNumber, n + 1);
    return n;
  }

  // ── Prompts ───────────────────────────────────────────────────────────────
  static Future<List<SavedPrompt>> getPrompts() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kPrompts);
    if (raw == null) return [];
    return SavedPrompt.listFromJson(raw);
  }
  static Future<SavedPrompt> addPrompt(SavedPrompt prompt) async {
    final p = await SharedPreferences.getInstance();
    int num = prompt.number;
    if (num == 0) num = await _nextNumber();
    final numbered = SavedPrompt(
      id: prompt.id, name: prompt.name, link: prompt.link,
      created: prompt.created, number: num,
      tags: prompt.tags, isFavorite: prompt.isFavorite,
    );
    final existing = await getPrompts();
    existing.insert(0, numbered);
    await p.setString(_kPrompts, SavedPrompt.listToJson(existing));
    return numbered;
  }
  static Future<void> deletePrompt(String id) async {
    final p = await SharedPreferences.getInstance();
    final existing = await getPrompts();
    existing.removeWhere((pr) => pr.id == id);
    await p.setString(_kPrompts, SavedPrompt.listToJson(existing));
    // Also remove cache entry
    final cacheRaw = p.getString(_kContentCache);
    if (cacheRaw != null) {
      final cache = Map<String, dynamic>.from(jsonDecode(cacheRaw) as Map);
      cache.remove(id);
      await p.setString(_kContentCache, jsonEncode(cache));
    }
  }
  static Future<void> updatePromptName(String id, String newName) async {
    final p = await SharedPreferences.getInstance();
    final prompts = await getPrompts();
    final idx = prompts.indexWhere((pr) => pr.id == id);
    if (idx == -1) return;
    prompts[idx] = prompts[idx].copyWith(name: newName);
    await p.setString(_kPrompts, SavedPrompt.listToJson(prompts));
  }
  static Future<void> replaceAll(List<SavedPrompt> prompts) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrompts, SavedPrompt.listToJson(prompts));
  }

  // ── Tags ──────────────────────────────────────────────────────────────────
  static Future<void> setPromptTags(String id, List<String> tags) async {
    final p = await SharedPreferences.getInstance();
    final prompts = await getPrompts();
    final idx = prompts.indexWhere((pr) => pr.id == id);
    if (idx == -1) return;
    prompts[idx] = prompts[idx].copyWith(tags: tags);
    await p.setString(_kPrompts, SavedPrompt.listToJson(prompts));
  }

  // ── Favorites ─────────────────────────────────────────────────────────────
  static Future<Set<String>> getFavorites() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kFavorites);
    if (raw == null) return {};
    try {
      return Set<String>.from(jsonDecode(raw) as List);
    } catch (_) { return {}; }
  }
  static Future<bool> toggleFavorite(String id) async {
    final p = await SharedPreferences.getInstance();
    final favs = await getFavorites();
    final isNowFav = !favs.contains(id);
    if (isNowFav) favs.add(id); else favs.remove(id);
    await p.setString(_kFavorites, jsonEncode(favs.toList()));
    // Also update the prompt model
    final prompts = await getPrompts();
    final idx = prompts.indexWhere((pr) => pr.id == id);
    if (idx != -1) {
      prompts[idx] = prompts[idx].copyWith(isFavorite: isNowFav);
      await p.setString(_kPrompts, SavedPrompt.listToJson(prompts));
    }
    return isNowFav;
  }

  // ── Content cache (offline) ───────────────────────────────────────────────
  static Future<String?> getCachedContent(String id) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kContentCache);
    if (raw == null) return null;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return map[id] as String?;
    } catch (_) { return null; }
  }
  static Future<void> setCachedContent(String id, String content) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kContentCache);
    final map = <String, dynamic>{};
    if (raw != null) {
      try { map.addAll(Map<String, dynamic>.from(jsonDecode(raw) as Map)); } catch (_) {}
    }
    map[id] = content;
    // Keep max 100 entries
    if (map.length > 100) {
      final keys = map.keys.toList();
      for (final k in keys.take(map.length - 100)) map.remove(k);
    }
    await p.setString(_kContentCache, jsonEncode(map));
  }
  static Future<void> clearContentCache() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kContentCache);
  }

  // ── Templates ─────────────────────────────────────────────────────────────
  static Future<List<PromptTemplate>> getTemplates() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kTemplates);
    if (raw == null) return _defaultTemplates();
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => PromptTemplate.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) { return _defaultTemplates(); }
  }
  static Future<void> saveTemplates(List<PromptTemplate> templates) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kTemplates, jsonEncode(templates.map((t) => t.toJson()).toList()));
  }
  static Future<PromptTemplate> addTemplate(String name, String content, {String category = 'Général'}) async {
    final templates = await getTemplates();
    final t = PromptTemplate(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name, content: content, category: category,
      createdAt: DateTime.now(),
    );
    templates.insert(0, t);
    await saveTemplates(templates);
    return t;
  }
  static Future<void> deleteTemplate(String id) async {
    final templates = await getTemplates();
    templates.removeWhere((t) => t.id == id);
    await saveTemplates(templates);
  }
  static Future<void> updateTemplate(String id, {String? name, String? content, String? category}) async {
    final templates = await getTemplates();
    final idx = templates.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final old = templates[idx];
    templates[idx] = PromptTemplate(
      id: old.id,
      name: name ?? old.name,
      content: content ?? old.content,
      category: category ?? old.category,
      createdAt: old.createdAt,
    );
    await saveTemplates(templates);
  }

  // ── Onboarding ────────────────────────────────────────────────────────────
  static Future<bool> isOnboardingSeen() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kOnboarding) ?? false;
  }
  static Future<void> setOnboardingSeen(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOnboarding, v);
  }

  // ── Pinned rooms ──────────────────────────────────────────────────────────
  static Future<Set<String>> getPinnedRooms() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kPinnedRooms);
    if (raw == null) return {};
    try { return Set<String>.from(jsonDecode(raw) as List); } catch (_) { return {}; }
  }
  static Future<bool> togglePinRoom(String id) async {
    final p = await SharedPreferences.getInstance();
    final pins = await getPinnedRooms();
    final isNowPinned = !pins.contains(id);
    if (isNowPinned) pins.add(id); else pins.remove(id);
    await p.setString(_kPinnedRooms, jsonEncode(pins.toList()));
    return isNowPinned;
  }

  // ── Archive prompt ────────────────────────────────────────────────────────
  static Future<void> archivePrompt(String id) async {
    final p = await SharedPreferences.getInstance();
    final prompts = await getPrompts();
    final idx = prompts.indexWhere((pr) => pr.id == id);
    if (idx == -1) return;
    prompts[idx] = prompts[idx].copyWith(isArchived: true);
    await p.setString(_kPrompts, SavedPrompt.listToJson(prompts));
  }
  static Future<void> unarchivePrompt(String id) async {
    final p = await SharedPreferences.getInstance();
    final prompts = await getPrompts();
    final idx = prompts.indexWhere((pr) => pr.id == id);
    if (idx == -1) return;
    prompts[idx] = prompts[idx].copyWith(isArchived: false);
    await p.setString(_kPrompts, SavedPrompt.listToJson(prompts));
  }

  static List<PromptTemplate> _defaultTemplates() => [
    PromptTemplate(
      id: 'tpl_bug',
      name: 'Bug Report',
      category: 'Dev',
      content: '''**Problème :** 

**Étapes pour reproduire :**
1. 
2. 
3. 

**Comportement attendu :** 

**Comportement actuel :** 

**Environnement :** 
- OS: 
- Version: 
- Device:''',
      createdAt: DateTime(2024, 1, 1),
    ),
    PromptTemplate(
      id: 'tpl_feature',
      name: 'Feature Request',
      category: 'Dev',
      content: '''**Feature demandée :** 

**Contexte / Motivation :** 

**Comportement souhaité :** 

**Critères d\'acceptation :**
- [ ] 
- [ ] 

**Priorité :** 🔴 Haute / 🟡 Moyenne / 🟢 Basse''',
      createdAt: DateTime(2024, 1, 1),
    ),
    PromptTemplate(
      id: 'tpl_analyse',
      name: 'Analyse de code',
      category: 'Dev',
      content: '''Analyse ce code et dis-moi :
1. Les problèmes de performance
2. Les failles de sécurité potentielles
3. Les améliorations possibles
4. La qualité globale (1-10)

```
[COLLER LE CODE ICI]
```''',
      createdAt: DateTime(2024, 1, 1),
    ),
    PromptTemplate(
      id: 'tpl_task',
      name: 'Tâche agent',
      category: 'Général',
      content: '''**Objectif :** 

**Contexte :** 

**Contraintes :**
- 
- 

**Livrable attendu :** 

**Deadline :**''',
      createdAt: DateTime(2024, 1, 1),
    ),
  ];
}
