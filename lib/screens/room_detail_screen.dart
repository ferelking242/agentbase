import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/room.dart';
import '../models/prompt.dart';
import '../models/message.dart';
import '../services/github_service.dart';
import '../services/prefs_service.dart';
import '../services/agentbase_context.dart';
import '../theme.dart';
import '../widgets/app_components.dart';

/// Shared markdown style sheet so bold/italic/headers/lists/links render
/// consistently everywhere content is shown "flush" on the page (no box).
MarkdownStyleSheet mdStyleSheet(BuildContext context) => MarkdownStyleSheet(
  p: GoogleFonts.inter(color: kText2, fontSize: 13.5, height: 1.5),
  strong: GoogleFonts.inter(color: kText, fontSize: 13.5, height: 1.5, fontWeight: FontWeight.w700),
  em: GoogleFonts.inter(color: kText2, fontSize: 13.5, height: 1.5, fontStyle: FontStyle.italic),
  h1: GoogleFonts.inter(color: kText, fontSize: 18, fontWeight: FontWeight.w700),
  h2: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600),
  h3: GoogleFonts.inter(color: kText2, fontSize: 13.5, fontWeight: FontWeight.w600),
  listBullet: GoogleFonts.inter(color: kText2, fontSize: 13.5, height: 1.5),
  code: GoogleFonts.robotoMono(color: kAccentMid, fontSize: 12.5, backgroundColor: kCard),
  blockquote: GoogleFonts.inter(color: kMuted2, fontSize: 13.5, fontStyle: FontStyle.italic),
  a: GoogleFonts.inter(color: kAccentMid, fontSize: 13.5, decoration: TextDecoration.underline),
  blockquoteDecoration: const BoxDecoration(),
  codeblockDecoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(6)),
  h1Padding: const EdgeInsets.only(bottom: 8),
  h2Padding: const EdgeInsets.only(bottom: 6, top: 4),
  h3Padding: const EdgeInsets.only(bottom: 4),
  pPadding: const EdgeInsets.only(bottom: 4),
);

// ─── Entry point ──────────────────────────────────────────────────────────────
class RoomDetailScreen extends StatelessWidget {
  final Room room;
  final GitHubService github;
  const RoomDetailScreen({super.key, required this.room, required this.github});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 7,
    child: Scaffold(backgroundColor: kBg, body: _RoomBody(room: room, github: github)),
  );
}

// ─── Body ─────────────────────────────────────────────────────────────────────
class _RoomBody extends StatefulWidget {
  final Room room;
  final GitHubService github;
  const _RoomBody({required this.room, required this.github});
  @override State<_RoomBody> createState() => _RoomBodyState();
}

class _RoomBodyState extends State<_RoomBody> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  String? _context;
  String _rules = '';
  List<String> _rulesList = [];
  String? _memory;
  List<ChatMessage> _messages = [];
  List<_LocalPrompt> _prompts = [];
  List<TranscriptEntry> _transcripts = [];
  bool _ctxLoading = true, _rulesLoading = true, _chatLoading = true;
  bool _promptLoading = true, _transcriptLoading = true, _memoryLoading = true;
  bool _rulesSaving = false, _rulesDirty = false;
  bool _ctxSaving = false, _memorySaving = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 7, vsync: this);
    _tab.addListener(() { if (!_tab.indexIsChanging) _loadTab(_tab.index); });
    _loadTab(0);
  }

  @override void dispose() { _tab.dispose(); super.dispose(); }

  void _loadTab(int i) {
    if (i == 0) { _loadContext(); _loadRules(); }
    if (i == 1 && _ctxLoading) _loadContext();
    if (i == 2 && _rulesLoading) _loadRules();
    if (i == 3 && _chatLoading) _loadChat();
    if (i == 4 && _transcriptLoading) _loadTranscripts();
    if (i == 5 && _promptLoading) _loadPrompts();
    if (i == 6 && _memoryLoading) _loadMemory();
  }

  Future<void> _loadContext() async {
    try {
      final c = await widget.github.fetchContext(widget.room.id);
      if (mounted) setState(() { _context = c; _ctxLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _ctxLoading = false);
    }
  }

  Future<void> _loadRules() async {
    try {
      final raw = await widget.github.fetchRules(widget.room.id);
      // Strip the hidden AgentBase context header before showing rules to the
      // human — that block is only meant for the AI reading the raw file.
      final visible = stripAgentBaseContext(raw ?? '');
      if (mounted) setState(() { _rules = visible; _rulesList = _parseRules(visible); _rulesLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _rulesLoading = false);
    }
  }

  Future<void> _loadMemory() async {
    try {
      final m = await widget.github.fetchMemory(widget.room.id);
      if (mounted) setState(() { _memory = m; _memoryLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _memoryLoading = false);
    }
  }

  Future<void> _loadChat() async {
    try {
      final m = await widget.github.fetchMessages(widget.room.id);
      if (mounted) setState(() { _messages = m; _chatLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _chatLoading = false);
    }
  }

  Future<void> _loadPrompts() async {
    try {
      final p = await widget.github.fetchPrompts(widget.room.id);
      if (mounted) setState(() {
        _prompts = p.map((a) => _LocalPrompt(id: a.id, name: a.name, text: a.text, status: a.status, createdAt: a.createdAt)).toList();
        _promptLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _promptLoading = false);
    }
  }

  Future<void> _loadTranscripts() async {
    try {
      final t = await widget.github.fetchTranscripts(widget.room.id);
      if (mounted) setState(() { _transcripts = t; _transcriptLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _transcriptLoading = false);
    }
  }

  List<String> _parseRules(String md) {
    final out = <String>[];
    for (final l in md.split('\n')) {
      final t = l.trim();
      if (t.startsWith('- ') || t.startsWith('* ')) out.add(t.substring(2).trim());
      else if (RegExp(r'^\d+\.\s').hasMatch(t)) out.add(t.replaceFirst(RegExp(r'^\d+\.\s'), '').trim());
      else if (t.isNotEmpty && !t.startsWith('#')) out.add(t);
    }
    return out.where((s) => s.isNotEmpty).toList();
  }

  String _rulesToMd() => _rulesList.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n');

  Future<void> _saveRules() async {
    if (!widget.github.hasPat) { showAppSnack(context, 'Token GitHub requis', color: kYellow); return; }
    setState(() => _rulesSaving = true);
    try {
      // Re-inject (or refresh) the hidden AgentBase context header on top of
      // the human-edited rules before pushing — the human never sees it.
      final full = ensureAgentBaseContext(_rulesToMd(), roomId: widget.room.id, roomName: widget.room.name);
      await widget.github.pushRules(widget.room.id, full);
      if (mounted) { setState(() { _rulesSaving = false; _rulesDirty = false; }); showAppSnack(context, 'Règles sauvegardées'); }
    } catch (e) {
      if (mounted) { setState(() => _rulesSaving = false); showAppSnack(context, 'Erreur: $e', isError: true); }
    }
  }

  Future<void> _saveMemory(String content) async {
    if (!widget.github.hasPat) { showAppSnack(context, 'Token GitHub requis', color: kYellow); return; }
    setState(() => _memorySaving = true);
    try {
      await widget.github.pushMemory(widget.room.id, content);
      if (mounted) { setState(() { _memory = content; _memorySaving = false; }); showAppSnack(context, 'Mémoire sauvegardée'); }
    } catch (e) {
      if (mounted) { setState(() => _memorySaving = false); showAppSnack(context, 'Erreur: $e', isError: true); }
    }
  }

  Future<void> _saveContext(String content) async {
    if (!widget.github.hasPat) { showAppSnack(context, 'Token GitHub requis', color: kYellow); return; }
    setState(() => _ctxSaving = true);
    try {
      await widget.github.pushContext(widget.room.id, content);
      if (mounted) { setState(() { _context = content; _ctxSaving = false; }); showAppSnack(context, 'Contexte sauvegardé'); }
    } catch (e) {
      if (mounted) { setState(() => _ctxSaving = false); showAppSnack(context, 'Erreur: $e', isError: true); }
    }
  }

  void _openUrl(String url) async {
    try { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.room.accentColor;
    final projectUrl = widget.room.githubUrl ?? 'https://github.com/${widget.github.owner}/${widget.github.repo}/tree/main/rooms/${widget.room.id}';
    return NestedScrollView(
      headerSliverBuilder: (ctx, _) => [
        SliverAppBar(
          backgroundColor: kBg,
          pinned: true, floating: false,
          surfaceTintColor: Colors.transparent,
          leading: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Padding(padding: const EdgeInsets.all(10), child: Container(
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
              child: const Icon(Icons.arrow_back_ios_new, size: 13, color: kMuted),
            )),
          ),
          title: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.room.iconData, size: 15, color: accent),
            const SizedBox(width: 7),
            Flexible(child: Text(widget.room.name,
              style: GoogleFonts.inter(color: kText, fontSize: 14.5, fontWeight: FontWeight.w600, letterSpacing: -0.2),
              overflow: TextOverflow.ellipsis)),
          ]),
          centerTitle: true,
          actions: [
            GestureDetector(
              onTap: () => _openUrl(projectUrl),
              child: Padding(padding: const EdgeInsets.only(right: 14, top: 10, bottom: 10), child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
                child: const Icon(Icons.code_rounded, size: 16, color: kMuted),
              )),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: Container(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBorder, width: 0.5))),
              child: TabBar(
                controller: _tab,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicator: UnderlineTabIndicator(
                  borderSide: BorderSide(color: accent, width: 2),
                  insets: const EdgeInsets.symmetric(horizontal: 8),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: kText,
                unselectedLabelColor: kMuted2,
                labelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
                unselectedLabelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w400),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Accueil'),
                  Tab(text: 'Contexte'),
                  Tab(text: 'Règles'),
                  Tab(text: 'Chat'),
                  Tab(text: 'Transcription'),
                  Tab(text: 'Prompts'),
                  Tab(text: 'Mémoire'),
                ],
              ),
            ),
          ),
        ),
      ],
      body: TabBarView(controller: _tab, children: [
        _AccueilTab(room: widget.room, context2: _context, rules: _rulesList, github: widget.github,
          onNavigate: (i) => _tab.animateTo(i),
          onPromptSent: (lp) => setState(() => _prompts.insert(0, lp)),
          onSnack: (msg, c) => showAppSnack(context, msg, color: c)),
        _ContexteTab(content: _context, loading: _ctxLoading, saving: _ctxSaving, onSave: _saveContext),
        _ReglesTab(
          rules: _rulesList, loading: _rulesLoading, saving: _rulesSaving, dirty: _rulesDirty,
          onAdd: (r) => setState(() { _rulesList.add(r); _rulesDirty = true; }),
          onEdit: (i, r) => setState(() { _rulesList[i] = r; _rulesDirty = true; }),
          onDelete: (i) => setState(() { _rulesList.removeAt(i); _rulesDirty = true; }),
          onSave: _saveRules,
        ),
        _ChatTab(
          room: widget.room, messages: _messages, loading: _chatLoading, github: widget.github,
          onSent: (m) => setState(() => _messages.add(m)),
          onSnack: (msg, c) => showAppSnack(context, msg, color: c),
        ),
        _TranscriptionTab(
          room: widget.room, transcripts: _transcripts, loading: _transcriptLoading, github: widget.github,
          onSent: (t) => setState(() => _transcripts.insert(0, t)),
          onSnack: (msg, c) => showAppSnack(context, msg, color: c),
        ),
        _PromptTab(
          room: widget.room, prompts: _prompts, loading: _promptLoading, github: widget.github,
          onSent: (lp) => setState(() => _prompts.insert(0, lp)),
          onStatusChanged: (i, s) => setState(() => _prompts[i] = _prompts[i].copyWith(status: s)),
          onSnack: (msg, c) => showAppSnack(context, msg, color: c),
        ),
        _MemoireTab(content: _memory, loading: _memoryLoading, saving: _memorySaving, onSave: _saveMemory),
      ]),
    );
  }
}

