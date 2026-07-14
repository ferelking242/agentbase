import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/room.dart';
import '../models/prompt.dart';
import '../models/message.dart';
import '../models/saved_prompt.dart';
import '../services/prefs_service.dart';

/// Generates a unique prompt ID: 13-digit timestamp + 6 random hex chars.
/// Avoids collisions across devices even at the same millisecond.
String generatePromptId() {
  final ts  = DateTime.now().millisecondsSinceEpoch;
  final rng = Random.secure();
  final hex = List.generate(6, (_) => rng.nextInt(16).toRadixString(16)).join();
  return '${ts}_$hex';
}

class AttachedFile {
  final String name;
  final Uint8List bytes;
  final bool isImage;
  AttachedFile({required this.name, required this.bytes, required this.isImage});
}

class TranscriptEntry {
  final String id, agentName, userRequest, actionsDone;
  final DateTime createdAt;
  TranscriptEntry({
    required this.id,
    required this.agentName,
    required this.userRequest,
    required this.actionsDone,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  static TranscriptEntry fromMarkdown(String content, String filename) {
    String agentName = 'Agent', userRequest = '', actionsDone = '', id = '';
    DateTime? createdAt;
    final lines = content.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.startsWith('**Agent:**')) agentName = l.replaceFirst('**Agent:**', '').trim();
      else if (l.startsWith('**Created:**')) {
        try { createdAt = DateTime.parse(l.replaceFirst('**Created:**', '').trim()); } catch (_) {}
      } else if (l.startsWith('**ID:**')) id = l.replaceFirst('**ID:**', '').trim();
      else if (l.trim() == '### Demande utilisateur') {
        final buf = StringBuffer(); i++;
        while (i < lines.length && !lines[i].startsWith('###')) { buf.writeln(lines[i]); i++; }
        userRequest = buf.toString().trim(); i--;
      } else if (l.trim() == '### Actions effectuées') {
        final buf = StringBuffer(); i++;
        while (i < lines.length && !lines[i].startsWith('###')) { buf.writeln(lines[i]); i++; }
        actionsDone = buf.toString().trim(); i--;
      }
    }
    final tsM = RegExp(r'\d{13}').firstMatch(filename);
    if (id.isEmpty) id = tsM?.group(0) ?? filename;
    if (createdAt == null && tsM != null) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(int.parse(tsM.group(0)!));
    }
    return TranscriptEntry(id: id, agentName: agentName, userRequest: userRequest,
        actionsDone: actionsDone, createdAt: createdAt);
  }

  String toMarkdown() {
    final buf = StringBuffer();
    buf.writeln('## Transcription — $agentName');
    buf.writeln();
    buf.writeln('**ID:** $id');
    buf.writeln('**Agent:** $agentName');
    buf.writeln('**Created:** ${createdAt.toIso8601String()}');
    buf.writeln();
    buf.writeln('### Demande utilisateur');
    buf.writeln();
    buf.writeln(userRequest.isNotEmpty ? userRequest : '_(non renseigné)_');
    buf.writeln();
    buf.writeln('### Actions effectuées');
    buf.writeln();
    buf.writeln(actionsDone.isNotEmpty ? actionsDone : '_(non renseigné)_');
    return buf.toString();
  }
}

// ── Clipboard model ──────────────────────────────────────────────────────────
class ClipboardEntry {
  final String id;
  final String content;
  final DateTime createdAt;
  ClipboardEntry({required this.id, required this.content, required this.createdAt});
  factory ClipboardEntry.fromJson(Map<String, dynamic> j) => ClipboardEntry(
    id: j['id'] as String,
    content: j['content'] as String,
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
  Map<String, dynamic> toJson() => {'id': id, 'content': content, 'createdAt': createdAt.toIso8601String()};
}

class GitHubService {
  final String owner, repo;
  /// Repo de données séparé. Quand non vide, toutes les lectures/écritures
  /// passent par ce repo au lieu de [repo]. Permet de garder le repo de code
  /// (avec CI) propre des commits de données.
  String _dataRepo = '';

  String _pat = '';
  final http.Client _client;
  GitHubService({this.owner = 'ferelking242', this.repo = 'agentbase', http.Client? client})
      : _client = client ?? http.Client();

  bool get hasPat => _pat.isNotEmpty;
  void setPat(String p) => _pat = p;

  /// Définit le repo de données. Passer une chaîne vide pour revenir au repo de code.
  void setDataRepo(String r) => _dataRepo = r.trim();
  String get dataRepo => _dataRepo;

