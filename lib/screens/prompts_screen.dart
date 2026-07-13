import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../models/saved_prompt.dart';
import '../services/github_service.dart';
import '../services/prefs_service.dart';
import '../theme.dart';
import '../widgets/app_components.dart';
import 'prompt_detail_screen.dart';
import 'prompt_history_screen.dart';

class PromptsScreen extends StatefulWidget {
  final GitHubService github;
  const PromptsScreen({super.key, required this.github});

  @override
  State<PromptsScreen> createState() => _PromptsScreenState();
}

enum _SortMode { newest, oldest }
enum _DateFilter { all, today, week, month }

class _PromptsScreenState extends State<PromptsScreen> {
  final _searchCtrl = TextEditingController();
  _SortMode _sort = _SortMode.newest;
  _DateFilter _dateFilter = _DateFilter.all;
  bool _syncing = false;
  bool _loading = true;
  List<SavedPrompt> _local = [];
  bool _showFavoritesOnly = false;
  bool _showArchived = false;
  String? _tagFilter;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _loadFromPrefs();
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _loadFromPrefs() async {
    final list = await PrefsService.getPrompts();
    if (mounted) setState(() { _local = list; _loading = false; });
  }

  // ── All unique tags from local prompts ────────────────────────────────────
  List<String> get _allTags {
    final set = <String>{};
    for (final p in _local) set.addAll(p.tags);
    final list = set.toList()..sort();
    return list;
  }

