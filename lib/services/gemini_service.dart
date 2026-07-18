import 'dart:convert';
import 'package:http/http.dart' as http;
import 'prefs_service.dart';

class GeminiApiResult {
  final String text;
  final bool success;
  final String? error;
  GeminiApiResult({required this.text, required this.success, this.error});
}

/// Manages multiple Gemini API keys with automatic rotation when quota is exhausted.
class GeminiService {
  static const String _kKeys = 'gemini_api_keys';
  static const String _kCurrentIndex = 'gemini_current_key_idx';
  static const String _kExhaustedUntil = 'gemini_exhausted_until';

  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  static final GeminiService _instance = GeminiService._();
  GeminiService._();
  factory GeminiService() => _instance;

  List<String> _keys = [];
  int _currentIndex = 0;
  Map<int, DateTime> _exhaustedUntil = {};
  bool _initialized = false;

  Future<void> init() async {
    _keys = await getKeys();
    final s = await PrefsService.getString(_kCurrentIndex);
    _currentIndex = int.tryParse(s ?? '0') ?? 0;
    _exhaustedUntil = await _loadExhaustedUntil();
    _initialized = true;
  }

  static Future<List<String>> getKeys() async {
    final raw = await PrefsService.getString(_kKeys);
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveKeys(List<String> keys) async {
    await PrefsService.setString(_kKeys, jsonEncode(keys));
  }

  Future<Map<int, DateTime>> _loadExhaustedUntil() async {
    final raw = await PrefsService.getString(_kExhaustedUntil);
    if (raw == null) return {};
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return map.map((k, v) => MapEntry(int.parse(k), DateTime.parse(v as String)));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveExhaustedUntil() async {
    final map = _exhaustedUntil.map((k, v) => MapEntry(k.toString(), v.toIso8601String()));
    await PrefsService.setString(_kExhaustedUntil, jsonEncode(map));
  }

  Future<void> _markExhausted(int idx) async {
    // Quota resets after 24h (daily limit) or 1 min (per-minute limit)
    // We use 1h as a safe middle ground to avoid blocking too long
    _exhaustedUntil[idx] = DateTime.now().add(const Duration(hours: 1));
    await _saveExhaustedUntil();
  }

  String? _getAvailableKey() {
    if (_keys.isEmpty) return null;
    final now = DateTime.now();
    // Remove expired exhaustions
    _exhaustedUntil.removeWhere((_, v) => v.isBefore(now));
    // Try from current index
    for (int i = 0; i < _keys.length; i++) {
      final idx = (_currentIndex + i) % _keys.length;
      if (!_exhaustedUntil.containsKey(idx) && _keys[idx].trim().isNotEmpty) {
        _currentIndex = idx;
        PrefsService.setString(_kCurrentIndex, '$idx');
        return _keys[idx].trim();
      }
    }
    return null;
  }

  Future<GeminiApiResult> _callGemini(
      String key, List<Map<String, dynamic>> contents) async {
    try {
      final url = Uri.parse('$_baseUrl?key=$key');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'contents': contents}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 429) {
        final idx = _keys.indexWhere((k) => k.trim() == key);
        if (idx != -1) await _markExhausted(idx);
        return GeminiApiResult(
            text: '', success: false, error: 'quota_exceeded');
      }
      if (response.statusCode != 200) {
        return GeminiApiResult(
            text: '', success: false, error: 'HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        return GeminiApiResult(
            text: '', success: false, error: 'Aucune réponse Gemini');
      }
      final content = candidates[0]['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>?;
      final text =
          parts?.firstWhere((p) => p['text'] != null, orElse: () => {'text': ''})['text'] as String? ?? '';
      return GeminiApiResult(text: text.trim(), success: true);
    } catch (e) {
      return GeminiApiResult(text: '', success: false, error: e.toString());
    }
  }

  Future<GeminiApiResult> generate(List<Map<String, dynamic>> contents) async {
    if (!_initialized) await init();
    for (int attempt = 0; attempt <= _keys.length; attempt++) {
      final key = _getAvailableKey();
      if (key == null) {
        return GeminiApiResult(
          text: '',
          success: false,
          error:
              'Aucune clé Gemini disponible. Configure tes clés dans Paramètres.',
        );
      }
      final result = await _callGemini(key, contents);
      if (result.success) return result;
      if (result.error == 'quota_exceeded') continue;
      return result;
    }
    return GeminiApiResult(
      text: '',
      success: false,
      error: 'Toutes les clés Gemini sont épuisées. Réessaie plus tard.',
    );
  }

  /// Améliore un prompt et retourne le texte amélioré.
  Future<GeminiApiResult> improvePrompt(
    String promptText, {
    String? roomContext,
    String? roomName,
  }) async {
    final ctx = roomContext != null && roomContext.isNotEmpty
        ? 'Contexte de la room "${roomName ?? "Room"}":\n$roomContext\n\n'
        : '';
    final systemPrompt =
        '${ctx}Tu es un expert en prompts pour agents IA. '
        'Améliore le prompt suivant pour le rendre plus clair, structuré et efficace. '
        'Garde le sens original. Réponds UNIQUEMENT avec le prompt amélioré, sans explication ni préambule.';

    return generate([
      {
        'role': 'user',
        'parts': [
          {'text': systemPrompt},
          {'text': '\nPrompt à améliorer:\n$promptText'},
        ],
      },
    ]);
  }

  /// Génère un nom/titre court pour un prompt.
  Future<GeminiApiResult> suggestName(
    String promptText, {
    String? roomContext,
    String? roomName,
  }) async {
    final ctx = roomContext != null && roomContext.isNotEmpty
        ? 'Contexte: ${roomName ?? "Room"} — ${roomContext.substring(0, roomContext.length.clamp(0, 200))}\n'
        : '';
    final prompt =
        '${ctx}Génère un titre court et précis (max 55 caractères) pour ce prompt. '
        'Le titre doit être descriptif, professionnel, en français si le prompt est en français. '
        'Réponds UNIQUEMENT avec le titre, sans guillemets, sans ponctuation finale.\n\n'
        'Prompt: $promptText';

    return generate([
      {
        'role': 'user',
        'parts': [{'text': prompt}],
      },
    ]);
  }

  /// Chat conversationnel avec Gemini.
  Future<GeminiApiResult> chat(List<Map<String, String>> messages) async {
    final contents = messages.map((m) {
      final role = m['role'] == 'user' ? 'user' : 'model';
      return {
        'role': role,
        'parts': [
          {'text': m['content'] ?? ''}
        ],
      };
    }).toList();
    return generate(contents);
  }

  bool get hasKeys => _keys.isNotEmpty;

  String get statusText {
    if (_keys.isEmpty) return 'Aucune clé configurée';
    final now = DateTime.now();
    final available = _keys
        .asMap()
        .entries
        .where((e) =>
            !_exhaustedUntil.containsKey(e.key) ||
            _exhaustedUntil[e.key]!.isBefore(now))
        .length;
    final total = _keys.length;
    return '$available/$total clé${total > 1 ? 's' : ''} disponible${available != 1 ? 's' : ''}';
  }

  /// Retourne l'heure de réactivation de la prochaine clé épuisée (ou null si aucune).
  DateTime? get nextAvailableAt {
    if (_exhaustedUntil.isEmpty) return null;
    final times = _exhaustedUntil.values.toList()..sort();
    return times.first;
  }
}
