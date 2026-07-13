import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/saved_prompt.dart';
import '../services/github_service.dart';
import '../theme.dart';
import '../widgets/app_components.dart';

class PromptHistoryScreen extends StatefulWidget {
  final SavedPrompt prompt;
  final GitHubService github;
  const PromptHistoryScreen({super.key, required this.prompt, required this.github});

  @override
  State<PromptHistoryScreen> createState() => _PromptHistoryScreenState();
}

class _PromptHistoryScreenState extends State<PromptHistoryScreen> {
  List<Map<String, dynamic>> _commits = [];
  bool _loading = true;
  String? _error;
  String? _viewingSha;
  String? _viewingContent;
  bool _loadingContent = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final history = await widget.github.fetchPromptHistory(widget.prompt.id);
      if (mounted) setState(() { _commits = history; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _viewVersion(Map<String, dynamic> commit) async {
    final sha = commit['sha'] as String;
    if (_viewingSha == sha) { setState(() { _viewingSha = null; _viewingContent = null; }); return; }
    setState(() { _viewingSha = sha; _loadingContent = true; _viewingContent = null; });
    try {
      final content = await widget.github.fetchPromptContentAtCommit(widget.prompt.id, commit['fullSha'] as String? ?? sha);
      if (mounted) setState(() { _viewingContent = content; _loadingContent = false; });
    } catch (_) {
      if (mounted) setState(() { _loadingContent = false; _viewingContent = '_(contenu non disponible)_'; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBg,
    body: SafeArea(
      bottom: false,
      child: Column(children: [
        _buildHeader(),
        Expanded(child: _loading
          ? const Center(child: AppLoadingIndicator())
          : _error != null
            ? AppEmptyState(icon: Icons.cloud_off, title: 'Erreur', subtitle: _error!)
            : _commits.isEmpty
              ? const AppEmptyState(icon: Icons.history, title: 'Aucun historique', subtitle: 'Ce prompt n\'a pas encore de commits')
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _commits.length,
                  itemBuilder: (_, i) => _buildCommitCard(_commits[i], i),
                ),
        ),
      ]),
    ),
  );

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBorder, width: 0.5))),
    child: Row(children: [
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(width: 34, height: 34,
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
          child: const Icon(Icons.arrow_back_ios_new, size: 13, color: kMuted)),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Historique', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        Text(widget.prompt.name, style: GoogleFonts.inter(color: kMuted2, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
      ])),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(6)),
        child: Text('${_commits.length} version${_commits.length > 1 ? "s" : ""}',
          style: GoogleFonts.inter(color: kAccentMid, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ),
    ]),
  );

  Widget _buildCommitCard(Map<String, dynamic> commit, int index) {
    final sha = commit['sha'] as String;
    final message = commit['message'] as String;
    final date = commit['date'] as String;
    final author = commit['author'] as String;
    final isOpen = _viewingSha == sha;
    final isFirst = index == 0;

    DateTime? parsedDate;
    try { parsedDate = DateTime.parse(date); } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isOpen ? kCard2 : kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isOpen ? kAccent.withOpacity(0.3) : kBorder, width: isOpen ? 1 : 0.5),
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () => _viewVersion(commit),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: isFirst ? kAccentSub : kCard2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Icon(
                  isFirst ? Icons.radio_button_checked : Icons.history,
                  size: 16, color: isFirst ? kAccentMid : kMuted2,
                )),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (isFirst) Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(4)),
                    child: Text('Actuelle', style: GoogleFonts.inter(color: kAccentMid, fontSize: 9.5, fontWeight: FontWeight.w700)),
                  ),
                  Expanded(child: Text(
                    message.split('\n').first,
                    style: GoogleFonts.inter(color: kText, fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  )),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(4)),
                    child: Text(sha.substring(0, 7), style: GoogleFonts.robotoMono(color: kMuted, fontSize: 10)),
                  ),
                  const SizedBox(width: 6),
                  Text(author, style: GoogleFonts.inter(color: kMuted2, fontSize: 11)),
                  const Spacer(),
                  Text(parsedDate != null ? _fmtDate(parsedDate) : date.substring(0, 10),
                    style: GoogleFonts.inter(color: kMuted2, fontSize: 11)),
                ]),
              ])),
              const SizedBox(width: 8),
              Icon(isOpen ? Icons.expand_less : Icons.expand_more, size: 16, color: kMuted2),
            ]),
          ),
        ),
        if (isOpen) ...[
          const Divider(color: kBorder, height: 1, thickness: 0.5),
          if (_loadingContent)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: AppLoadingIndicator()))
          else if (_viewingContent != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('Contenu à cette version', style: GoogleFonts.inter(color: kMuted2, fontSize: 11.5))),
                  GestureDetector(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: _viewingContent!));
                      if (context.mounted) showAppSnack(context, 'Contenu copié');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(6), border: Border.all(color: kBorder, width: 0.5)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.copy, size: 12, color: kMuted),
                        const SizedBox(width: 4),
                        Text('Copier', style: GoogleFonts.inter(color: kMuted, fontSize: 11.5)),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
                  child: SelectableText(_viewingContent!,
                    style: GoogleFonts.robotoMono(color: kText2, fontSize: 11.5, height: 1.6)),
                ),
              ]),
            ),
        ],
      ]),
    );
  }

  String _fmtDate(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays == 0) return 'Aujourd\'hui';
    if (diff.inDays == 1) return 'Hier';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays}j';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}