  Future<bool> init() async {
    final p  = await PrefsService.getPat();
    final dr = await PrefsService.getDataRepo();
    if (p != null && p.isNotEmpty) { _pat = p; }
    _dataRepo = dr;
    return _pat.isNotEmpty;
  }

  Map<String, String> get _h => {
    'Authorization': 'token $_pat',
    'Accept': 'application/vnd.github.v3+json',
    'Content-Type': 'application/json',
  };

  /// Headers to use with raw.githubusercontent.com requests (no Content-Type).
  Map<String, String> get downloadHeaders =>
      _pat.isNotEmpty ? {'Authorization': 'token $_pat'} : {};

  // Utilise le repo de données s'il est configuré, sinon le repo de code.
  String get _effectiveRepo => _dataRepo.isNotEmpty ? _dataRepo : repo;

  String get _api => 'https://api.github.com/repos/$owner/$_effectiveRepo';
  String get _raw => 'https://raw.githubusercontent.com/$owner/$_effectiveRepo/main';

  Future<bool> validatePat() async {
    try {
      final r = await _client.get(Uri.parse('$_api'), headers: _h);
      return r.statusCode == 200;
    } catch (_) { return false; }
  }

  // ── Retry helper ──────────────────────────────────────────────────────────
  Future<T> _retry<T>(Future<T> Function() fn, {int retries = 3}) async {
    for (int i = 0; i < retries; i++) {
      try {
        return await fn();
      } catch (e) {
        if (i == retries - 1) rethrow;
        await Future.delayed(Duration(milliseconds: 800 * (i + 1)));
      }
    }
    throw Exception('Max retries exceeded');
  }

  // ── Rooms ─────────────────────────────────────────────────────────────────

  Future<List<Room>> fetchRooms() async {
    for (final url in ['$_raw/api/v1/rooms.json', '$_raw/rooms.json', '$_raw/data/rooms.json']) {
      try {
        final r = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          final data = jsonDecode(r.body);
          final list = data is List ? data : (data['rooms'] as List? ?? []);
          return list.map((e) => Room.fromJson(e as Map<String, dynamic>)).toList();
        }
      } catch (_) {}
    }
    return [];
  }