  List<SavedPrompt> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    final now = DateTime.now();
    var list = _local.where((p) {
      if (p.isArchived) return false;  // archived prompts hidden from main list
      if (_showFavoritesOnly && !p.isFavorite) return false;
      if (_tagFilter != null && !p.tags.contains(_tagFilter)) return false;
      if (q.isNotEmpty && !p.name.toLowerCase().contains(q) && !p.id.contains(q)) return false;
      switch (_dateFilter) {
        case _DateFilter.today:
          return p.created.day == now.day && p.created.month == now.month && p.created.year == now.year;
        case _DateFilter.week:
          return now.difference(p.created).inDays < 7;
        case _DateFilter.month:
          return now.difference(p.created).inDays < 30;
        case _DateFilter.all:
          return true;
      }
    }).toList();
    list.sort((a, b) => _sort == _SortMode.newest
        ? b.created.compareTo(a.created)
        : a.created.compareTo(b.created));
    return list;
  }

  List<SavedPrompt> get _archived => _local.where((p) => p.isArchived).toList();

  // ── Sync ──────────────────────────────────────────────────────────────────
  Future<void> _sync() async {
    if (!widget.github.hasPat) {
      showAppSnack(context, 'Configure ton token dans Paramètres', isError: true);
      return;
    }
    setState(() => _syncing = true);
    try {
      final remote   = await widget.github.fetchRemotePrompts();
      final local    = await PrefsService.getPrompts();
      final localIds = local.map((p) => p.id).toSet();
      final newOnes  = remote.where((p) => !localIds.contains(p.id)).toList();
      for (final p in newOnes) await PrefsService.addPrompt(p);
      final updated = await PrefsService.getPrompts();
      if (!mounted) return;
      setState(() { _syncing = false; _local = updated; });
      showAppSnack(context, newOnes.isEmpty
        ? 'Déjà à jour (${updated.length} prompts)'
        : '+${newOnes.length} prompt${newOnes.length > 1 ? "s" : ""} synchronisé${newOnes.length > 1 ? "s" : ""}');
    } catch (e) {
      if (mounted) { setState(() => _syncing = false); showAppSnack(context, 'Erreur: $e', isError: true); }
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────
  Future<void> _delete(SavedPrompt p) async {
    await PrefsService.deletePrompt(p.id);
    if (!mounted) return;
    setState(() => _local.removeWhere((x) => x.id == p.id));
    showAppSnack(context, '"${p.name}" supprimé');
  }

  Future<void> _undoDelete(SavedPrompt p) async {
    await PrefsService.addPrompt(p);
    if (!mounted) return;
    final updated = await PrefsService.getPrompts();
    setState(() => _local = updated);
  }

  // ── Archive ───────────────────────────────────────────────────────────────
  Future<void> _archive(SavedPrompt p) async {
    HapticFeedback.mediumImpact();
    await PrefsService.archivePrompt(p.id);
    if (!mounted) return;
    setState(() {
      final idx = _local.indexWhere((x) => x.id == p.id);
      if (idx != -1) _local[idx] = _local[idx].copyWith(isArchived: true);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: kCard2,
      behavior: SnackBarBehavior.floating,
      content: Text('"${p.name}" archivé', style: GoogleFonts.inter(color: kText, fontSize: 13)),
      action: SnackBarAction(
        label: 'Annuler',
        textColor: kAccentMid,
        onPressed: () async {
          await PrefsService.unarchivePrompt(p.id);
          if (!mounted) return;
          setState(() {
            final idx = _local.indexWhere((x) => x.id == p.id);
            if (idx != -1) _local[idx] = _local[idx].copyWith(isArchived: false);
          });
        },
      ),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _unarchive(SavedPrompt p) async {
    await PrefsService.unarchivePrompt(p.id);
    if (!mounted) return;
    setState(() {
      final idx = _local.indexWhere((x) => x.id == p.id);
      if (idx != -1) _local[idx] = _local[idx].copyWith(isArchived: false);
    });
    showAppSnack(context, '"${p.name}" restauré');
  }

  // ── Favorite ──────────────────────────────────────────────────────────────
  Future<void> _toggleFavorite(SavedPrompt p) async {
    final nowFav = await PrefsService.toggleFavorite(p.id);
    if (!mounted) return;
    setState(() {
      final idx = _local.indexWhere((x) => x.id == p.id);
      if (idx != -1) _local[idx] = _local[idx].copyWith(isFavorite: nowFav);
    });
  }

  // ── Open detail ───────────────────────────────────────────────────────────
  Future<void> _openDetail(SavedPrompt p) async {
    final result = await Navigator.push<PromptDetailResult>(
      context,
      MaterialPageRoute(builder: (_) => PromptDetailScreen(prompt: p, github: widget.github)),
    );
    if (result == null) return;
    if (result.deleted) {
      await _delete(p);
    } else if (result.newName != null && result.newName != p.name) {
      await PrefsService.updatePromptName(p.id, result.newName!);
      setState(() {
        final idx = _local.indexWhere((x) => x.id == p.id);
        if (idx != -1) _local[idx] = p.copyWith(name: result.newName!);
      });
    }
  }

  // ── Share ─────────────────────────────────────────────────────────────────
  void _share(SavedPrompt p) {
    Share.share('${p.name}\n${p.link}', subject: p.name);
  }

  // ── Copy MD ───────────────────────────────────────────────────────────────
  Future<void> _copyMd(SavedPrompt p) async {
    final md = '[${p.name}](${p.link})';
    await Clipboard.setData(ClipboardData(text: md));
    if (mounted) showAppSnack(context, 'Lien Markdown copié !');
  }

  // ── Edit tags ─────────────────────────────────────────────────────────────
  Future<void> _editTags(SavedPrompt p) async {
    final ctrl = TextEditingController(text: p.tags.join(', '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: kBorder)),
        title: Text('Tags', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          AppInput(
            controller: ctrl, autofocus: true,
            hint: 'Ex: dev, urgent, IA',
            onSubmitted: (v) => Navigator.pop(context, true),
          ),
          const SizedBox(height: 6),
          Text('Sépare les tags par des virgules', style: GoogleFonts.inter(color: kMuted2, fontSize: 11.5)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: Text('Annuler', style: GoogleFonts.inter(color: kMuted))),
          AppButton(label: 'OK', onTap: () => Navigator.pop(_, true), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
        ],
      ),
    );
    ctrl.dispose();
    if (ok == true) {
      final tags = ctrl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
      await PrefsService.setPromptTags(p.id, tags);
      if (!mounted) return;
      setState(() {
        final idx = _local.indexWhere((x) => x.id == p.id);
        if (idx != -1) _local[idx] = _local[idx].copyWith(tags: tags);
      });
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _buildHeader(),
          _buildFiltersRow(),
          if (_allTags.isNotEmpty) _buildTagsRow(),
          Expanded(child: _loading
            ? const Center(child: AppLoadingIndicator())
            : items.isEmpty && _archived.isEmpty
              ? AppEmptyState(
                  icon: Icons.description_outlined,
                  title: _searchCtrl.text.isNotEmpty ? 'Aucun résultat' : 'Aucun prompt',
                  subtitle: _searchCtrl.text.isNotEmpty
                      ? 'Essaie un autre terme'
                      : 'Synchronise depuis GitHub ou crée un prompt depuis l\'accueil',
                  action: widget.github.hasPat && _searchCtrl.text.isEmpty
                      ? AppButton(label: 'Synchroniser', loading: _syncing, onTap: _sync,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9))
                      : null,
                )
              : RefreshIndicator(
                  color: kAccent, backgroundColor: kCard,
                  onRefresh: _sync,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      ...items.map((p) => _PromptCard(
                        prompt: p,
                        onTap: () => _openDetail(p),
                        onArchive: () => _archive(p),
                        onFavorite: () => _toggleFavorite(p),
                        onCopyMd: () => _copyMd(p),
                        onShare: () => _share(p),
                        onEditTags: () => _editTags(p),
                        onHistory: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => PromptHistoryScreen(prompt: p, github: widget.github))),
                      )),
                      // ── Archived section ──────────────────────────────
                      if (_archived.isNotEmpty) ...[
                        GestureDetector(
                          onTap: () { HapticFeedback.selectionClick(); setState(() => _showArchived = !_showArchived); },
                          child: Container(
                            margin: const EdgeInsets.only(top: 8, bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
                            child: Row(children: [
                              Icon(_showArchived ? Icons.expand_less : Icons.expand_more, size: 16, color: kMuted2),
                              const SizedBox(width: 8),
                              Text('Archivés', style: GoogleFonts.inter(color: kMuted2, fontSize: 12.5, fontWeight: FontWeight.w500)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(4)),
                                child: Text('${_archived.length}', style: GoogleFonts.inter(color: kMuted, fontSize: 11, fontWeight: FontWeight.w600)),
                              ),
                            ]),
                          ),
                        ),
                        if (_showArchived)
                          ..._archived.map((p) => _ArchivedCard(
                            prompt: p,
                            onUnarchive: () => _unarchive(p),
                            onDelete: () => _delete(p),
                          )),
                      ],
                    ],
                  ),
                ),
          ),
        ]),
      ),
    );
  }


  Widget _buildHeader() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBorder, width: 0.5))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(width: 34, height: 34,
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
            child: const Icon(Icons.arrow_back_ios_new, size: 13, color: kMuted)),
        ),
        const SizedBox(width: 12),
        Text('Prompts', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        const Spacer(),
        // Favorites toggle
        GestureDetector(
          onTap: () => setState(() { _showFavoritesOnly = !_showFavoritesOnly; }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: _showFavoritesOnly ? const Color(0xFFF59E0B).withOpacity(0.15) : kCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _showFavoritesOnly ? const Color(0xFFF59E0B).withOpacity(0.5) : kBorder, width: _showFavoritesOnly ? 1 : 0.5),
            ),
            child: Icon(
              _showFavoritesOnly ? Icons.star_rounded : Icons.star_border_rounded,
              size: 17, color: _showFavoritesOnly ? const Color(0xFFF59E0B) : kMuted,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Sync button
        GestureDetector(
          onTap: _syncing ? null : _sync,
          child: Container(width: 34, height: 34,
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
            child: _syncing
              ? const Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 1.5, color: kAccent))
              : const Icon(Icons.sync_rounded, size: 17, color: kMuted)),
        ),
        const SizedBox(width: 8),
        // Total badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(6)),
          child: Text('${_local.length}', style: GoogleFonts.inter(color: kAccentMid, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ]),
      const SizedBox(height: 10),
      AppInput(
        hint: 'Rechercher un prompt…',
        controller: _searchCtrl,
        suffix: GestureDetector(
          onTap: _searchCtrl.text.isNotEmpty ? () { _searchCtrl.clear(); setState(() {}); } : null,
          child: Icon(_searchCtrl.text.isNotEmpty ? Icons.close : Icons.search, size: 16, color: kMuted2),
        ),
      ),
    ]),
  );

  Widget _buildFiltersRow() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Row(children: [
      // Sort
      GestureDetector(
        onTap: () => setState(() => _sort = _sort == _SortMode.newest ? _SortMode.oldest : _SortMode.newest),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(7), border: Border.all(color: kBorder, width: 0.5)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_sort == _SortMode.newest ? Icons.arrow_downward : Icons.arrow_upward, size: 13, color: kMuted2),
            const SizedBox(width: 5),
            Text(_sort == _SortMode.newest ? 'Plus récents' : 'Plus anciens', style: GoogleFonts.inter(color: kMuted2, fontSize: 12)),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      // Date filter chips
      ..._DateFilter.values.map((f) {
        final label = switch (f) {
          _DateFilter.all   => 'Tous',
          _DateFilter.today => "Aujourd'hui",
          _DateFilter.week  => '7j',
          _DateFilter.month => '30j',
        };
        final selected = _dateFilter == f;
        return GestureDetector(
          onTap: () => setState(() => _dateFilter = f),
          child: Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? kAccentSub : kCard,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: selected ? kAccent.withOpacity(0.4) : kBorder, width: selected ? 1 : 0.5),
            ),
            child: Text(label, style: GoogleFonts.inter(
              color: selected ? kAccentMid : kMuted2,
              fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            )),
          ),
        );
      }),
    ]),
  );

  Widget _buildTagsRow() => SizedBox(
    height: 36,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      children: [
        GestureDetector(
          onTap: () => setState(() => _tagFilter = null),
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _tagFilter == null ? kAccentSub : kCard,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _tagFilter == null ? kAccent.withOpacity(0.4) : kBorder, width: _tagFilter == null ? 1 : 0.5),
            ),
            child: Text('# Tous', style: GoogleFonts.inter(
              color: _tagFilter == null ? kAccentMid : kMuted2,
              fontSize: 11.5, fontWeight: _tagFilter == null ? FontWeight.w600 : FontWeight.w400,
            )),
          ),
        ),
        ..._allTags.map((t) {
          final selected = _tagFilter == t;
          return GestureDetector(
            onTap: () => setState(() => _tagFilter = selected ? null : t),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? kAccentSub : kCard,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: selected ? kAccent.withOpacity(0.4) : kBorder, width: selected ? 1 : 0.5),
              ),
              child: Text('# $t', style: GoogleFonts.inter(
                color: selected ? kAccentMid : kMuted2,
                fontSize: 11.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              )),
            ),
          );
        }),
      ],
    ),
  );
}

