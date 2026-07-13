import 'dart:convert'; // ignore: unused_import
  class AgentPrompt {
    final String id, roomId, text, status, name;
    final int number;
    final DateTime? createdAt;
    final List<PromptAttachment> attachments;

    const AgentPrompt({
      required this.id, required this.number, required this.roomId,
      required this.text, required this.status, this.name = '',
      this.createdAt, this.attachments = const [],
    });

    factory AgentPrompt.fromMarkdown(String content, String filename) {
      int number = 0;
      String text = '', status = 'pending', id = '', name = '';
      DateTime? createdAt;
      final attachments = <PromptAttachment>[];
      final lines = content.split('\n');
      if (lines.isNotEmpty && lines[0].startsWith('## ')) {
        final h = lines[0].substring(3);
        if (h.startsWith('Prompt: ')) name = h.substring(8).trim();
        final nm = RegExp(r'#(\d+)').firstMatch(h);
        if (nm != null) number = int.tryParse(nm.group(1)!) ?? 0;
      }
      for (int i = 1; i < lines.length; i++) {
        final l = lines[i];
        if (l.startsWith('**ID:**')) id = l.replaceFirst('**ID:**','').trim();
        else if (l.startsWith('**Created:**')) { try { createdAt = DateTime.parse(l.replaceFirst('**Created:**','').trim()); } catch(_){} }
        else if (l.startsWith('**Status:**')) status = l.replaceFirst('**Status:**','').trim();
        else if (l.trim() == '### Instructions') {
          final buf = StringBuffer(); i++;
          while (i < lines.length && !lines[i].startsWith('###')) { buf.writeln(lines[i]); i++; }
          text = buf.toString().trim(); i--;
        } else if (l.trim() == '### Attachments') {
          i++;
          while (i < lines.length) {
            final ln = lines[i];
            if (ln.startsWith('- **')) {
              final tm = RegExp(r'\*\*(\w+)\*\*').firstMatch(ln);
              final nm2 = RegExp(r'`([^`]+)`').firstMatch(ln);
              final t = tm?.group(1)?.toLowerCase() ?? 'file';
              final n = nm2?.group(1) ?? 'file';
              final b64 = StringBuffer(); i++;
              if (i < lines.length && lines[i].startsWith('```')) {
                i++;
                while (i < lines.length && !lines[i].startsWith('```')) { b64.write(lines[i].trim()); i++; }
              }
              final s = b64.toString();
              attachments.add(PromptAttachment(type: t, name: n, path: '', base64Data: s.isNotEmpty ? s : null, sizeBytes: s.isNotEmpty ? (s.length*3~/4) : 0));
            }
            i++;
          }
        }
      }
      if (id.isEmpty) {
        final tsM = RegExp(r'\d{13}').firstMatch(filename);
        id = tsM?.group(0) ?? filename;
        if (createdAt == null && tsM != null) createdAt = DateTime.fromMillisecondsSinceEpoch(int.parse(tsM.group(0)!));
      }
      return AgentPrompt(id: id, number: number, roomId: '', text: text, status: status, name: name, createdAt: createdAt, attachments: attachments);
    }

    String toMarkdown() {
      final buf = StringBuffer();
      if (name.isNotEmpty) buf.writeln('## Prompt: $name');
      else buf.writeln('## Prompt #$number — Room: $roomId');
      buf.writeln(); buf.writeln('**ID:** $id');
      buf.writeln('**Created:** ${createdAt?.toIso8601String() ?? DateTime.now().toIso8601String()}');
      buf.writeln('**Status:** $status');
      buf.writeln(); buf.writeln('### Instructions'); buf.writeln();
      buf.writeln(text);
      if (attachments.isNotEmpty) {
        buf.writeln(); buf.writeln('### Attachments');
        for (final a in attachments) {
          buf.writeln(); buf.writeln('- **${a.type.toUpperCase()}** `${a.name}`');
          if (a.base64Data != null && a.base64Data!.isNotEmpty) {
            buf.writeln(); buf.writeln('```base64'); buf.writeln(a.base64Data); buf.writeln('```');
          }
        }
      }
      return buf.toString();
    }
  }

  class PromptAttachment {
    final String type, name, path;
    final String? base64Data;
    final int sizeBytes;
    const PromptAttachment({required this.type, required this.name, required this.path, this.base64Data, required this.sizeBytes});
  }