// ─── Tab 0: Accueil ───────────────────────────────────────────────────────────
class _AccueilTab extends StatefulWidget {
  final Room room;
  final String? context2;
  final List<String> rules;
  final GitHubService github;
  final ValueChanged<int> onNavigate;
  final ValueChanged<_LocalPrompt> onPromptSent;
  final void Function(String, Color) onSnack;
  const _AccueilTab({required this.room, this.context2, required this.rules, required this.github,
      required this.onNavigate, required this.onPromptSent, required this.onSnack});

  @override
  State<_AccueilTab> createState() => _AccueilTabState();
}

class _AccueilTabState extends State<_AccueilTab> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  String? _bannerImageUrl;
  bool _bannerLoaded = false;

  @override
  void initState() {
    super.initState();
    _fetchLinkedRepoBanner();
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _fetchLinkedRepoBanner() async {
    if (widget.room.linkedRepos.isEmpty) { setState(() => _bannerLoaded = true); return; }
    try {
      final repoUrl = widget.room.linkedRepos.first;
      final match = RegExp(r'github\.com/([^/]+)/([^/?#]+)').firstMatch(repoUrl);
      if (match == null) { setState(() => _bannerLoaded = true); return; }
      final owner = match.group(1)!;
      final repo = match.group(2)!.replaceAll('.git', '');
      final url = 'https://api.github.com/repos/$owner/$repo/readme';
      final resp = await widget.github.getPublicJson(url);
      if (resp == null) { if (mounted) setState(() => _bannerLoaded = true); return; }
      final content = resp['content'] as String? ?? '';
      final decoded = utf8.decode(base64.decode(content.replaceAll('\n', '')));
      // Extract first markdown image URL from README
      final imgMatch = RegExp(r'!\[.*?\]\((https?://[^\)]+)\)').firstMatch(decoded);
      if (imgMatch != null) {
        if (mounted) setState(() { _bannerImageUrl = imgMatch.group(1); _bannerLoaded = true; });
        return;
      }
      // Try HTML img tag
      final htmlMatch = RegExp(r'<img[^>]+src=["\'](https?://[^"\']+)["\']').firstMatch(decoded);
      if (htmlMatch != null && mounted) {
        setState(() { _bannerImageUrl = htmlMatch.group(1); _bannerLoaded = true; });
        return;
      }
      if (mounted) setState(() => _bannerLoaded = true);
    } catch (_) {
      if (mounted) setState(() => _bannerLoaded = true);
    }
  }

  void _openUrl(String url) async {
    try { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); } catch (_) {}
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    if (!widget.github.hasPat) { widget.onSnack('Token GitHub requis', kYellow); return; }
    setState(() => _sending = true);
    try {
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      final name = words.take(8).join(' ');
      final prompt = AgentPrompt(id: ts, number: 0, roomId: widget.room.id, text: t, status: 'pending', name: name, createdAt: DateTime.now());
      await widget.github.pushPrompt(widget.room.id, prompt);
      final lp = _LocalPrompt(id: ts, name: name, text: t, status: 'pending', createdAt: prompt.createdAt);
      _ctrl.clear();
      if (mounted) setState(() => _sending = false);
      widget.onPromptSent(lp);
      widget.onSnack('Prompt ajouté', kGreen);
    } catch (e) {
      if (mounted) { setState(() => _sending = false); widget.onSnack('Erreur: $e', kRed); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final rules = widget.rules;
    final context2 = widget.context2;
    final onNavigate = widget.onNavigate;
    final accent = room.accentColor;
    final hasContent = _ctrl.text.trim().isNotEmpty;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 40), children: [
      // ── Hero ──────────────────────────────────────────────────────────────
      // Banner from linked repo README (if available)
      if (_bannerImageUrl != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: CachedNetworkImage(
            imageUrl: _bannerImageUrl!,
            height: 140, width: double.infinity,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      if (_bannerImageUrl != null) const SizedBox(height: 16),
      Center(child: Column(children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: accent.withOpacity(0.3), width: 1.5),
          ),
          child: Icon(room.iconData, size: 32, color: accent),
        ),
        const SizedBox(height: 12),
        Text(room.name, style: GoogleFonts.inter(color: kText, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.7)),
        if (room.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(room.description,
            style: GoogleFonts.inter(color: kMuted2, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center),
        ],
        if (room.stack != null && room.stack!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center,
            children: room.stack!.split(',').map((s) => _Chip(s.trim())).toList()),
        ],
      ])),
      const SizedBox(height: 20),

      // ── Zone de prompt rapide (style home screen) ────────────────────────
      Container(
        decoration: BoxDecoration(
          color: kCard2,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: kBorder2, width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 12, offset: const Offset(0, 3))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: TextField(
              controller: _ctrl,
              minLines: 1, maxLines: 5,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _send(),
              style: GoogleFonts.inter(color: kText, fontSize: 14, height: 1.5),
              cursorColor: accent, cursorWidth: 1.5,
              decoration: InputDecoration(
                hintText: 'Envoyer un prompt à ${room.name}…',
                hintStyle: GoogleFonts.inter(color: kMuted2, fontSize: 14),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: true,
                fillColor: Colors.transparent,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              const Spacer(),
              GestureDetector(
                onTap: (hasContent && !_sending) ? _send : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: hasContent ? accent : kCard,
                    shape: BoxShape.circle,
                    border: Border.all(color: hasContent ? Colors.transparent : kBorder, width: 0.5),
                  ),
                  child: _sending
                      ? const Center(child: SizedBox(width: 13, height: 13, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5)))
                      : Icon(Icons.arrow_upward_rounded, size: 16, color: hasContent ? Colors.white : kMuted2),
                ),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),

      // ── Stats ─────────────────────────────────────────────────────────────
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _StatCell('${room.transcriptCount}', 'Prompts'),
          _VSep(),
          _StatCell('${room.chatCount}', 'Messages'),
          _VSep(),
          _StatCell('${rules.length}', 'Règles'),
        ]),
      ),
      const SizedBox(height: 16),

      // ── Quick actions ─────────────────────────────────────────────────────
      const _SectionLabel('ACTIONS RAPIDES'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _QuickAction(icon: Icons.chat_bubble_outline, label: 'Chat', color: accent, onTap: () => onNavigate(3))),
        const SizedBox(width: 10),
        Expanded(child: _QuickAction(icon: Icons.description_outlined, label: 'Transcrire', color: accent, onTap: () => onNavigate(4))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _QuickAction(icon: Icons.rule_rounded, label: 'Règles', color: accent, onTap: () => onNavigate(2))),
        const SizedBox(width: 10),
        Expanded(child: _QuickAction(icon: Icons.notes_rounded, label: 'Contexte', color: accent, onTap: () => onNavigate(1))),
      ]),
      const SizedBox(height: 20),

      if (room.linkedRepos.isNotEmpty) ...[
        const _SectionLabel('REPOS LIÉS'),
        const SizedBox(height: 8),
        ...room.linkedRepos.map((url) {
          final parts = url.replaceFirst('https://github.com/', '').split('/');
          final repoName = parts.length >= 2 ? parts[1] : url;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _LinkCard(
              icon: Icons.link_rounded,
              title: repoName,
              subtitle: url.replaceFirst('https://github.com/', ''),
              color: kMuted,
              onTap: () => _openUrl(url),
            ),
          );
        }),
        const SizedBox(height: 16),
      ],

      // ── Context preview ───────────────────────────────────────────────────
      if (context2 != null && context2!.isNotEmpty) ...[
        const _SectionLabel('CONTEXTE'),
        const SizedBox(height: 8),
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Text(
            context2!.split('\n').where((l) => l.isNotEmpty && !l.startsWith('#')).take(3).join(' '),
            style: GoogleFonts.inter(color: kText2, fontSize: 13, height: 1.5),
            maxLines: 3, overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 16),
      ],

      // ── Rules preview ─────────────────────────────────────────────────────
      if (rules.isNotEmpty) ...[
        const _SectionLabel('RÈGLES ACTIVES'),
        const SizedBox(height: 8),
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(children: rules.take(3).toList().asMap().entries.map((e) =>
            Padding(
              padding: EdgeInsets.only(bottom: e.key < rules.take(3).length - 1 ? 8 : 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(5)),
                  child: Center(child: Text('${e.key + 1}', style: GoogleFonts.inter(color: kAccentMid, fontSize: 10, fontWeight: FontWeight.w700))),
                ),
                const SizedBox(width: 9),
                Expanded(child: Text(e.value, style: GoogleFonts.inter(color: kText2, fontSize: 13, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ).toList()),
        ),
        if (rules.length > 3)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('+ ${rules.length - 3} autre${rules.length - 3 > 1 ? "s" : ""} règle${rules.length - 3 > 1 ? "s" : ""}',
              style: GoogleFonts.inter(color: kMuted2, fontSize: 11.5)),
          ),
      ],
    ]);
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(children: [
        Container(width: 30, height: 30,
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 15, color: color)),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: GoogleFonts.inter(color: kText, fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
    ),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(6), border: Border.all(color: kBorder, width: 0.5)),
    child: Text(label, style: GoogleFonts.inter(color: kMuted, fontSize: 11.5, fontWeight: FontWeight.w500)),
  );
}

