import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
  });

  AppNotification copyWith({bool? read}) => AppNotification(
    id: id, title: title, body: body, createdAt: createdAt,
    read: read ?? this.read,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'body': body,
    'createdAt': createdAt.toIso8601String(), 'read': read,
  };

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: j['id'] as String,
    title: j['title'] as String,
    body: j['body'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    read: j['read'] as bool? ?? false,
  );
}

class NotificationService {
  static const _prefsKey  = 'agentbase_notifications';
  static const _maxStored = 80;

  static Future<List<AppNotification>> getAll() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_prefsKey) ?? [];
    final result = <AppNotification>[];
    for (final s in raw) {
      try { result.add(AppNotification.fromJson(jsonDecode(s) as Map<String, dynamic>)); } catch (_) {}
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  static Future<void> add(AppNotification n) async {
    final p = await SharedPreferences.getInstance();
    final existing = p.getStringList(_prefsKey) ?? [];
    existing.insert(0, jsonEncode(n.toJson()));
    if (existing.length > _maxStored) existing.removeRange(_maxStored, existing.length);
    await p.setStringList(_prefsKey, existing);
  }

  static Future<void> markRead(String id) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_prefsKey) ?? [];
    final updated = raw.map((s) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        if (m['id'] == id) m['read'] = true;
        return jsonEncode(m);
      } catch (_) { return s; }
    }).toList();
    await p.setStringList(_prefsKey, updated);
  }

  static Future<void> markAllRead() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_prefsKey) ?? [];
    final updated = raw.map((s) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        m['read'] = true;
        return jsonEncode(m);
      } catch (_) { return s; }
    }).toList();
    await p.setStringList(_prefsKey, updated);
  }

  static Future<void> delete(String id) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_prefsKey) ?? [];
    final updated = raw.where((s) {
      try { return (jsonDecode(s) as Map<String, dynamic>)['id'] != id; }
      catch (_) { return true; }
    }).toList();
    await p.setStringList(_prefsKey, updated);
  }

  static Future<void> clearAll() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_prefsKey);
  }

  static Future<int> unreadCount() async {
    final all = await getAll();
    return all.where((n) => !n.read).length;
  }

  static Future<void> notifyPromptSaved({
    required String promptName,
    required String link,
  }) async {
    await add(AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Prompt sauvegardé ✅',
      body: promptName,
      createdAt: DateTime.now(),
    ));
  }

  static Future<void> notifyAgentDone({
    required String message,
    String? link,
  }) async {
    await add(AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Agent terminé 🤖',
      body: message,
      createdAt: DateTime.now(),
    ));
  }

  static Future<void> notifyInfo({
    required String title,
    required String body,
  }) async {
    await add(AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      body: body,
      createdAt: DateTime.now(),
    ));
  }
}