  Future<Map<String, dynamic>?> _roomsFileMeta() async {
    for (final p in ['api/v1/rooms.json', 'rooms.json', 'data/rooms.json']) {
      final r = await _client.get(Uri.parse('$_api/contents/$p'), headers: _h);
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final content = utf8.decode(base64Decode((body['content'] as String).replaceAll('\n', '')));
        return {'sha': body['sha'], 'path': p, 'content': content};
      }
    }
    return null;
  }

  Future<Room> createRoom(String name, {String description = '', String color = '#6366f1',
      String? githubUrl, String? stack, List<String> linkedRepos = const []}) async {
    if (_pat.isEmpty) throw Exception('Token GitHub manquant');
    final id = 'room_${DateTime.now().millisecondsSinceEpoch}';
    final newRoom = Room(id: id, name: name, description: description, color: color,
        githubUrl: githubUrl, stack: stack, linkedRepos: linkedRepos);
    final meta = await _roomsFileMeta();
    List<dynamic> rooms = [];
    String? sha;
    String path = 'api/v1/rooms.json';
    if (meta != null) {
      sha = meta['sha'] as String;
      path = meta['path'] as String;
      final data = jsonDecode(meta['content'] as String);
      rooms = data is List ? data : (data['rooms'] as List? ?? []);
    }
    rooms.add(newRoom.toJson());
    final body = jsonEncode({
      'message': 'rooms: add $name',
      'content': base64Encode(utf8.encode(jsonEncode({'rooms': rooms}))),
      if (sha != null) 'sha': sha,
    });
    final r = await _client.put(Uri.parse('$_api/contents/$path'), headers: _h, body: body);
    if (r.statusCode != 200 && r.statusCode != 201) throw Exception('Création room échouée: ${r.statusCode}');
    return newRoom;
  }

  // ── Room detail ───────────────────────────────────────────────────────────

  Future<String?> _raw_(String path) async {
    try {
      final r = await _client.get(Uri.parse('$_raw/$path'));
      return r.statusCode == 200 ? r.body : null;
    } catch (_) { return null; }
  }

  Future<String?> fetchContext(String roomId) => _raw_('rooms/$roomId/context.md');
  Future<String?> fetchRoomFile(String roomId, String fileName) => _raw_('rooms/$roomId/$fileName');
  Future<String?> fetchRules(String roomId) => _raw_('rooms/$roomId/rules.md');
  Future<String?> fetchMemory(String roomId) => _raw_('rooms/$roomId/memory.md');

  Future<List<String>> listFiles(String roomId) async {
    try {
      final r = await _client.get(
        Uri.parse('$_api/contents/rooms/$roomId'),
        headers: _pat.isNotEmpty ? _h : {});
      if (r.statusCode != 200) return [];
      return (jsonDecode(r.body) as List<dynamic>).map((f) => f['name'] as String).toList();
    } catch (_) { return []; }
  }

  Future<String?> _fileSha(String path) async {
    try {
      final r = await _client.get(Uri.parse('$_api/contents/$path'), headers: _h);
      if (r.statusCode != 200) return null;
      return (jsonDecode(r.body) as Map<String, dynamic>)['sha'] as String?;
    } catch (_) { return null; }
  }

  Future<void> pushContext(String roomId, String content) async {
    if (_pat.isEmpty) throw Exception('No PAT');
    final path = 'rooms/$roomId/context.md';
    final sha = await _fileSha(path);
    final body = <String, dynamic>{
      'message': 'Update context.md — $roomId',
      'content': base64Encode(utf8.encode(content)),
    };
    if (sha != null) body['sha'] = sha;
    final r = await _client.put(Uri.parse('$_api/contents/$path'), headers: _h, body: jsonEncode(body));
    if (r.statusCode != 200 && r.statusCode != 201) throw Exception('Push context failed: ${r.statusCode}');
  }

  Future<void> pushRules(String roomId, String content) async {
    if (_pat.isEmpty) throw Exception('No PAT');
    final path = 'rooms/$roomId/rules.md';
    final sha = await _fileSha(path);
    final body = <String, dynamic>{
      'message': 'Update rules.md — $roomId',
      'content': base64Encode(utf8.encode(content)),
    };
    if (sha != null) body['sha'] = sha;
    final r = await _client.put(Uri.parse('$_api/contents/$path'), headers: _h, body: jsonEncode(body));
    if (r.statusCode != 200 && r.statusCode != 201) throw Exception('Push rules failed: ${r.statusCode}');
  }

  Future<void> pushMemory(String roomId, String content) async {
    if (_pat.isEmpty) throw Exception('No PAT');
    final path = 'rooms/$roomId/memory.md';
    final sha = await _fileSha(path);
    final body = <String, dynamic>{
      'message': 'Update memory.md — $roomId',
      'content': base64Encode(utf8.encode(content)),
    };
    if (sha != null) body['sha'] = sha;
    final r = await _client.put(Uri.parse('$_api/contents/$path'), headers: _h, body: jsonEncode(body));
    if (r.statusCode != 200 && r.statusCode != 201) throw Exception('Push memory failed: ${r.statusCode}');
  }

  Future<List<ChatMessage>> fetchMessages(String roomId) async {
    final files = await listFiles(roomId);
    final results = <ChatMessage>[];
    await Future.wait(files.where((fn) => fn.startsWith('chat-') || fn.contains('agent')).map((fn) async {
      final c = await _raw_('rooms/$roomId/$fn');
      if (c == null) return;
      results.add(ChatMessage.fromMarkdown(c, fn));
    }));
    results.sort((a, b) {
      final ta = a.createdAt, tb = b.createdAt;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return ta.compareTo(tb);
    });
    return results;
  }

  Future<void> pushMessage(String roomId, String text, {String sender = 'Agent'}) async {
    if (_pat.isEmpty) throw Exception('No PAT');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final md = ['## Message', '**Sender:** $sender',
      '**Created:** ${DateTime.now().toIso8601String()}', '', text].join('\n');
    final r = await _client.put(
      Uri.parse('$_api/contents/rooms/$roomId/chat-$ts.md'),
      headers: _h,
      body: jsonEncode({'message': 'Chat — $roomId', 'content': base64Encode(utf8.encode(md))}));
    if (r.statusCode != 201) throw Exception('Push msg failed: ${r.statusCode}');
  }

  // ── Transcriptions ────────────────────────────────────────────────────────

  Future<List<TranscriptEntry>> fetchTranscripts(String roomId) async {
    final files = await listFiles(roomId);
    final results = <TranscriptEntry>[];
    await Future.wait(files.where((fn) => fn.startsWith('transcript-')).map((fn) async {
      final c = await _raw_('rooms/$roomId/$fn');
      if (c == null) return;
      results.add(TranscriptEntry.fromMarkdown(c, fn));
    }));
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }

  Future<void> pushTranscript(String roomId, TranscriptEntry entry) async {
    if (_pat.isEmpty) throw Exception('No PAT');
    final r = await _client.put(
      Uri.parse('$_api/contents/rooms/$roomId/transcript-${entry.id}.md'),
      headers: _h,
      body: jsonEncode({
        'message': 'Transcription — ${entry.agentName}',
        'content': base64Encode(utf8.encode(entry.toMarkdown())),
      }));
    if (r.statusCode != 201 && r.statusCode != 200) throw Exception('Push transcript failed: ${r.statusCode}');
  }

  // ── Prompts ───────────────────────────────────────────────────────────────

  Future<List<AgentPrompt>> fetchPrompts(String roomId) async {
    final files = await listFiles(roomId);
    final results = <AgentPrompt>[];
    await Future.wait(files.where((fn) => fn.startsWith('prompt-')).map((fn) async {
      final c = await _raw_('rooms/$roomId/$fn');
      if (c == null) return;
      results.add(AgentPrompt.fromMarkdown(c, fn));
    }));
    results.sort((a, b) {
      final ta = a.createdAt, tb = b.createdAt;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    return results;
  }

  Future<void> pushPrompt(String roomId, AgentPrompt prompt) async {
    if (_pat.isEmpty) throw Exception('No PAT');
    final r = await _client.put(
      Uri.parse('$_api/contents/rooms/$roomId/prompt-${prompt.id}.md'),
      headers: _h,
      body: jsonEncode({
        'message': 'Prompt ${prompt.name.isNotEmpty ? prompt.name : "#${prompt.number}"} — $roomId',
        'content': base64Encode(utf8.encode(prompt.toMarkdown())),
      }));
    if (r.statusCode != 201 && r.statusCode != 200) throw Exception('Push prompt failed: ${r.statusCode}');
  }

  Future<void> updatePromptStatus(String roomId, AgentPrompt prompt, String newStatus) async {
    if (_pat.isEmpty) throw Exception('No PAT');
    final updated = AgentPrompt(
      id: prompt.id, number: prompt.number, roomId: prompt.roomId,
      text: prompt.text, status: newStatus, name: prompt.name,
      createdAt: prompt.createdAt, attachments: prompt.attachments,
    );
    final path = 'rooms/$roomId/prompt-${prompt.id}.md';
    final sha = await _fileSha(path);
    final body = <String, dynamic>{
      'message': 'Status → $newStatus — ${prompt.name}',
      'content': base64Encode(utf8.encode(updated.toMarkdown())),
    };
    if (sha != null) body['sha'] = sha;
    final r = await _client.put(Uri.parse('$_api/contents/$path'), headers: _h, body: jsonEncode(body));
    if (r.statusCode != 200 && r.statusCode != 201) throw Exception('Update status failed: ${r.statusCode}');
  }

  // ── Direct prompts ────────────────────────────────────────────────────────

  Future<String?> fetchPromptContent(String id) => _raw_('prompts/$id.md');

  /// Fetches the commit history for a specific prompt file.
  Future<List<Map<String, dynamic>>> fetchPromptHistory(String id) async {
    if (_pat.isEmpty) return [];
    try {
      final r = await _client.get(
        Uri.parse('$_api/commits?path=prompts/$id.md&per_page=20'),
        headers: _h,
      );
      if (r.statusCode != 200) return [];
      final commits = jsonDecode(r.body) as List<dynamic>;
      return commits.map((c) {
        final map    = c as Map<String, dynamic>;
        final commit = map['commit'] as Map<String, dynamic>;
        final author = commit['author'] as Map<String, dynamic>?;
        final fullSha = map['sha'] as String? ?? '';
        return {
          'sha': fullSha.length >= 7 ? fullSha.substring(0, 7) : fullSha,
          'fullSha': fullSha,
          'message': (commit['message'] as String? ?? '').split('\n').first,
          'date': author?['date'] as String? ?? '',
          'author': author?['name'] as String? ?? 'Unknown',
        };
      }).toList();
    } catch (_) { return []; }
  }

  /// Fetches the raw content of a prompt file at a specific commit SHA.
  Future<String?> fetchPromptContentAtCommit(String id, String sha) async {
    try {
      final r = await _client.get(
        Uri.parse('$_api/contents/prompts/$id.md?ref=$sha'),
        headers: _h,
      );
      if (r.statusCode != 200) return null;
      final data    = jsonDecode(r.body) as Map<String, dynamic>;
      final encoded = data['content'] as String?;
      if (encoded == null) return null;
      return utf8.decode(base64Decode(encoded.replaceAll('\n', '')));
    } catch (_) { return null; }
  }

  Future<List<SavedPrompt>> fetchRemotePrompts() async {
    if (_pat.isEmpty) return [];
    try {
      final r = await _client.get(Uri.parse('$_api/contents/prompts'), headers: _h);
      if (r.statusCode != 200) return [];
      final files = (jsonDecode(r.body) as List<dynamic>)
          .where((f) {
            final name = f['name'] as String;
            if (!name.endsWith('.md')) return false;
            final id = name.replaceAll('.md', '');
            // Accept: 13-digit timestamp, timestamp_hex, or timestamp_hex format
            return RegExp(r'^\d{13}').hasMatch(id);
          })
          .toList();
      final results = <SavedPrompt>[];
      await Future.wait(files.map((f) async {
        final fileName = f['name'] as String;
        final id = fileName.replaceAll('.md', '');
        final rawUrl = '$_raw/prompts/$fileName';
        final content = await _raw_('prompts/$fileName');
        String promptName = id;
        DateTime? created;
        if (content != null) {
          final clean = stripPromptMeta(content);
          if (clean.isNotEmpty) promptName = _smartTitle(clean);
          // Extract timestamp from ID (works for both old and new format)
          final tsMatch = RegExp(r'^(\d{13})').firstMatch(id);
          if (tsMatch != null) {
            created = DateTime.fromMillisecondsSinceEpoch(int.parse(tsMatch.group(1)!));
          }
        }
        results.add(SavedPrompt(
          id: id,
          name: promptName.isNotEmpty ? promptName : id,
          link: rawUrl,
          created: created ?? DateTime.now(),
        ));
      }));
      results.sort((a, b) => b.created.compareTo(a.created));
      return results;
    } catch (_) { return []; }
  }

  /// Strips legacy metadata (HTML comment block + ## Contenu header) from raw file content.
  static String stripPromptMeta(String raw) {
    var s = raw;
    // Remove HTML comment metadata block
    s = s.replaceAll(RegExp(r'<!--[\s\S]*?-->', multiLine: true), '');
    // Remove legacy ## Contenu section header (keep the content after it)
    final contenuIdx = s.indexOf('## Contenu');
    if (contenuIdx != -1) {
      s = s.substring(contenuIdx + '## Contenu'.length);
    }
    // Remove ## Pièces jointes and everything after (not part of the prompt)
    final pjIdx = s.indexOf('\n## Pièces jointes');
    if (pjIdx != -1) s = s.substring(0, pjIdx);
    // Remove room context separator
    final sepIdx = s.indexOf('\n\n---\n\n## Contexte');
    if (sepIdx != -1) s = s.substring(0, sepIdx);
    return s.trim();
  }

  static String _smartTitle(String raw) {
    var s = raw.replaceAll(RegExp(r'#{1,6}\s*'), '')
               .replaceAll(RegExp(r'[*_`~>]'), '')
               .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
               .replaceAll(RegExp(r'\s+'), ' ')
               .trim();
    final sentences = s.split(RegExp(r'(?<=[.?!])\s+'));
    s = sentences.firstWhere((x) => x.trim().length > 6, orElse: () => s).trim();
    if (s.length > 60) {
      s = s.substring(0, 57);
      final last = s.lastIndexOf(' ');
      if (last > 15) s = s.substring(0, last);
      s = '$s…';
    }
    return s;
  }

  // ── Upload asset helper ───────────────────────────────────────────────────

  /// Pre-upload a file to a staging path and return its raw URL.
  /// Call this as soon as the user attaches a file so uploads run while they type.
  Future<String?> preUploadFile(String stagingId, AttachedFile file) async {
    if (_pat.isEmpty) return null;
    try {
      final safeName = file.name.replaceAll(' ', '_');
      return await _uploadAsset('assets/staging/$stagingId/$safeName', file.bytes);
    } catch (_) { return null; }
  }

  /// Télécharge les bytes bruts d'une URL (raw.githubusercontent.com ou autre).
  /// Envoie le token d'authentification si disponible.
  Future<Uint8List> downloadBytes(String url) async {
    final r = await _client.get(Uri.parse(url),
        headers: _pat.isNotEmpty ? {'Authorization': 'token $_pat'} : {});
    if (r.statusCode != 200) throw Exception('Téléchargement échoué : ${r.statusCode}');
    return r.bodyBytes;
  }

  Future<String> _uploadAsset(String path, Uint8List bytes, {String? message}) async {
    String? sha;
    final check = await _client.get(Uri.parse('$_api/contents/$path'), headers: _h);
    if (check.statusCode == 200) sha = (jsonDecode(check.body) as Map<String, dynamic>)['sha'] as String?;
    final body = jsonEncode({
      'message': message ?? 'upload $path',
      'content': base64Encode(bytes),
      if (sha != null) 'sha': sha,
    });
    final res = await _client.put(Uri.parse('$_api/contents/$path'), headers: _h, body: body);
    if (res.statusCode != 200 && res.statusCode != 201) throw Exception('Upload failed: ${res.statusCode}');
    return '$_raw/$path';
  }

  /// Retourne le MIME type d'après l'extension du fichier.
  static String _imageMime(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return const {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
      'png': 'image/png',  'gif': 'image/gif',
      'webp': 'image/webp',
    }[ext] ?? 'image/jpeg';
  }

  /// Génère une data URI base64 pour une image (inline dans le MD).
  /// Si l'image est trop grosse (> 3 Mo encodé), retourne null pour
  /// éviter de dépasser la limite de l'API GitHub (1 Mo par push).
  static String? _imageDataUri(String filename, Uint8List bytes) {
    final encoded = base64Encode(bytes);
    if (encoded.length > 3 * 1024 * 1024) return null; // > ~3 Mo → trop gros
    return 'data:${_imageMime(filename)};base64,$encoded';
  }

  Future<String> pushDirectPrompt(
    String id, String text, List<AttachedFile> files, {
    Room? room, String? roomContext,
    Map<String, String> preUploadedUrls = const {},
  }) async {
    if (_pat.isEmpty) throw Exception('PAT non configuré — va dans Paramètres');

    // urlMap  : nom original → URL raw GitHub (stockage permanent)
    // inlineMap: nom original → data URI base64 (affichage inline Claude/ChatGPT)
    final urlMap    = <String, String>{};
    final inlineMap = <String, String>{};

    for (final f in files) {
      final safeName = f.name.replaceAll(' ', '_');
      // Use pre-uploaded URL if available (uploaded while user was typing)
      if (preUploadedUrls.containsKey(f.name)) {
        urlMap[f.name] = preUploadedUrls[f.name]!;
      } else {
        // Upload vers GitHub pour la sauvegarde
        try {
          final url = await _uploadAsset('assets/prompts/$id/$safeName', f.bytes);
          urlMap[f.name] = url;
        } catch (_) {}
      }
      // Construit la data URI base64 pour l'affichage inline (Claude / ChatGPT)
      if (f.isImage) {
        final dataUri = _imageDataUri(f.name, f.bytes);
        inlineMap[f.name] = dataUri ?? (urlMap[f.name] ?? '');
      } else {
        inlineMap[f.name] = urlMap[f.name] ?? '';
      }
    }

    final mentionPattern = RegExp(r'@(\w+)');
    final usedFiles = <String>{};

    // Résout le nom original d'un fichier à partir d'une @mention (strict).
    // Priorité : correspondance exacte (slug = mention), puis préfixe slug.
    String resolveFileName(String mention) {
      final needle = mention.toLowerCase();
      // 1. Exact match on slug (name without extension, spaces→_)
      for (final key in inlineMap.keys) {
        final slug = key.replaceAll(' ', '_').replaceAll(RegExp(r'\.[^.]+$'), '').toLowerCase();
        if (slug == needle) return key;
      }
      // 2. Full filename (with extension) match
      for (final key in inlineMap.keys) {
        if (key.toLowerCase() == needle) return key;
      }
      // 3. Slug starts with mention (e.g. @photo matches photo_001.jpg)
      for (final key in inlineMap.keys) {
        final slug = key.replaceAll(' ', '_').replaceAll(RegExp(r'\.[^.]+$'), '').toLowerCase();
        if (slug.startsWith(needle)) return key;
      }
      return mention; // no match → keep the raw @mention text
    }

    final contentBuf = StringBuffer();
    int lastEnd = 0;
    for (final match in mentionPattern.allMatches(text)) {
      final beforeText = text.substring(lastEnd, match.start);
      if (beforeText.isNotEmpty) contentBuf.write(beforeText);
      final mentionKey = match.group(1)!;
      final fileName   = resolveFileName(mentionKey);
      final inlineUrl  = inlineMap[fileName] ?? '';
      if (inlineUrl.isNotEmpty) {
        if (usedFiles.contains(fileName)) {
          contentBuf.write('\n*[@$mentionKey — voir image ci-dessus]*\n');
        } else {
          usedFiles.add(fileName);
          // data URI → image inline dans Claude/ChatGPT
          contentBuf.write('\n\n![$fileName]($inlineUrl)\n\n');
        }
      } else {
        contentBuf.write(match.group(0)!);
      }
      lastEnd = match.end;
    }
    if (lastEnd < text.length) contentBuf.write(text.substring(lastEnd));
    final inlineContent = contentBuf.toString().trim();

    // Fichiers non mentionnés → section "Pièces jointes" avec data URI aussi
    final nonMentioned = inlineMap.entries.where((e) => !usedFiles.contains(e.key)).toList();

    // Build clean prompt content — no metadata block, no section headers
    final sb = StringBuffer();
    if (inlineContent.isNotEmpty) sb.write(inlineContent);

    // Non-mentioned attachments appended after the text
    if (nonMentioned.isNotEmpty) {
      if (sb.isNotEmpty) sb.write('\n\n');
      for (final e in nonMentioned) {
        if (e.value.isEmpty) continue;
        final isImg = ['png','jpg','jpeg','gif','webp']
            .contains(e.key.split('.').last.toLowerCase());
        if (isImg) {
          sb.writeln('![${e.key}](${e.value})');
        } else {
          sb.writeln('[${e.key}](${e.value})');
        }
      }
    }

    // Room context appended as a separator section (useful for the agent)
    if (roomContext != null && roomContext.trim().isNotEmpty) {
      sb.write('\n\n---\n\n## Contexte — ${room?.name ?? "Global"}\n\n');
      sb.write(roomContext.trim());
    }

    final promptPath = 'prompts/$id.md';
    final body = jsonEncode({'message': 'prompt: $id', 'content': base64Encode(utf8.encode(sb.toString()))});
    final r = await _client.put(Uri.parse('$_api/contents/$promptPath'), headers: _h, body: body);
    if (r.statusCode != 201 && r.statusCode != 200) throw Exception('Sauvegarde échouée: ${r.statusCode}');
    return '$_raw/$promptPath';
  }

  // ── OpenSpace ─────────────────────────────────────────────────────────────

  static bool _isVideoExt(String name) {
    final l = name.toLowerCase();
    return l.endsWith('.mp4') || l.endsWith('.mov') || l.endsWith('.avi') ||
           l.endsWith('.webm') || l.endsWith('.mkv') || l.endsWith('.m4v');
  }

  /// Retourne images ET vidéos du dossier openspace.
  Future<List<dynamic>> fetchOpenspaceFiles() async {
    try {
      final r = await _client.get(Uri.parse('$_api/contents/openspace'),
          headers: _pat.isNotEmpty ? _h : {});
      if (r.statusCode == 404) return [];
      if (r.statusCode != 200) throw Exception('Erreur ${r.statusCode}');
      final files = (jsonDecode(r.body) as List<dynamic>).where((f) {
        final name = (f['name'] as String).toLowerCase();
        return name.endsWith('.png') || name.endsWith('.jpg') ||
               name.endsWith('.jpeg') || name.endsWith('.gif') || name.endsWith('.webp') ||
               _isVideoExt(name);
      }).toList();
      return files.map((f) {
        final name = f['name'] as String;
        final slug = name.replaceAll(' ', '_').replaceAll(RegExp(r'\.[^.]+$'), '');
        return {
          'name': name,
          'mention': '@$slug',
          'rawUrl': '$_raw/openspace/$name',
          'sha': f['sha'] as String? ?? '',
          'isVideo': _isVideoExt(name),
        };
      }).toList();
    } catch (e) { throw Exception('Chargement OpenSpace : $e'); }
  }

  /// Alias legacy.
  Future<List<dynamic>> fetchOpenspaceImages() => fetchOpenspaceFiles();

  // GitHub Contents API: files up to 25 MB via base64 JSON; larger require Git Data API.
  static const _maxUploadBytes = 25 * 1024 * 1024; // 25 MB

  Future<Map<String, dynamic>> uploadOpenspaceImage(
      String originalName, Uint8List bytes, List<dynamic> existingImages) async {
    if (_pat.isEmpty) throw Exception('Token GitHub manquant');
    if (bytes.length > _maxUploadBytes) {
      final mb = (bytes.length / 1024 / 1024).toStringAsFixed(1);
      throw Exception('Fichier trop volumineux (${mb} Mo). La limite GitHub est 25 Mo.');
    }
    final ext = originalName.contains('.')
        ? originalName.substring(originalName.lastIndexOf('.')).toLowerCase() : '.jpg';
    final baseName = originalName.contains('.')
        ? originalName.substring(0, originalName.lastIndexOf('.')) : originalName;
    final safeBase = baseName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final existingNames = existingImages.map((f) => (f is Map ? f['name'] : '') as String).toSet();
    String finalName = '$safeBase$ext';
    if (existingNames.contains(finalName)) {
      int counter = 1;
      while (existingNames.contains('${safeBase}_$counter$ext')) counter++;
      finalName = '${safeBase}_$counter$ext';
    }
    final path = 'openspace/$finalName';
    final body = jsonEncode({'message': 'OpenSpace: add $finalName', 'content': base64Encode(bytes)});
    final r = await _client.put(Uri.parse('$_api/contents/$path'), headers: _h, body: body);
    if (r.statusCode != 201 && r.statusCode != 200) throw Exception('Upload échoué : ${r.statusCode}');
    final resp = jsonDecode(r.body) as Map<String, dynamic>;
    final sha = (resp['content'] as Map<String, dynamic>)['sha'] as String? ?? '';
    final slug = finalName.replaceAll(RegExp(r'\.[^.]+$'), '');
    return {'name': finalName, 'mention': '@$slug', 'rawUrl': '$_raw/$path', 'sha': sha};
  }

  Future<void> deleteOpenspaceImage(String name, String sha) async {
    if (_pat.isEmpty) throw Exception('Token GitHub manquant');
    final r = await _client.delete(Uri.parse('$_api/contents/openspace/$name'),
        headers: _h, body: jsonEncode({'message': 'OpenSpace: remove $name', 'sha': sha}));
    if (r.statusCode != 200) throw Exception('Suppression échouée : ${r.statusCode}');
  }

  // ── Clipboard partagé ─────────────────────────────────────────────────────

  static const _clipPath = 'clipboard/entries.json';

  Future<List<dynamic>> _fetchClipboardRaw() async {
    final r = await _client.get(Uri.parse('$_api/contents/$_clipPath'),
        headers: _pat.isNotEmpty ? _h : {});
    if (r.statusCode == 404) return [];
    if (r.statusCode != 200) throw Exception('Erreur ${r.statusCode}');
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final content = utf8.decode(base64Decode((body['content'] as String).replaceAll('\n', '')));
    return jsonDecode(content) as List<dynamic>;
  }

  Future<String?> _clipboardSha() async {
    final r = await _client.get(Uri.parse('$_api/contents/$_clipPath'), headers: _h);
    if (r.statusCode == 404) return null;
    return (jsonDecode(r.body) as Map<String, dynamic>)['sha'] as String?;
  }

  Future<List<ClipboardEntry>> fetchClipboardEntries() async {
    try {
      final raw = await _fetchClipboardRaw();
      final list = raw.map((e) => ClipboardEntry.fromJson(e as Map<String, dynamic>)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) { return []; }
  }

  Future<ClipboardEntry> saveClipboardEntry(String content) async {
    if (_pat.isEmpty) throw Exception('Token GitHub manquant');
    List<dynamic> entries;
    try { entries = await _fetchClipboardRaw(); } catch (_) { entries = []; }
    final entry = ClipboardEntry(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      content: content,
      createdAt: DateTime.now().toUtc(),
    );
    entries.insert(0, entry.toJson());
    final sha = await _clipboardSha();
    final body = <String, dynamic>{
      'message': 'Clipboard: add entry',
      'content': base64Encode(utf8.encode(jsonEncode(entries))),
      if (sha != null) 'sha': sha,
    };
    final r = await _client.put(Uri.parse('$_api/contents/$_clipPath'), headers: _h, body: jsonEncode(body));
    if (r.statusCode != 200 && r.statusCode != 201) throw Exception('Sauvegarde échouée : ${r.statusCode}');
    return entry;
  }

  Future<void> deleteClipboardEntry(String id) async {
    if (_pat.isEmpty) throw Exception('Token GitHub manquant');
    final raw = await _fetchClipboardRaw();
    final updated = raw.where((e) => (e as Map<String, dynamic>)['id'] != id).toList();
    final sha = await _clipboardSha();
    if (sha == null) return;
    final body = <String, dynamic>{
      'message': 'Clipboard: remove $id',
      'content': base64Encode(utf8.encode(jsonEncode(updated))),
      'sha': sha,
    };
    final r = await _client.put(Uri.parse('$_api/contents/$_clipPath'), headers: _h, body: jsonEncode(body));
    if (r.statusCode != 200 && r.statusCode != 201) throw Exception('Suppression échouée : ${r.statusCode}');
  }
}