class _LinkCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _LinkCard({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(width: 34, height: 34,
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: color)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.inter(color: kText, fontSize: 13.5, fontWeight: FontWeight.w600)),
          Text(subtitle, style: GoogleFonts.inter(color: kMuted2, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        const Icon(Icons.open_in_new, size: 13, color: kMuted2),
      ]),
    ),
  );
}

class _StatCell extends StatelessWidget {
  final String value, label;
  const _StatCell(this.value, this.label);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: GoogleFonts.inter(color: kText, fontSize: 20, fontWeight: FontWeight.w700)),
    const SizedBox(height: 2),
    Text(label, style: GoogleFonts.inter(color: kMuted2, fontSize: 11)),
  ]);
}

class _VSep extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(width: 0.5, height: 30, color: kBorder);
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
    style: GoogleFonts.inter(color: kMuted2, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.7));
}

// ─── Tab 1: Contexte ──────────────────────────────────────────────────────────
class _ContexteTab extends StatefulWidget {
  final String? content;
  final bool loading, saving;
  final Future<void> Function(String) onSave;
  const _ContexteTab({this.content, required this.loading, required this.saving, required this.onSave});
  @override State<_ContexteTab> createState() => _ContexteTabState();
}

class _ContexteTabState extends State<_ContexteTab> {
  bool _editing = false;
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.content ?? '');
  }

  @override
  void didUpdateWidget(covariant _ContexteTab old) {
    super.didUpdateWidget(old);
    if (!_editing && old.content != widget.content) _ctrl.text = widget.content ?? '';
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    await widget.onSave(_ctrl.text.trim());
    if (mounted) setState(() => _editing = false);
  }

  void _cancel() {
    _ctrl.text = widget.content ?? '';
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const AppLoadingIndicator();

    if (_editing) {
      return Column(children: [
        Expanded(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder, width: 0.5)),
            padding: const EdgeInsets.all(14),
            child: TextField(
              controller: _ctrl,
              maxLines: null, expands: true,
              autofocus: true,
              textAlignVertical: TextAlignVertical.top,
              style: GoogleFonts.inter(color: kText, fontSize: 13.5, height: 1.6),
              cursorColor: kAccent, cursorWidth: 1.5,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Décris le projet, ses objectifs, les infos utiles pour les agents…',
                hintStyle: GoogleFonts.inter(color: kMuted2),
              ),
            ),
          ),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(children: [
            Expanded(child: AppButton(
              variant: AppButtonVariant.secondary, label: 'Annuler', fullWidth: true,
              onTap: widget.saving ? null : _cancel,
            )),
            const SizedBox(width: 10),
            Expanded(child: AppButton(
              label: 'Enregistrer', loading: widget.saving, fullWidth: true,
              onTap: widget.saving ? null : _save,
            )),
          ]),
        ),
      ]);
    }

    if (widget.content == null || widget.content!.isEmpty) {
      return Stack(children: [
        const AppEmptyState(
          icon: Icons.info_outline,
          title: 'Aucun contexte défini',
          subtitle: 'Décris ici le projet, ses objectifs et les infos utiles pour les agents.',
        ),
        Positioned(
          right: 16, bottom: 16,
          child: AppButton(label: 'Ajouter un contexte', icon: Icons.add,
            onTap: () => setState(() => _editing = true),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
        ),
      ]);
    }

    return Stack(children: [
      ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
        // Rendered directly on the page — no card/box around it.
        MarkdownBody(data: widget.content!, styleSheet: mdStyleSheet(context), selectable: true),
      ]),
      Positioned(
        right: 16, bottom: 16,
        child: AppButton(label: 'Modifier', icon: Icons.edit_outlined,
          onTap: () => setState(() => _editing = true),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
      ),
    ]);
  }
}

