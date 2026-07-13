import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/saved_prompt.dart';
import '../services/github_service.dart';
import '../services/prefs_service.dart';
import '../theme.dart';
import '../widgets/app_components.dart';
import 'prompt_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  final GitHubService github;
  const DashboardScreen({super.key, required this.github});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<SavedPrompt> _prompts = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await PrefsService.getPrompts();
    if (mounted) setState(() { _prompts = list; _loading = false; });
  }

  Future<void> _sync() async {
    if (!widget.github.hasPat) return;
    setState(() => _syncing = true);
    try {
      final remote = await widget.github.fetchRemotePrompts();
      final local = await PrefsService.getPrompts();
      final ids = local.map((p) => p.id).toSet();
      final newOnes = remote.where((p) => !ids.contains(p.id)).toList();
      for (final p in newOnes) await PrefsService.addPrompt(p);
      final updated = await PrefsService.getPrompts();
      if (!mounted) return;
      setState(() { _prompts = updated; _syncing = false; });
      if (newOnes.isNotEmpty) showAppSnack(context, '+${newOnes.length} prompt(s) sync');
    } catch (e) {
      if (mounted) setState(() => _syncing = false);
    }
  }

  // ── Stats ─────────────────────────────────────────────────────────────────
  int get _total => _prompts.length;

  int get _thisWeek {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _prompts.where((p) => p.created.isAfter(cutoff)).length;
  }

  int get _today {
    final now = DateTime.now();
    return _prompts.where((p) =>
        p.created.day == now.day && p.created.month == now.month && p.created.year == now.year).length;
  }

  int get _favorites => _prompts.where((p) => p.isFavorite).length;

  List<_DayStat> get _last7Days {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final count = _prompts.where((p) =>
          p.created.day == d.day && p.created.month == d.month && p.created.year == d.year).length;
      return _DayStat(day: d, count: count);
    });
  }

  // ── Tags breakdown ────────────────────────────────────────────────────────
  Map<String, int> get _tagCounts {
    final map = <String, int>{};
    for (final p in _prompts) {
      for (final t in p.tags) {
        map[t] = (map[t] ?? 0) + 1;
      }
    }
    final sorted = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted.take(6));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _buildHeader(),
          Expanded(child: _loading
            ? const Center(child: AppLoadingIndicator())
            : RefreshIndicator(
                color: kAccent, backgroundColor: kCard,
                onRefresh: () async { await _load(); await _sync(); },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildStatsRow(),
                    const SizedBox(height: 16),
                    _buildActivityChart(),
                    const SizedBox(height: 16),
                    if (_tagCounts.isNotEmpty) ...[_buildTagBreakdown(), const SizedBox(height: 16)],
                    _buildRecentPrompts(),
                    SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                  ],
                ),
              ),
          ),
        ]),
      ),
    );
  }

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
      Text('Dashboard', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
      const Spacer(),
      GestureDetector(
        onTap: _syncing ? null : _sync,
        child: Container(width: 34, height: 34,
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
          child: _syncing
            ? const Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 1.5, color: kAccent))
            : const Icon(Icons.sync_rounded, size: 17, color: kMuted)),
      ),
    ]),
  );

  Widget _buildStatsRow() => Row(children: [
    Expanded(child: _StatCard(label: 'Total', value: '$_total', icon: Icons.description_outlined, color: kAccent)),
    const SizedBox(width: 10),
    Expanded(child: _StatCard(label: "Aujourd'hui", value: '$_today', icon: Icons.today_outlined, color: const Color(0xFF10b981))),
    const SizedBox(width: 10),
    Expanded(child: _StatCard(label: '7 jours', value: '$_thisWeek', icon: Icons.date_range_outlined, color: const Color(0xFFF59E0B))),
    const SizedBox(width: 10),
    Expanded(child: _StatCard(label: 'Favoris', value: '$_favorites', icon: Icons.star_outline, color: const Color(0xFFEF4444))),
  ]);

  Widget _buildActivityChart() {
    final days = _last7Days;
    final maxCount = days.map((d) => d.count).fold(0, (a, b) => a > b ? a : b);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Activité — 7 derniers jours', style: GoogleFonts.inter(color: kText, fontSize: 13.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: days.map((d) {
              final fraction = maxCount == 0 ? 0.05 : (d.count / maxCount).clamp(0.05, 1.0);
              final isToday = d.day.day == DateTime.now().day &&
                  d.day.month == DateTime.now().month;
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (d.count > 0)
                    Text('${d.count}', style: GoogleFonts.inter(color: kMuted2, fontSize: 9)),
                  const SizedBox(height: 2),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    height: 60 * fraction,
                    decoration: BoxDecoration(
                      color: isToday ? kAccent : kAccentSub,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_dayLabel(d.day), style: GoogleFonts.inter(
                    color: isToday ? kAccentMid : kMuted2, fontSize: 9.5,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                  )),
                ]),
              ));
            }).toList(),
          ),
        ),
      ]),
    );
  }

  String _dayLabel(DateTime d) {
    const days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return days[d.weekday - 1];
  }

  Widget _buildTagBreakdown() => AppCard(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Tags utilisés', style: GoogleFonts.inter(color: kText, fontSize: 13.5, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: _tagCounts.entries.map((e) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(6), border: Border.all(color: kAccent.withOpacity(0.2), width: 0.5)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(e.key, style: GoogleFonts.inter(color: kAccentMid, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: kAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
            child: Text('${e.value}', style: GoogleFonts.inter(color: kAccentMid, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ]),
      )).toList()),
    ]),
  );

  Widget _buildRecentPrompts() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text('Récents', style: GoogleFonts.inter(color: kText, fontSize: 13.5, fontWeight: FontWeight.w600)),
    ),
    if (_prompts.isEmpty)
      const AppEmptyState(icon: Icons.description_outlined, title: 'Aucun prompt', subtitle: 'Crée ton premier prompt depuis l\'accueil')
    else
      ..._prompts.take(8).map((p) => GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => PromptDetailScreen(prompt: p, github: widget.github))),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder, width: 0.5)),
          child: Row(children: [
            Container(width: 32, height: 32,
              decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text('#${p.number}', style: GoogleFonts.inter(color: kAccentMid, fontSize: 10, fontWeight: FontWeight.w700)))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name.isNotEmpty ? p.name : p.id, style: GoogleFonts.inter(color: kText, fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (p.tags.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(p.tags.join(' · '), style: GoogleFonts.inter(color: kAccentMid, fontSize: 10.5)),
              ],
            ])),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_relativeDate(p.created), style: GoogleFonts.inter(color: kMuted2, fontSize: 11)),
              if (p.isFavorite) ...[
                const SizedBox(height: 2),
                const Icon(Icons.star_rounded, size: 13, color: Color(0xFFF59E0B)),
              ],
            ]),
          ]),
        ),
      )),
  ]);

  String _relativeDate(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inHours < 1) return '${diff.inMinutes}min';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}j';
    return '${d.day}/${d.month}';
  }
}

class _DayStat {
  final DateTime day;
  final int count;
  const _DayStat({required this.day, required this.count});
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(height: 6),
      Text(value, style: GoogleFonts.inter(color: kText, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
      Text(label, style: GoogleFonts.inter(color: kMuted2, fontSize: 10.5)),
    ]),
  );
}
