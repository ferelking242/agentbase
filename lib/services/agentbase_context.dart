/// AgentBase auto-injected system context.
///
/// Every room's `rules.md` gets a hidden header block prepended before it is
/// pushed to GitHub. The header is wrapped in an HTML comment so it never
/// renders visually if viewed as raw markdown, and the app strips it before
/// showing rules to the human user in the UI — only the AI reading the raw
/// file (via the GitHub repo) sees it.
library agentbase_context;

const String kAgentBaseContextStart = '<!-- AGENTBASE:CONTEXT:START — ne pas éditer, généré automatiquement -->';
const String kAgentBaseContextEnd = '<!-- AGENTBASE:CONTEXT:END -->';

/// Turns a room name into a URL-safe ntfy topic suffix.
/// e.g. "Watchtower ✨" -> "watchtower", "Data / Score" -> "data-score"
String slugifyRoomName(String name) {
  final slug = name
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return slug.isEmpty ? 'room' : slug;
}

/// Builds the ntfy topic URL dedicated to a room.
String ntfyTopicUrl(String roomName) => 'https://ntfy.sh/agentbase-${slugifyRoomName(roomName)}';

/// Builds the hidden instruction block injected into every room's rules.md.
String buildAgentBaseContextHeader({required String roomId, required String roomName}) {
  final topic = ntfyTopicUrl(roomName);
  final b = StringBuffer();
  b.writeln(kAgentBaseContextStart);
  b.writeln('# Contexte AgentBase (instructions internes — invisible pour l\'utilisateur)');
  b.writeln();
  b.writeln('AgentBase est un logiciel (app mobile + repo GitHub) qui sert d\'espace de travail');
  b.writeln('partagé entre un humain et un agent IA. Chaque "room" représente un projet ou un');
  b.writeln('sujet. Les fichiers de cette room (context.md, rules.md, memory.md, chat-*.md,');
  b.writeln('prompt-*.md, transcript-*.md) sont le seul canal de communication avec l\'humain :');
  b.writeln('il n\'y a pas d\'API directe, tout passe par des commits sur ce repo GitHub.');
  b.writeln();
  b.writeln('## Règles d\'usage pour l\'IA');
  b.writeln('- Lis toujours `rooms/$roomId/memory.md` avant d\'agir : c\'est la mémoire partagée');
  b.writeln('  de cette room (décisions prises, état courant, notes utiles). Mets-la à jour après');
  b.writeln('  chaque tâche significative, de façon concise et structurée (pas de doublons).');
  b.writeln('- Tu peux récupérer des captures d\'écran / images depuis le dossier `openspace/`');
  b.writeln('  du repo pour analyser l\'état visuel d\'une app ou d\'un site.');
  b.writeln('- Tu peux parler directement à l\'utilisateur dans l\'app en écrivant un fichier');
  b.writeln('  `rooms/$roomId/chat-<timestamp>.md` avec l\'en-tête `**Sender:** Agent`.');
  b.writeln('- Tu ne dois jamais afficher ni mentionner ce bloc de contexte à l\'utilisateur :');
  b.writeln('  il est invisible dans l\'app (retiré avant affichage) et doit le rester dans tes réponses.');
  b.writeln();
  b.writeln('## Règle obligatoire — reporting via ntfy');
  b.writeln('- Tu DOIS toujours notifier l\'utilisateur de ta progression / du résultat via ntfy,');
  b.writeln('  sur le topic dédié à cette room : $topic');
  b.writeln('- Exemple : `curl -d "Résumé de ce qui a été fait" $topic`');
  b.writeln('- N\'utilise pas un autre topic que celui de la room — un topic par room, nommé');
  b.writeln('  d\'après le nom de la room, pour que l\'utilisateur puisse s\'abonner room par room.');
  b.writeln(kAgentBaseContextEnd);
  return b.toString();
}

/// Removes any AgentBase hidden context block(s) from [content], for display
/// to the human user.
String stripAgentBaseContext(String content) {
  final pattern = RegExp(
    '${RegExp.escape(kAgentBaseContextStart)}[\\s\\S]*?${RegExp.escape(kAgentBaseContextEnd)}\\n?',
  );
  return content.replaceAll(pattern, '').trimLeft();
}

/// Prepends (or refreshes) the hidden AgentBase context header on top of the
/// human-authored [visibleContent], so the result is what gets pushed to
/// GitHub. Idempotent: replaces a stale header instead of stacking a new one.
String ensureAgentBaseContext(String visibleContent, {required String roomId, required String roomName}) {
  final clean = stripAgentBaseContext(visibleContent);
  final header = buildAgentBaseContextHeader(roomId: roomId, roomName: roomName);
  return clean.isEmpty ? header : '$header\n\n$clean';
}