// ─── Tab 6: Mémoire ───────────────────────────────────────────────────────────
/// Shared memory stash for the room ("open memory stash"): free-form notes
/// the AI agent reads before acting and updates after meaningful work, so
/// context survives across sessions without re-explaining everything.
class _MemoireTab extends StatefulWidget {
  final String? content;
  final bool loading, saving;
  final Future<void> Function(String) onSave;
  const _MemoireTab({this.content, required this.loading, required this.saving, required this.onSave});
  @override State<_MemoireTab> createState() => _MemoireTabState();
}

class _MemoireTabState extends State<_MemoireTab> {
  bool _editing = false;
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.content ?? '');
  }

  @override
  void didUpdateWidget(covariant _MemoireTab old) {
    super.didUpdateWidget(old);
    if (!_editing && old.content != widget.content) _ctrl.text = widget.content ?? '';
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    await widget.onSave(_ctrl.text.trim());
    if (mounted) setState(() => _editing = false);
  }

  void _cancel() {
    _ctrl.text = widget.content ?? '';
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const AppLoadingIndicator();

    if (_editing) {
      return Column(children: [
        Expanded(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder, width: 0.5)),
            padding: const EdgeInsets.all(14),
            child: TextField(
              controller: _ctrl,
              maxLines: null, expands: true,
              autofocus: true,
              textAlignVertical: TextAlignVertical.top,
              style: GoogleFonts.inter(color: kText, fontSize: 13.5, height: 1.6),
              cursorColor: kAccent, cursorWidth: 1.5,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Notes partagées avec l\'agent : décisions prises, état courant, points à retenir…',
                hintStyle: GoogleFonts.inter(color: kMuted2),
              ),
            ),
          ),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(children: [
            Expanded(child: AppButton(
              variant: AppButtonVariant.secondary, label: 'Annuler', fullWidth: true,
              onTap: widget.saving ? null : _cancel,
            )),
            const SizedBox(width: 10),
            Expanded(child: AppButton(
              label: 'Enregistrer', loading: widget.saving, fullWidth: true,
              onTap: widget.saving ? null : _save,
            )),
          ]),
        ),
      ]);
    }

    if (widget.content == null || widget.content!.isEmpty) {
      return Stack(children: [
        const AppEmptyState(
          icon: Icons.psychology_outlined,
          title: 'Aucune mémoire partagée',
          subtitle: 'L\'agent lit et met à jour ces notes entre les sessions — état courant, décisions, contexte utile.',
        ),
        Positioned(
          right: 16, bottom: 16,
          child: AppButton(label: 'Ajouter des notes', icon: Icons.add,
            onTap: () => setState(() => _editing = true),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
        ),
      ]);
    }

    return Stack(children: [
      ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
        MarkdownBody(data: widget.content!, styleSheet: mdStyleSheet(context), selectable: true),
      ]),
      Positioned(
        right: 16, bottom: 16,
        child: AppButton(label: 'Modifier', icon: Icons.edit_outlined,
          onTap: () => setState(() => _editing = true),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
      ),
    ]);
  }
}

// ─── Tab 2: Règles ────────────────────────────────────────────────────────────
class _ReglesTab extends StatefulWidget {
  final List<String> rules;
  final bool loading, saving, dirty;
  final ValueChanged<String> onAdd;
  final void Function(int, String) onEdit;
  final ValueChanged<int> onDelete;
  final VoidCallback onSave;
  const _ReglesTab({
    required this.rules, required this.loading, required this.saving, required this.dirty,
    required this.onAdd, required this.onEdit, required this.onDelete, required this.onSave,
  });
  @override State<_ReglesTab> createState() => _ReglesTabState();
}

class _ReglesTabState extends State<_ReglesTab> {
  int? _editing;
  final _ctrl = TextEditingController();
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  void _startEdit(int i) => setState(() { _editing = i; _ctrl.text = widget.rules[i]; });
  void _confirmEdit() {
    if (_editing == null) return;
    final t = _ctrl.text.trim();
    if (t.isNotEmpty) widget.onEdit(_editing!, t);
    setState(() => _editing = null);
    _ctrl.clear();
  }

  // Watchtower preset rules
  static const _kWatchtowerRules = [
    'Cloner le repo dans un dossier racine portant le nom exact du dépôt (ex: git clone ... → /repo-name/)',
    'Coder proprement : code lisible, nommage explicite, pas de duplication inutile, respect des conventions du projet',
    'Toujours push le contenu du dossier, jamais le dossier lui-même (push src/, pas push/src)',
  ];

