import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'github_service.dart';
import 'notification_service.dart';

/// Polls GitHub rooms for new agent-written files (transcript-*.md, chat-*.md from Agent).
/// Runs every [interval] while the app is in foreground.
class AgentPollerService {
  final GitHubService github;
  final Duration interval;

  Timer? _timer;
  static const _seenKey = 'agentbase_seen_agent_files';

  AgentPollerService({required this.github, this.interval = const Duration(minutes: 1)});

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _poll());
    _poll(); // immediate first check
  }

  void stop() => _timer?.cancel();

  Future<void> _poll() async {
    if (!github.hasPat) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen  = Set<String>.from(prefs.getStringList(_seenKey) ?? []);
      bool updated = false;

      final rooms = await github.fetchRooms();
      for (final room in rooms) {
        final files = await github.listFiles(room.id);
        for (final file in files) {
          final key = '${room.id}/$file';
          if (seen.contains(key)) continue;
          seen.add(key);
          updated = true;

          // Transcript file → agent completed a task
          if (file.startsWith('transcript-')) {
            await NotificationService.notifyAgentDone(
              message: '${room.name} — Transcription disponible',
              link: 'rooms/${room.id}/$file',
            );
          }
          // Chat file from agent (not a user message)
          else if (file.startsWith('chat-') && file.endsWith('.md')) {
            final content = await github.fetchRoomFile(room.id, file);
            if (content != null && content.contains('**Sender:** Agent')) {
              await NotificationService.notifyAgentDone(
                message: '${room.name} — Message de l\'agent',
                link: 'rooms/${room.id}/$file',
              );
            }
          }
        }
      }

      if (updated) {
        final list = seen.toList();
        // Keep max 500 entries
        if (list.length > 500) list.removeRange(0, list.length - 500);
        await prefs.setStringList(_seenKey, list);
      }
    } catch (_) {}
  }
}
