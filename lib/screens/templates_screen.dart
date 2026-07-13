import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/prefs_service.dart';
import '../theme.dart';
import '../widgets/app_components.dart';

class TemplatesScreen extends StatefulWidget {
  /// If non-null, shows an "Utiliser" button that pops with the selected content.
  final bool pickMode;
  const TemplatesScreen({super.key, this.pickMode = false});

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  List<PromptTemplate> _templates = [];
  bool _loading = true;
  String _search = '';
  String? _filterCategory;
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await PrefsService.getTemplates();
    if (mounted) setState(() { _templates = list; _loading = false; });
  }

  List<PromptTemplate> get _filtered {
    var list = _templates;
    if (_filterCategory != null) list = list.where((t) => t.category == _filterCategory).toList();
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((t) => t.name.toLowerCase().contains(q) || t.content.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  Set<String> get _categories => _templates.map((t) => t.category).toSet();

  Future<void> _showCreateOrEdit([PromptTemplate? tpl]) async {
    final nameCtrl = TextEditingController(text: tpl?.name ?? '');
    final contentCtrl = TextEditingController(text: tpl?.content ?? '');
    String category = tpl?.category ?? 'Général';
    final categories = ['Général', 'Dev', 'Business', 'Design', 'Marketing', 'IA', 'Autre'];

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            height: MediaQuery.of(ctx).size.height * 0.85,
            decoration: const BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(top: BorderSide(color: kBorder, width: 0.5)),
            ),
            child: SafeArea(
              top: false,
              child: Column(children: [
                const AppDragHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Row(children: [
                    Text(tpl == null ? 'Nouveau template' : 'Modifier', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    AppButton(
                      label: 'Sauvegarder',
                      onTap: () => Navigator.pop(ctx, true),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ]),
                ),
                Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
                  const AppLabel('Nom'),
                  const SizedBox(height: 6),
                  AppInput(controller: nameCtrl, hint: 'Ex: Bug Report', autofocus: tpl == null),
                  const SizedBox(height: 14),
                  const AppLabel('Catégorie'),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, children: categories.map((c) => GestureDetector(
                    onTap: () => set(() => category = c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: category == c ? kAccentSub : kBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: category == c ? kAccent.withOpacity(0.4) : kBorder, width: category == c ? 1 : 0.5),
                      ),
                      child: Text(c, style: GoogleFonts.inter(color: category == c ? kAccentMid : kMuted, fontSize: 12.5, fontWeight: category == c ? FontWeight.w600 : FontWeight.w400)),
                    ),
                  )).toList()),
                  const SizedBox(height: 14),
                  const AppLabel('Contenu'),
                  const SizedBox(height: 6),
                  AppInput(controller: contentCtrl, hint: 'Contenu du template…', maxLines: 14),
                ])),
              ]),
            ),
          ),
        ),
      ),
    );

    if (result == true) {
      final name = nameCtrl.text.trim();
      final content = contentCtrl.text.trim();
      if (name.isEmpty || content.isEmpty) return;
      if (tpl == null) {
        await PrefsService.addTemplate(name, content, category: category);
      } else {
        await PrefsService.updateTemplate(tpl.id, name: name, content: content, category: category);
      }
      await _load();
    }
    nameCtrl.dispose();
    contentCtrl.dispose();
  }

  Future<void> _delete(PromptTemplate tpl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: kBorder)),
        title: Text('Supprimer "${tpl.name}" ?', style: GoogleFonts.inter(color: kText, fontSize: 15)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: Text('Annuler', style: GoogleFonts.inter(color: kMuted))),
          AppButton(label: 'Supprimer', variant: AppButtonVariant.destructive, onTap: () => Navigator.pop(_, true), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
        ],
      ),
    );
    if (ok == true) { await PrefsService.deleteTemplate(tpl.id); await _load(); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBg,
    body: SafeArea(
      bottom: false,
      child: Column(children: [
        _buildHeader(),
        if (_categories.length > 1) _buildCategoryFilter(),
        Expanded(child: _loading
          ? const Center(child: AppLoadingIndicator())
          : _filtered.isEmpty
            ? AppEmptyState(
                icon: Icons.auto_awesome_outlined,
                title: 'Aucun template',
                subtitle: _search.isNotEmpty ? 'Aucun résultat pour "$_search"' : 'Crée ton premier template',
                action: _search.isEmpty ? AppButton(label: 'Créer', onTap: () => _showCreateOrEdit(), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9)) : null,
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                itemCount: _filtered.length,
                itemBuilder: (_, i) => _buildCard(_filtered[i]),
              ),
        ),
      ]),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: _showCreateOrEdit,
      backgroundColor: kAccent,
      child: const Icon(Icons.add, color: Colors.white),
    ),
  );

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBorder, width: 0.5))),
    child: Column(children: [
      Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(width: 34, height: 34,
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
            child: const Icon(Icons.arrow_back_ios_new, size: 13, color: kMuted)),
        ),
        const SizedBox(width: 12),
        Text(widget.pickMode ? 'Choisir un template' : 'Templates', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(6)),
          child: Text('${_templates.length}', style: GoogleFonts.inter(color: kAccentMid, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ]),
      const SizedBox(height: 10),
      AppInput(
        controller: _searchCtrl,
        hint: 'Rechercher…',
        suffix: GestureDetector(
          onTap: _search.isEmpty ? null : () { _searchCtrl.clear(); setState(() => _search = ''); },
          child: Icon(_search.isEmpty ? Icons.search : Icons.close, size: 16, color: kMuted2),
        ),
      ),
    ]),
  );

  Widget _buildCategoryFilter() => SizedBox(
    height: 40,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      children: [
        _CatChip(label: 'Tous', selected: _filterCategory == null, onTap: () => setState(() => _filterCategory = null)),
        ..._categories.map((c) => _CatChip(label: c, selected: _filterCategory == c, onTap: () => setState(() => _filterCategory = _filterCategory == c ? null : c))),
      ],
    ),
  );

  Widget _buildCard(PromptTemplate tpl) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(5)),
            child: Text(tpl.category, style: GoogleFonts.inter(color: kAccentMid, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(tpl.name, style: GoogleFonts.inter(color: kText, fontSize: 13.5, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
          GestureDetector(onTap: () => _showCreateOrEdit(tpl), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.edit_outlined, size: 15, color: kMuted2))),
          const SizedBox(width: 2),
          GestureDetector(onTap: () => _delete(tpl), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.delete_outline, size: 15, color: kRed))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Text(
          tpl.content.length > 120 ? '${tpl.content.substring(0, 120)}…' : tpl.content,
          style: GoogleFonts.robotoMono(color: kMuted2, fontSize: 11, height: 1.5),
          maxLines: 4, overflow: TextOverflow.ellipsis,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Row(children: [
          Expanded(child: GestureDetector(
            onTap: () async { await Clipboard.setData(ClipboardData(text: tpl.content)); if (context.mounted) showAppSnack(context, 'Copié !'); },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(7), border: Border.all(color: kBorder, width: 0.5)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.copy, size: 13, color: kMuted),
                const SizedBox(width: 5),
                Text('Copier', style: GoogleFonts.inter(color: kMuted, fontSize: 12.5)),
              ]),
            ),
          )),
          if (widget.pickMode) ...[
            const SizedBox(width: 8),
            Expanded(child: GestureDetector(
              onTap: () => Navigator.pop(context, tpl.content),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(7), border: Border.all(color: kAccent.withOpacity(0.3), width: 0.5)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.check, size: 13, color: kAccentMid),
                  const SizedBox(width: 5),
                  Text('Utiliser', style: GoogleFonts.inter(color: kAccentMid, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            )),
          ],
        ]),
      ),
    ]),
  );
}

class _CatChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CatChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? kAccentSub : kCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: selected ? kAccent.withOpacity(0.4) : kBorder, width: selected ? 1 : 0.5),
      ),
      child: Text(label, style: GoogleFonts.inter(color: selected ? kAccentMid : kMuted, fontSize: 12.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
    ),
  );
}