  void _loadWatchtowerRules() {
    for (final r in _kWatchtowerRules) {
      if (!widget.rules.contains(r)) widget.onAdd(r);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const AppLoadingIndicator();
    return Column(children: [
      if (widget.dirty)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: kYellow.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: kYellow.withOpacity(0.25), width: 0.5)),
          child: Row(children: [
            const Icon(Icons.edit_note, size: 14, color: kYellow),
            const SizedBox(width: 8),
            Expanded(child: Text('Modifications non sauvegardées', style: GoogleFonts.inter(color: kYellow, fontSize: 12.5))),
            AppButton(label: 'Sauvegarder', loading: widget.saving, onTap: widget.saving ? null : widget.onSave, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
          ]),
        ),
      // Watchtower preset button
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: GestureDetector(
          onTap: _loadWatchtowerRules,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(8), border: Border.all(color: kAccent.withOpacity(0.3), width: 0.5)),
            child: Row(children: [
              const Icon(Icons.auto_fix_high_rounded, size: 14, color: kAccentMid),
              const SizedBox(width: 8),
              Expanded(child: Text('Charger règles Watchtower', style: GoogleFonts.inter(color: kAccentMid, fontSize: 13, fontWeight: FontWeight.w600))),
              const Icon(Icons.chevron_right_rounded, size: 14, color: kAccentMid),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Expanded(
        child: widget.rules.isEmpty
            ? const AppEmptyState(icon: Icons.rule_outlined, title: 'Aucune règle', subtitle: 'Ajoute ta première règle ci-dessous')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                itemCount: widget.rules.length,
                itemBuilder: (_, i) {
                  if (_editing == i) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: kAccent.withOpacity(0.5), width: 1)),
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        TextField(
                          controller: _ctrl, autofocus: true, maxLines: null,
                          style: GoogleFonts.inter(color: kText, fontSize: 13.5),
                          cursorColor: kAccent, cursorWidth: 1.5,
                          decoration: InputDecoration(border: InputBorder.none, hintText: 'Contenu de la règle…', hintStyle: GoogleFonts.inter(color: kMuted2), contentPadding: EdgeInsets.zero, isDense: true),
                        ),
                        const SizedBox(height: 10),
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          AppButton(label: 'Annuler', variant: AppButtonVariant.ghost, onTap: () => setState(() { _editing = null; _ctrl.clear(); }), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                          const SizedBox(width: 8),
                          AppButton(label: 'Confirmer', onTap: _confirmEdit, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                        ]),
                      ]),
                    );
                  }
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder, width: 0.5)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      leading: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(7)),
                        child: Center(child: Text('${i + 1}', style: GoogleFonts.inter(color: kAccentMid, fontSize: 11, fontWeight: FontWeight.w700))),
                      ),
                      title: Text(widget.rules[i], style: GoogleFonts.inter(color: kText2, fontSize: 13.5, height: 1.5)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        GestureDetector(onTap: () => _startEdit(i), child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.edit_outlined, size: 15, color: kMuted2))),
                        GestureDetector(onTap: () => widget.onDelete(i), child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.delete_outline, size: 15, color: kRed))),
                      ]),
                    ),
                  );
                },
              ),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: _AddRuleBar(onAdd: widget.onAdd)),
    ]);
  }
}

class _AddRuleBar extends StatefulWidget {
  final ValueChanged<String> onAdd;
  const _AddRuleBar({required this.onAdd});
  @override State<_AddRuleBar> createState() => _AddRuleBarState();
}

class _AddRuleBarState extends State<_AddRuleBar> {
  final _c = TextEditingController();
  @override void dispose() { _c.dispose(); super.dispose(); }
  void _submit() { final t = _c.text.trim(); if (t.isNotEmpty) { widget.onAdd(t); _c.clear(); } }

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
    Expanded(child: Container(
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(22), border: Border.all(color: kBorder, width: 0.5)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: TextField(
        controller: _c, maxLines: 1, onSubmitted: (_) => _submit(),
        style: GoogleFonts.inter(color: kText, fontSize: 13.5), cursorColor: kAccent, cursorWidth: 1.5,
        decoration: InputDecoration(border: InputBorder.none, hintText: 'Nouvelle règle…', hintStyle: GoogleFonts.inter(color: kMuted2), contentPadding: EdgeInsets.zero, isDense: true),
      ),
    )),
    const SizedBox(width: 8),
    GestureDetector(
      onTap: _submit,
      child: Container(
        width: 40, height: 40,
        decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
        child: const Icon(Icons.arrow_upward_rounded, size: 18, color: Colors.white),
      ),
    ),
  ]);
}