// ── PromptCard ────────────────────────────────────────────────────────────────
class _PromptCard extends StatelessWidget {
  final SavedPrompt prompt;
  final VoidCallback onTap, onArchive, onFavorite, onCopyMd, onShare, onEditTags, onHistory;

  const _PromptCard({
    required this.prompt,
    required this.onTap,
    required this.onArchive,
    required this.onFavorite,
    required this.onCopyMd,
    required this.onShare,
    required this.onEditTags,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final p = prompt;
    return Dismissible(
      key: ValueKey(p.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: kYellow.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kYellow.withOpacity(0.2), width: 0.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.archive_outlined, color: kYellow, size: 18),
          const SizedBox(width: 4),
          Text('Archiver', style: GoogleFonts.inter(color: kYellow, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
      ),
      confirmDismiss: (_) async {
        onArchive();
        return false;
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kBorder, width: 0.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Main row ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Number badge
                Container(
                  width: 36, height: 36,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(8)),
                  child: Center(child: Text('#${p.number}', style: GoogleFonts.inter(color: kAccentMid, fontSize: 10.5, fontWeight: FontWeight.w700))),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    p.name.isNotEmpty ? p.name : p.id,
                    style: GoogleFonts.inter(color: kText, fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.3),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.schedule, size: 11, color: kMuted2),
                    const SizedBox(width: 3),
                    Text(_relativeDate(p.created), style: GoogleFonts.inter(color: kMuted2, fontSize: 11.5)),
                  ]),
                ])),
                const SizedBox(width: 6),
                // Favorite star
                GestureDetector(
                  onTap: onFavorite,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      p.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 18,
                      color: p.isFavorite ? const Color(0xFFF59E0B) : kMuted2,
                    ),
                  ),
                ),
              ]),
            ),
            // ── Tags ─────────────────────────────────────────────────────
            if (p.tags.isNotEmpty) Padding(
              padding: const EdgeInsets.fromLTRB(60, 6, 14, 0),
              child: Wrap(spacing: 5, runSpacing: 4, children: p.tags.map((t) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: kAccentSub.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: kAccent.withOpacity(0.15), width: 0.5),
                ),
                child: Text('# $t', style: GoogleFonts.inter(color: kAccentMid, fontSize: 10.5, fontWeight: FontWeight.w500)),
              )).toList()),
            ),
            // ── Action buttons ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(children: [
                _Btn(icon: Icons.copy_outlined, label: 'Copier MD', onTap: onCopyMd),
                const SizedBox(width: 6),
                _Btn(icon: Icons.share_outlined, label: 'Partager', onTap: onShare),
                const SizedBox(width: 6),
                _Btn(icon: Icons.label_outline, label: 'Tags', onTap: onEditTags),
                const SizedBox(width: 6),
                _Btn(icon: Icons.history_rounded, label: 'Historique', onTap: onHistory),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  String _relativeDate(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inHours < 1) return 'Il y a ${diff.inMinutes}min';
    if (diff.inDays < 1) return 'Il y a ${diff.inHours}h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays}j';
    if (diff.inDays < 30) return 'Il y a ${(diff.inDays / 7).floor()}sem';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }
}

// ── ArchivedCard ─────────────────────────────────────────────────────────────
class _ArchivedCard extends StatelessWidget {
  final SavedPrompt prompt;
  final VoidCallback onUnarchive;
  final VoidCallback onDelete;
  const _ArchivedCard({required this.prompt, required this.onUnarchive, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final p = prompt;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kCard.withOpacity(0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder, width: 0.5),
      ),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(7)),
          child: const Icon(Icons.archive_outlined, size: 15, color: kMuted2),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(
          p.name.isNotEmpty ? p.name : p.id,
          style: GoogleFonts.inter(color: kMuted, fontSize: 13, fontWeight: FontWeight.w400),
          maxLines: 1, overflow: TextOverflow.ellipsis,
        )),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onUnarchive,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(6)),
            child: Text('Restaurer', style: GoogleFonts.inter(color: kAccentMid, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: onDelete,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Icon(Icons.delete_outline, size: 15, color: kMuted2),
          ),
        ),
      ]),
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Btn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(6), border: Border.all(color: kBorder, width: 0.5)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: kMuted),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.inter(color: kMuted, fontSize: 11, fontWeight: FontWeight.w500)),
      ]),
    ),
  );
}
