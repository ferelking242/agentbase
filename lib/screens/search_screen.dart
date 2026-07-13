import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/saved_prompt.dart';
import '../services/github_service.dart';
import '../services/prefs_service.dart';
import '../theme.dart';
import '../widgets/app_components.dart';
import 'prompt_detail_screen.dart';
import 'templates_screen.dart';

class SearchScreen extends StatefulWidget {
  final GitHubService github;
  const SearchScreen({super.key, required this.github});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  List<SavedPrompt> _prompts = [];
  List<PromptTemplate> _templates = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() => _query = _ctrl.text.trim()));
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() { _ctrl.dispose(); _focus.dispose(); super.dispose(); }

  Future<void> _load() async {
    final prompts   = await PrefsService.getPrompts();
    final templates = await PrefsService.getTemplates();
    if (mounted) setState(() { _prompts = prompts; _templates = templates; _loading = false; });
  }

  List<SavedPrompt> get _matchedPrompts {
    if (_query.isEmpty) return [];
    final q = _query.toLowerCase();
    return _prompts.where((p) =>
      p.name.toLowerCase().contains(q) ||
      p.id.contains(q) ||
      p.tags.any((t) => t.toLowerCase().contains(q))
    ).take(20).toList();
  }

  List<PromptTemplate> get _matchedTemplates {
    if (_query.isEmpty) return [];
    final q = _query.toLowerCase();
    return _templates.where((t) =>
      t.name.toLowerCase().contains(q) ||
      t.content.toLowerCase().contains(q) ||
      t.category.toLowerCase().contains(q)
    ).take(10).toList();
  }

  @override
  Widget build(BuildContext context) {
    final prompts   = _matchedPrompts;
    final templates = _matchedTemplates;
    final hasResults = prompts.isNotEmpty || templates.isNotEmpty;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBorder, width: 0.5))),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(width: 34, height: 34,
                  decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
                  child: const Icon(Icons.arrow_back_ios_new, size: 13, color: kMuted)),
              ),
              const SizedBox(width: 10),
              Expanded(child: AppInput(
                controller: _ctrl,
                focusNode: _focus,
                hint: 'Rechercher prompts, templates…',
                isDense: true,
                suffix: _query.isNotEmpty
                  ? GestureDetector(onTap: () { _ctrl.clear(); HapticFeedback.lightImpact(); }, child: const Icon(Icons.close, size: 16, color: kMuted2))
                  : const Icon(Icons.search, size: 16, color: kMuted2),
              )),
            ]),
          ),

          // ── Results ─────────────────────────────────────────────────────
          Expanded(child: _loading
            ? const Center(child: AppLoadingIndicator())
            : _query.isEmpty
              ? _buildRecents()
              : !hasResults
                ? AppEmptyState(icon: Icons.search_off, title: 'Aucun résultat', subtitle: 'Essaie un autre terme de recherche')
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      if (prompts.isNotEmpty) ...[
                        const AppSectionHeader('Prompts'),
                        ...prompts.map((p) => _PromptResult(
                          prompt: p, query: _query,
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => PromptDetailScreen(prompt: p, github: widget.github))),
                        )),
                      ],
                      if (templates.isNotEmpty) ...[
                        const AppSectionHeader('Templates'),
                        ...templates.map((t) => _TemplateResult(template: t, query: _query)),
                      ],
                    ],
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _buildRecents() {
    final recents = _prompts.take(5).toList();
    if (recents.isEmpty) {
      return const AppEmptyState(icon: Icons.search, title: 'Recherche globale', subtitle: 'Prompts, templates, tags…');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        const AppSectionHeader('Récents'),
        ...recents.map((p) => _PromptResult(
          prompt: p, query: '',
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => PromptDetailScreen(prompt: p, github: widget.github))),
        )),
      ],
    );
  }
}

class _PromptResult extends StatelessWidget {
  final SavedPrompt prompt;
  final String query;
  final VoidCallback onTap;
  const _PromptResult({required this.prompt, required this.query, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder, width: 0.5)),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.description_outlined, size: 15, color: kAccentMid),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(prompt.name, style: GoogleFonts.inter(color: kText, fontSize: 13.5, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (prompt.tags.isNotEmpty)
            Text(prompt.tags.join(', '), style: GoogleFonts.inter(color: kMuted2, fontSize: 11), maxLines: 1),
        ])),
        if (prompt.isFavorite) const Icon(Icons.star, size: 14, color: kYellow),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right_rounded, size: 16, color: kMuted2),
      ]),
    ),
  );
}

class _TemplateResult extends StatelessWidget {
  final PromptTemplate template;
  final String query;
  const _TemplateResult({required this.template, required this.query});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () async {
      await Clipboard.setData(ClipboardData(text: template.content));
      if (context.mounted) showAppSnack(context, '"${template.name}" copié !');
    },
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder, width: 0.5)),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: kAccentSub.withOpacity(0.5), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.auto_awesome_outlined, size: 15, color: kAccentMid),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(template.name, style: GoogleFonts.inter(color: kText, fontSize: 13.5, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(template.category, style: GoogleFonts.inter(color: kMuted2, fontSize: 11)),
        ])),
        const Icon(Icons.copy_outlined, size: 14, color: kMuted2),
      ]),
    ),
  );
}