// ─── Tab 3: Chat ──────────────────────────────────────────────────────────────
class _ChatTab extends StatefulWidget {
  final Room room;
  final List<ChatMessage> messages;
  final bool loading;
  final GitHubService github;
  final ValueChanged<ChatMessage> onSent;
  final void Function(String, Color) onSnack;
  const _ChatTab({required this.room, required this.messages, required this.loading,
      required this.github, required this.onSent, required this.onSnack});
  @override State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  String? _agentName;
  bool _nameLoaded = false;
  Timer? _pollTimer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _loadAgentName();
    // Poll for new messages every 12 seconds for real-time feel
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) => _pollMessages());
  }

  @override void dispose() {
    _pollTimer?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pollMessages() async {
    if (_polling || !mounted) return;
    _polling = true;
    try {
      final newMsgs = await widget.github.fetchMessages(widget.room.id);
      if (!mounted) return;
      if (newMsgs.length != widget.messages.length) {
        // New messages arrived — scroll to bottom
        setState(() {});
        await Future.delayed(const Duration(milliseconds: 100));
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      }
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  Future<void> _loadAgentName() async {
    final saved = await PrefsService.getString('agent_name_${widget.room.id}');
    if (mounted) setState(() { _agentName = saved; _nameLoaded = true; });
  }

  Future<void> _pickAgentName() async {
    final usedNames = widget.messages.where((m) => !m.isUser).map((m) => m.sender.toLowerCase()).toSet();
    final ctrl = TextEditingController(text: _agentName ?? '');
    String? error;

    final chosen = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: kCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: kBorder, width: 0.5)),
          title: Text('Choisir ton nom d\'agent', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ton nom doit être unique dans cette room.', style: GoogleFonts.inter(color: kMuted2, fontSize: 12.5)),
            const SizedBox(height: 12),
            AppInput(
              controller: ctrl,
              hint: 'Ex: AlphaAgent, Dev-42…',
              autofocus: true,
              onChanged: (v) => setS(() => error = null),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: GoogleFonts.inter(color: kRed, fontSize: 12)),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Annuler', style: GoogleFonts.inter(color: kMuted))),
            AppButton(
              label: 'Confirmer',
              onTap: () {
                final name = ctrl.text.trim();
                if (name.isEmpty) { setS(() => error = 'Le nom ne peut pas être vide'); return; }
                if (name.length < 2) { setS(() => error = 'Minimum 2 caractères'); return; }
                if (usedNames.contains(name.toLowerCase()) && name.toLowerCase() != (_agentName?.toLowerCase() ?? '')) {
                  setS(() => error = 'Ce nom est déjà utilisé par un autre agent'); return;
                }
                Navigator.pop(ctx, name);
              },
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (chosen != null && chosen.isNotEmpty) {
      await PrefsService.setString('agent_name_${widget.room.id}', chosen);
      if (mounted) setState(() => _agentName = chosen);
    }
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    if (_agentName == null || _agentName!.isEmpty) { await _pickAgentName(); return; }
    if (!widget.github.hasPat) { widget.onSnack('Token requis', kYellow); return; }
    setState(() => _sending = true);
    try {
      await widget.github.pushMessage(widget.room.id, t, sender: _agentName!);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final msg = ChatMessage(id: 'chat-$ts.md', sender: _agentName!, content: t, isUser: true, createdAt: DateTime.fromMillisecondsSinceEpoch(ts));
      _ctrl.clear();
      widget.onSent(msg);
      if (mounted) {
        setState(() => _sending = false);
        await Future.delayed(const Duration(milliseconds: 100));
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    } catch (e) {
      if (mounted) { setState(() => _sending = false); widget.onSnack('Erreur: $e', kRed); }
    }
  }

  String _fmt(DateTime? d) {
    if (d == null) return '';
    return '${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading || !_nameLoaded) return const AppLoadingIndicator();
    final accent = widget.room.accentColor;
    return Column(children: [
      // Name banner
      if (_agentName != null)
        GestureDetector(
          onTap: _pickAgentName,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(color: kCard, border: Border(bottom: BorderSide(color: kBorder, width: 0.5))),
            child: Row(children: [
              Container(width: 22, height: 22, decoration: BoxDecoration(color: accent.withOpacity(0.15), shape: BoxShape.circle),
                child: Center(child: Text(_agentName![0].toUpperCase(), style: GoogleFonts.inter(color: accent, fontSize: 10, fontWeight: FontWeight.w700)))),
              const SizedBox(width: 8),
              Text('Connecté en tant que ', style: GoogleFonts.inter(color: kMuted2, fontSize: 12)),
              Text(_agentName!, style: GoogleFonts.inter(color: kText, fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('Changer', style: GoogleFonts.inter(color: kAccentMid, fontSize: 11.5)),
            ]),
          ),
        ),
      Expanded(child: widget.messages.isEmpty
          ? _buildEmpty()
          : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              itemCount: widget.messages.length,
              itemBuilder: (_, i) {
                final m = widget.messages[i];
                final isMe = m.sender.toLowerCase() == (_agentName?.toLowerCase() ?? '');
                // No bubble/box — the message content sits directly on the
                // page background, just indented by sender side.
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                    margin: const EdgeInsets.only(bottom: 14),
                    child: Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 2, right: 2, bottom: 3),
                        child: Text(isMe ? 'Toi' : m.sender, style: GoogleFonts.inter(color: accent, fontSize: 10.5, fontWeight: FontWeight.w600)),
                      ),
                      MarkdownBody(
                        data: m.content,
                        selectable: true,
                        styleSheet: mdStyleSheet(context).copyWith(
                          p: GoogleFonts.inter(color: kText2, fontSize: 13.5, height: 1.4),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 3, left: 2, right: 2),
                        child: Text(_fmt(m.createdAt), style: GoogleFonts.inter(color: kMuted2, fontSize: 10)),
                      ),
                    ]),
                  ),
                );
              })),
      Container(
        decoration: const BoxDecoration(color: kBg, border: Border(top: BorderSide(color: kBorder, width: 0.5))),
        padding: EdgeInsets.only(left: 14, right: 14, top: 8, bottom: MediaQuery.of(context).padding.bottom + 8),
        child: Row(children: [
          Expanded(child: Container(
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(22), border: Border.all(color: kBorder, width: 0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: TextField(
              controller: _ctrl, maxLines: 4, minLines: 1,
              onSubmitted: (_) => _send(),
              style: GoogleFonts.inter(color: kText, fontSize: 13.5),
              cursorColor: kAccent, cursorWidth: 1.5,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: _agentName == null ? 'Choisir un nom pour commencer…' : 'Envoyer un message…',
                hintStyle: GoogleFonts.inter(color: kMuted2),
                contentPadding: EdgeInsets.zero, isDense: true,
              ),
            ),
          )),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : (_agentName == null ? _pickAgentName : _send),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: _agentName == null ? kCard2 : accent, shape: BoxShape.circle),
              child: _sending
                  ? const Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5)))
                  : Icon(_agentName == null ? Icons.person_outline : Icons.send_rounded, size: 18, color: _agentName == null ? kMuted2 : Colors.white),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildEmpty() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 56, height: 56, decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
      child: const Icon(Icons.chat_bubble_outline, size: 24, color: kMuted2)),
    const SizedBox(height: 14),
    Text('Aucun message', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600)),
    const SizedBox(height: 4),
    Text(_agentName == null ? 'Choisir un nom pour participer au chat' : 'Les agents peuvent discuter ici',
      style: GoogleFonts.inter(color: kMuted2, fontSize: 13), textAlign: TextAlign.center),
    if (_agentName == null) ...[
      const SizedBox(height: 16),
      AppButton(label: 'Choisir mon nom', icon: Icons.person_outlined, onTap: _pickAgentName,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
    ],
  ]));
}

// ─── Tab 4: Transcription ─────────────────────────────────────────────────────
class _TranscriptionTab extends StatefulWidget {
  final Room room;
  final List<TranscriptEntry> transcripts;
  final bool loading;
  final GitHubService github;
  final ValueChanged<TranscriptEntry> onSent;
  final void Function(String, Color) onSnack;
  const _TranscriptionTab({required this.room, required this.transcripts, required this.loading,
      required this.github, required this.onSent, required this.onSnack});
  @override State<_TranscriptionTab> createState() => _TranscriptionTabState();
}

class _TranscriptionTabState extends State<_TranscriptionTab> {
  bool _composing = false;

  void _openCompose() => setState(() => _composing = true);

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const AppLoadingIndicator();
    if (_composing) {
      return _ComposeTranscript(
        room: widget.room,
        github: widget.github,
        onDone: (entry) {
          widget.onSent(entry);
          setState(() => _composing = false);
        },
        onCancel: () => setState(() => _composing = false),
        onSnack: widget.onSnack,
      );
    }
    return Stack(children: [
      widget.transcripts.isEmpty
          ? const AppEmptyState(
              icon: Icons.description_outlined,
              title: 'Aucune transcription',
              subtitle: 'Chaque agent documente les demandes et ce qui a été fait.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: widget.transcripts.length,
              itemBuilder: (_, i) => _TranscriptCard(entry: widget.transcripts[i]),
            ),
      Positioned(
        right: 16, bottom: 16,
        child: AppButton(
          label: 'Nouvelle transcription',
          icon: Icons.add,
          onTap: _openCompose,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
    ]);
  }
}

class _ComposeTranscript extends StatefulWidget {
  final Room room;
  final GitHubService github;
  final ValueChanged<TranscriptEntry> onDone;
  final VoidCallback onCancel;
  final void Function(String, Color) onSnack;
  const _ComposeTranscript({required this.room, required this.github, required this.onDone, required this.onCancel, required this.onSnack});
  @override State<_ComposeTranscript> createState() => _ComposeTranscriptState();
}

class _ComposeTranscriptState extends State<_ComposeTranscript> {
  final _nameCtrl = TextEditingController();
  final _requestCtrl = TextEditingController();
  final _actionsCtrl = TextEditingController();
  bool _saving = false;

