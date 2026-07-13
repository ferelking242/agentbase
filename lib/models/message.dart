class ChatMessage {
    final String id, sender, content;
    final bool isUser;
    final DateTime? createdAt;
    const ChatMessage({required this.id, required this.sender, required this.content, required this.isUser, this.createdAt});

    factory ChatMessage.fromMarkdown(String content, String filename) {
      String sender = 'Agent';
      bool isUser = filename.startsWith('chat-') && !filename.contains('agent');
      final lines = content.split('\n');
      for (final l in lines) {
        if (l.startsWith('**Sender:**')) { sender = l.replaceFirst('**Sender:**','').trim(); break; }
        if (l.startsWith('## ')) { sender = l.substring(3).trim(); break; }
      }
      if (isUser) sender = 'Moi';
      DateTime? ts;
      final m = RegExp(r'\d{13}').firstMatch(filename);
      if (m != null) ts = DateTime.fromMillisecondsSinceEpoch(int.parse(m.group(0)!));
      // extract body text (after empty line following headers)
      String body = content;
      final blankIdx = lines.indexWhere((l) => l.isEmpty, 2);
      if (blankIdx != -1 && blankIdx < lines.length - 1) {
        body = lines.sublist(blankIdx + 1).where((l) => !l.startsWith('**')).join('\n').trim();
      }
      return ChatMessage(id: filename, sender: sender, content: body.isNotEmpty ? body : content, isUser: isUser, createdAt: ts);
    }

    String toMarkdown(String text) {
      final ts = DateTime.now();
      return [
        '## Message utilisateur',
        '**Sender:** Moi',
        '**Created:** ${ts.toIso8601String()}',
        '',
        text,
      ].join('\n');
    }
  }