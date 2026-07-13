import 'package:flutter/material.dart';

class Room {
  final String id, name, description, color;
  final int transcriptCount, chatCount;
  final String? githubUrl;
  final String? stack;
  final List<String> linkedRepos;

  const Room({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
    this.transcriptCount = 0,
    this.chatCount = 0,
    this.githubUrl,
    this.stack,
    this.linkedRepos = const [],
  });

  int get promptCount => transcriptCount + chatCount;

  factory Room.fromJson(Map<String, dynamic> j) => Room(
    id:              j['id']               as String? ?? '',
    name:            j['name']             as String? ?? 'Room',
    description:     j['description']      as String? ?? '',
    color:           j['color']            as String? ?? '#6366f1',
    transcriptCount: j['transcript_count'] as int? ?? 0,
    chatCount:       j['chat_count']       as int? ?? 0,
    githubUrl:       j['github_url']       as String?,
    stack:           j['stack']            as String?,
    linkedRepos:     (j['linked_repos'] as List<dynamic>?)
                         ?.map((e) => e as String).toList() ?? [],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'color': color,
    'transcript_count': transcriptCount,
    'chat_count': chatCount,
    if (githubUrl != null) 'github_url': githubUrl,
    if (stack != null) 'stack': stack,
    if (linkedRepos.isNotEmpty) 'linked_repos': linkedRepos,
  };

  Color get accentColor {
    try { return Color(int.parse('FF${color.replaceAll("#", "")}', radix: 16)); }
    catch (_) { return const Color(0xFF6366F1); }
  }

  IconData get iconData {
    switch (id.toLowerCase()) {
      case 'watchtower': return Icons.radar_outlined;
      case 'scorais':    return Icons.bar_chart_outlined;
      default:
        final l = name.toLowerCase();
        if (l.contains('code') || l.contains('dev'))      return Icons.code_outlined;
        if (l.contains('design') || l.contains('ui'))     return Icons.palette_outlined;
        if (l.contains('data')  || l.contains('score'))   return Icons.bar_chart_outlined;
        if (l.contains('watch') || l.contains('monitor')) return Icons.radar_outlined;
        if (l.contains('server') || l.contains('back'))   return Icons.dns_outlined;
        if (l.contains('site') || l.contains('web'))      return Icons.language_outlined;
        return Icons.layers_outlined;
    }
  }
}