  @override void initState() {
    super.initState();
    PrefsService.getString('agent_name_${widget.room.id}').then((n) {
      if (mounted && n != null) setState(() => _nameCtrl.text = n);
    });
  }
  @override void dispose() { _nameCtrl.dispose(); _requestCtrl.dispose(); _actionsCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) { widget.onSnack('Nom d\'agent requis', kYellow); return; }
    if (_requestCtrl.text.trim().isEmpty) { widget.onSnack('Demande utilisateur requise', kYellow); return; }
    if (!widget.github.hasPat) { widget.onSnack('Token GitHub requis', kYellow); return; }
    setState(() => _saving = true);
    try {
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      final entry = TranscriptEntry(id: ts, agentName: _nameCtrl.text.trim(),
          userRequest: _requestCtrl.text.trim(), actionsDone: _actionsCtrl.text.trim());
      await widget.github.pushTranscript(widget.room.id, entry);
      await PrefsService.setString('agent_name_${widget.room.id}', entry.agentName);
      widget.onDone(entry);
    } catch (e) {
      if (mounted) { setState(() => _saving = false); widget.onSnack('Erreur: $e', kRed); }
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBorder, width: 0.5))),
      child: Row(children: [
        GestureDetector(onTap: widget.onCancel, child: const Icon(Icons.close, size: 18, color: kMuted)),
        const SizedBox(width: 12),
        Text('Nouvelle transcription', style: GoogleFonts.inter(color: kText, fontSize: 14, fontWeight: FontWeight.w600)),
        const Spacer(),
        AppButton(label: 'Publier', loading: _saving, onTap: _saving ? null : _submit, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
      ]),
    ),
    Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
      const AppLabel('Nom de l\'agent'),
      const SizedBox(height: 6),
      AppInput(controller: _nameCtrl, hint: 'Ex: AlphaAgent'),
      const SizedBox(height: 16),
      const AppLabel('Demande utilisateur'),
      const SizedBox(height: 6),
      AppInput(controller: _requestCtrl, hint: 'Ce que le user a demandé…', maxLines: 5),
      const SizedBox(height: 16),
      const AppLabel('Actions effectuées'),
      const SizedBox(height: 6),
      AppInput(controller: _actionsCtrl, hint: 'Ce qui a été fait, les fichiers modifiés…', maxLines: 6),
      const SizedBox(height: 24),
      AppCard(
        color: kAccentSub.withOpacity(0.3),
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, size: 13, color: kAccentMid),
          const SizedBox(width: 8),
          Expanded(child: Text('La transcription sera publiée en Markdown dans rooms/${widget.room.id}/ sur GitHub.',
            style: GoogleFonts.inter(color: kMuted2, fontSize: 12, height: 1.45))),
        ]),
      ),
    ])),
  ]);
}

class _TranscriptCard extends StatelessWidget {
  final TranscriptEntry entry;
  const _TranscriptCard({required this.entry});

  String _fmt(DateTime d) {
    return '${d.day.toString().padLeft(2,"0")}/${d.month.toString().padLeft(2,"0")} ${d.hour.toString().padLeft(2,"0")}:${d.minute.toString().padLeft(2,"0")}';
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Row(children: [
          Container(width: 30, height: 30, decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text(entry.agentName.isNotEmpty ? entry.agentName[0].toUpperCase() : 'A',
              style: GoogleFonts.inter(color: kAccentMid, fontSize: 12, fontWeight: FontWeight.w700)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry.agentName, style: GoogleFonts.inter(color: kText, fontSize: 13.5, fontWeight: FontWeight.w600)),
            Text(_fmt(entry.createdAt), style: GoogleFonts.inter(color: kMuted2, fontSize: 11)),
          ])),
        ]),
      ),
      const Divider(height: 1, color: kBorder),
      // User request
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('DEMANDE', style: GoogleFonts.inter(color: kMuted2, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: 4),
          Text(entry.userRequest, style: GoogleFonts.inter(color: kText2, fontSize: 13, height: 1.4), maxLines: 3, overflow: TextOverflow.ellipsis),
        ]),
      ),
      if (entry.actionsDone.isNotEmpty) ...[
        const Divider(height: 1, color: kBorder, indent: 14, endIndent: 14),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ACTIONS', style: GoogleFonts.inter(color: kMuted2, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            const SizedBox(height: 4),
            Text(entry.actionsDone, style: GoogleFonts.inter(color: kText2, fontSize: 13, height: 1.4), maxLines: 4, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ] else const SizedBox(height: 12),
    ]),
  );
}

// ─── Tab 5: Prompts ───────────────────────────────────────────────────────────
class _LocalPrompt {
  final String id, name, text, status;
  final DateTime? createdAt;
  const _LocalPrompt({required this.id, required this.name, required this.text, required this.status, this.createdAt});
  _LocalPrompt copyWith({String? status}) => _LocalPrompt(id: id, name: name, text: text, status: status ?? this.status, createdAt: createdAt);
}

class _PromptTab extends StatefulWidget {
  final Room room;
  final List<_LocalPrompt> prompts;
  final bool loading;
  final GitHubService github;
  final ValueChanged<_LocalPrompt> onSent;
  final void Function(int, String) onStatusChanged;
  final void Function(String, Color) onSnack;
  const _PromptTab({required this.room, required this.prompts, required this.loading,
      required this.github, required this.onSent, required this.onStatusChanged, required this.onSnack});
  @override State<_PromptTab> createState() => _PromptTabState();
}

class _PromptTabState extends State<_PromptTab> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  List<AttachedFile> _files = [];
  String _filter = 'all';

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  List<_LocalPrompt> get _filtered {
    if (_filter == 'all') return widget.prompts;
    return widget.prompts.where((p) => p.status == _filter).toList();
  }

  Future<void> _pickFiles() async {
    try {
      final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true, type: FileType.any);
      if (res == null) return;
      setState(() {
        for (final f in res.files) {
          if (f.bytes != null) {
            final n = f.name.toLowerCase();
            _files.insert(0, AttachedFile(name: f.name, bytes: f.bytes!,
              isImage: n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.gif') || n.endsWith('.webp')));
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _pickFromGallery() async {
    try {
      final imgs = await ImagePicker().pickMultiImage(imageQuality: 90);
      for (int i = 0; i < imgs.length; i++) {
        final bytes = await imgs[i].readAsBytes();
        final name = imgs[i].name.isNotEmpty ? imgs[i].name : 'photo_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final n = name.toLowerCase();
        if (mounted) setState(() => _files.insert(0, AttachedFile(name: name, bytes: bytes,
          isImage: n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.gif') || n.endsWith('.webp'))));
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty && _files.isEmpty) return;
    if (!widget.github.hasPat) { widget.onSnack('Token GitHub requis', kYellow); return; }
    setState(() => _sending = true);
    try {
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      final name = words.take(8).join(' ');
      final filesCopy = List<AttachedFile>.from(_files);
      final prompt = AgentPrompt(
        id: ts, number: widget.prompts.length + 1, roomId: widget.room.id,
        text: t, status: 'pending', name: name, createdAt: DateTime.now(),
        attachments: filesCopy.map((f) => PromptAttachment(type: f.isImage ? 'image' : 'file', name: f.name, path: '', sizeBytes: f.bytes.length)).toList(),
      );
      await widget.github.pushPrompt(widget.room.id, prompt);
      final lp = _LocalPrompt(id: ts, name: name, text: t, status: 'pending', createdAt: prompt.createdAt);
      _ctrl.clear(); setState(() { _files = []; _sending = false; });
      widget.onSent(lp);
      widget.onSnack('Prompt ajouté', kGreen);
    } catch (e) {
      if (mounted) { setState(() => _sending = false); widget.onSnack('Erreur: $e', kRed); }
    }
  }

  Future<void> _changeStatus(int idx, _LocalPrompt p) async {
    final statuses = [
      ('pending', 'En attente', kMuted2),
      ('in_progress', 'En cours', kYellow),
      ('done', 'Exécuté', kGreen),
    ];
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: kBorder, width: 0.5)),
        title: Text('Changer le statut', style: GoogleFonts.inter(color: kText, fontSize: 14, fontWeight: FontWeight.w600)),
        content: Column(mainAxisSize: MainAxisSize.min, children: statuses.map((s) =>
          GestureDetector(
            onTap: () => Navigator.pop(ctx, s.$1),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: p.status == s.$1 ? s.$3.withOpacity(0.08) : kBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.status == s.$1 ? s.$3.withOpacity(0.4) : kBorder, width: 0.5),
              ),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Text(s.$2, style: GoogleFonts.inter(color: kText, fontSize: 13.5)),
                const Spacer(),
                if (p.status == s.$1) const Icon(Icons.check, size: 14, color: kGreen),
              ]),
            ),
          ),
        ).toList()),
      ),
    );
    if (chosen != null && chosen != p.status) {
      widget.onStatusChanged(widget.prompts.indexOf(p), chosen);
      try {
        final full = AgentPrompt(id: p.id, number: 0, roomId: widget.room.id, text: p.text, status: chosen, name: p.name, createdAt: p.createdAt);
        await widget.github.updatePromptStatus(widget.room.id, full, chosen);
      } catch (e) { widget.onSnack('Statut non sauvegardé: $e', kYellow); }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const AppLoadingIndicator();
    final filtered = _filtered;
    return Column(children: [
      // Filter row
      Container(
        height: 44,
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBorder, width: 0.5))),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          children: [
            _FilterChip(label: 'Tous', count: widget.prompts.length, selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
            _FilterChip(label: 'En attente', count: widget.prompts.where((p) => p.status == 'pending').length, selected: _filter == 'pending', color: kMuted2, onTap: () => setState(() => _filter = 'pending')),
            _FilterChip(label: 'En cours', count: widget.prompts.where((p) => p.status == 'in_progress').length, selected: _filter == 'in_progress', color: kYellow, onTap: () => setState(() => _filter = 'in_progress')),
            _FilterChip(label: 'Exécuté', count: widget.prompts.where((p) => p.status == 'done').length, selected: _filter == 'done', color: kGreen, onTap: () => setState(() => _filter = 'done')),
          ],
        ),
      ),
      Expanded(child: filtered.isEmpty
          ? AppEmptyState(icon: Icons.article_outlined, title: _filter == 'all' ? 'Aucun prompt' : 'Aucun prompt dans cette catégorie', subtitle: 'Compose un prompt ci-dessous')
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              itemCount: filtered.length,
              itemBuilder: (_, i) => _PromptCard(
                prompt: filtered[i],
                onStatusTap: () => _changeStatus(widget.prompts.indexOf(filtered[i]), filtered[i]),
              ),
            )),
      // Input
      Container(
        decoration: const BoxDecoration(color: kBg, border: Border(top: BorderSide(color: kBorder, width: 0.5))),
        padding: EdgeInsets.only(left: 14, right: 14, top: 8, bottom: MediaQuery.of(context).padding.bottom + 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_files.isNotEmpty)
            SizedBox(
              height: 54,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _files.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_files[i].isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined, size: 14, color: kMuted2),
                    const SizedBox(width: 6),
                    Text(_files[i].name, style: GoogleFonts.inter(color: kText2, fontSize: 12), maxLines: 1),
                    const SizedBox(width: 6),
                    GestureDetector(onTap: () => setState(() => _files.removeAt(i)), child: const Icon(Icons.close, size: 13, color: kMuted2)),
                  ]),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Row(children: [
            GestureDetector(
              onTap: () => showModalBottomSheet(
                context: context, backgroundColor: kCard,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                builder: (_) => SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const AppDragHandle(),
                  ListTile(leading: const Icon(Icons.folder_outlined, color: kMuted2), title: Text('Fichiers', style: GoogleFonts.inter(color: kText, fontSize: 14)),
                    onTap: () { Navigator.pop(context); _pickFiles(); }),
                  ListTile(leading: const Icon(Icons.photo_library_outlined, color: kMuted2), title: Text('Galerie', style: GoogleFonts.inter(color: kText, fontSize: 14)),
                    onTap: () { Navigator.pop(context); _pickFromGallery(); }),
                  const SizedBox(height: 8),
                ])),
              ),
              child: Container(width: 36, height: 36, decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(9), border: Border.all(color: kBorder, width: 0.5)),
                child: const Icon(Icons.attach_file_rounded, size: 16, color: kMuted2)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Container(
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder, width: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: TextField(
                controller: _ctrl, maxLines: 3, minLines: 1,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.inter(color: kText, fontSize: 13.5), cursorColor: kAccent, cursorWidth: 1.5,
                decoration: InputDecoration(border: InputBorder.none, hintText: 'Nouveau prompt…', hintStyle: GoogleFonts.inter(color: kMuted2), contentPadding: EdgeInsets.zero, isDense: true),
              ),
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: (_ctrl.text.trim().isNotEmpty || _files.isNotEmpty) && !_sending ? _send : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: (_ctrl.text.trim().isNotEmpty || _files.isNotEmpty) && !_sending ? kAccent : kCard2,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: _sending
                    ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5))
                    : Icon(Icons.arrow_upward_rounded, size: 17, color: (_ctrl.text.trim().isNotEmpty || _files.isNotEmpty) && !_sending ? Colors.white : kMuted2),
              ),
            ),
          ]),
        ]),
      ),
    ]);
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.count, required this.selected, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = color ?? kAccentMid;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? c.withOpacity(0.12) : kBg,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: selected ? c.withOpacity(0.5) : kBorder, width: 0.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: GoogleFonts.inter(color: selected ? c : kMuted2, fontSize: 12.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
          if (count > 0) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: selected ? c.withOpacity(0.2) : kCard2, borderRadius: BorderRadius.circular(4)),
              child: Text('$count', style: GoogleFonts.inter(color: selected ? c : kMuted2, fontSize: 10.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  final _LocalPrompt prompt;
  final VoidCallback onStatusTap;
  const _PromptCard({required this.prompt, required this.onStatusTap});

  (String, Color) get _statusInfo {
    switch (prompt.status) {
      case 'in_progress': return ('En cours', kYellow);
      case 'done': return ('Exécuté', kGreen);
      default: return ('En attente', kMuted2);
    }
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '';
    return '${d.day.toString().padLeft(2,"0")}/${d.month.toString().padLeft(2,"0")}';
  }

  @override
  Widget build(BuildContext context) {
    final (label, color) = _statusInfo;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder, width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (prompt.name.isNotEmpty)
                Text(prompt.name, style: GoogleFonts.inter(color: kText, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3)),
              const SizedBox(height: 4),
              Text(prompt.text, style: GoogleFonts.inter(color: kMuted2, fontSize: 12.5, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onStatusTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withOpacity(0.3), width: 0.5)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(label, style: GoogleFonts.inter(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Text(_fmtDate(prompt.createdAt), style: GoogleFonts.inter(color: kMuted2, fontSize: 11)),
        ),
      ]),
    );
  }
}

