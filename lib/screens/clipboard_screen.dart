import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/github_service.dart';
import '../theme.dart';
import '../widgets/app_components.dart';

// ── Screen ────────────────────────────────────────────────────────────────────
class ClipboardScreen extends StatefulWidget {
  final GitHubService github;
  const ClipboardScreen({super.key, required this.github});

  @override
  State<ClipboardScreen> createState() => _ClipboardScreenState();
}

class _ClipboardScreenState extends State<ClipboardScreen> {
  List<ClipboardEntry> _entries = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _composing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final entries = await widget.github.fetchClipboardEntries();
      if (mounted) setState(() { _entries = entries; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _save() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    if (!widget.github.hasPat) {
      showAppSnack(context, 'Configure ton token dans Paramètres', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final entry = await widget.github.saveClipboardEntry(text);
      if (mounted) {
        setState(() {
          _entries.insert(0, entry);
          _saving = false;
          _composing = false;
          _ctrl.clear();
        });
        showAppSnack(context, 'Enregistré dans le presse-papiers partagé !');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAppSnack(context, e.toString().replaceAll('Exception: ', ''), isError: true);
      }
    }
  }

  Future<void> _delete(ClipboardEntry entry) async {
    try {
      await widget.github.deleteClipboardEntry(entry.id);
      if (mounted) setState(() => _entries.removeWhere((e) => e.id == entry.id));
      showAppSnack(context, 'Entrée supprimée');
    } catch (e) {
      if (mounted) showAppSnack(context, e.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    showAppSnack(context, 'Copié !');
  }

  Future<void> _editAndCopy(ClipboardEntry entry) async {
    final ctrl = TextEditingController(text: entry.content);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: kBorder, width: 0.5)),
        title: Text('Éditer et copier', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 8,
          style: GoogleFonts.inter(color: kText, fontSize: 13, height: 1.5),
          cursorColor: kAccent,
          decoration: InputDecoration(
            hintText: 'Modifie le texte…',
            hintStyle: GoogleFonts.inter(color: kMuted2, fontSize: 13),
            filled: true,
            fillColor: kCard2,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder, width: 0.5)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kAccent, width: 1)),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_), child: Text('Annuler', style: GoogleFonts.inter(color: kMuted))),
          AppButton(label: 'Copier', onTap: () => Navigator.pop(_, ctrl.text), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: result));
      if (mounted) showAppSnack(context, 'Copié !');
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isNotEmpty) {
      _ctrl.text = text;
      setState(() => _composing = true);
      _focus.requestFocus();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBg,
    body: SafeArea(bottom: false, child: Column(children: [
      _buildHeader(),
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator(color: kAccent, strokeWidth: 2))
        : _error != null
          ? _buildError()
          : _entries.isEmpty && !_composing
            ? _buildEmpty()
            : _buildList()),
      _buildComposer(),
      const SizedBox(height: 12),
    ])),
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
      Container(width: 28, height: 28,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFf59e0b), Color(0xFFd97706)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.content_paste_rounded, size: 15, color: Colors.white)),
      const SizedBox(width: 8),
      Text('Presse-papiers', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
      if (_entries.isNotEmpty) ...[
        const SizedBox(width: 8),
        AppBadge('${_entries.length}'),
      ],
      const Spacer(),
      GestureDetector(
        onTap: _load,
        child: Container(width: 34, height: 34,
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
          child: const Icon(Icons.sync_rounded, size: 17, color: kMuted)),
      ),
    ]),
  );

  Widget _buildError() => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off_outlined, size: 40, color: kRed),
      const SizedBox(height: 12),
      Text(_error!, style: GoogleFonts.inter(color: kMuted2, fontSize: 13), textAlign: TextAlign.center),
      const SizedBox(height: 16),
      AppButton(label: 'Réessayer', icon: Icons.refresh, onTap: _load, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
    ]),
  ));

  Widget _buildEmpty() => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 72, height: 72,
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: kBorder)),
        child: const Icon(Icons.content_paste_off_outlined, size: 34, color: kMuted2)),
      const SizedBox(height: 16),
      Text('Presse-papiers vide', style: GoogleFonts.inter(color: kText, fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text('Colle du texte ci-dessous pour le partager avec tous les utilisateurs.',
        style: GoogleFonts.inter(color: kMuted2, fontSize: 13, height: 1.5), textAlign: TextAlign.center),
    ]),
  ));

  Widget _buildList() => ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    itemCount: _entries.length,
    itemBuilder: (_, i) => _EntryCard(
      entry: _entries[i],
      onCopy: () => _copy(_entries[i].content),
      onEditAndCopy: () => _editAndCopy(_entries[i]),
      onDelete: () => _delete(_entries[i]),
    ),
  );

  Widget _buildComposer() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _composing
        ? _buildComposeExpanded()
        : _buildComposeCollapsed(),
    ),
  );

  Widget _buildComposeCollapsed() => Row(key: const ValueKey('collapsed'), children: [
    Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _composing = true),
        child: Container(
          height: 44,
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder, width: 0.5)),
          child: Row(children: [
            const SizedBox(width: 14),
            const Icon(Icons.add, size: 16, color: kMuted2),
            const SizedBox(width: 8),
            Text('Ajouter du texte…', style: GoogleFonts.inter(color: kMuted2, fontSize: 14)),
          ]),
        ),
      ),
    ),
    const SizedBox(width: 8),
    GestureDetector(
      onTap: _pasteFromClipboard,
      child: Container(width: 44, height: 44,
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder, width: 0.5)),
        child: const Icon(Icons.content_paste_go_rounded, size: 18, color: kMuted)),
    ),
  ]);

  Widget _buildComposeExpanded() => Container(
    key: const ValueKey('expanded'),
    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _ctrl,
        focusNode: _focus,
        autofocus: true,
        maxLines: 6, minLines: 3,
        style: GoogleFonts.inter(color: kText, fontSize: 13, height: 1.6),
        cursorColor: kAccent,
        decoration: InputDecoration(
          hintText: 'Colle ou tape du texte à partager…',
          hintStyle: GoogleFonts.inter(color: kMuted2, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
        ),
      ),
      const Divider(height: 1, color: kBorder),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(children: [
          GestureDetector(
            onTap: _pasteFromClipboard,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.content_paste_go_rounded, size: 13, color: kMuted),
                const SizedBox(width: 4),
                Text('Coller', style: GoogleFonts.inter(color: kMuted, fontSize: 12, fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () { setState(() { _composing = false; _ctrl.clear(); }); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(8)),
              child: Text('Annuler', style: GoogleFonts.inter(color: kMuted, fontSize: 12, fontWeight: FontWeight.w500)),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _saving ? null : _save,
            child: AnimatedOpacity(
              opacity: _saving ? 0.6 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(10)),
                child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.cloud_upload_outlined, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text('Partager', style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    ]),
              ),
            ),
          ),
        ]),
      ),
    ]),
  );
}

// ── Entry card ────────────────────────────────────────────────────────────────
class _EntryCard extends StatelessWidget {
  final ClipboardEntry entry;
  final VoidCallback onCopy;
  final VoidCallback onEditAndCopy;
  final VoidCallback onDelete;

  const _EntryCard({required this.entry, required this.onCopy, required this.onEditAndCopy, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy · HH:mm', 'fr');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder, width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Text(entry.content,
            style: GoogleFonts.inter(color: kText, fontSize: 13, height: 1.6),
            maxLines: 8, overflow: TextOverflow.ellipsis),
        ),
        const Divider(height: 1, color: kBorder),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Row(children: [
            Text(fmt.format(entry.createdAt.toLocal()), style: GoogleFonts.inter(color: kMuted2, fontSize: 11)),
            const Spacer(),
            // Edit & copy
            _ActionBtn(icon: Icons.edit_outlined, label: 'Éditer', onTap: onEditAndCopy),
            const SizedBox(width: 6),
            // Copy
            _ActionBtn(icon: Icons.copy_rounded, label: 'Copier', accent: true, onTap: onCopy),
            const SizedBox(width: 6),
            // Delete
            GestureDetector(
              onTap: onDelete,
              child: Container(width: 30, height: 30,
                decoration: BoxDecoration(color: kRedSub.withOpacity(0.4), borderRadius: BorderRadius.circular(7)),
                child: const Icon(Icons.delete_outline, size: 14, color: kRed)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;
  final VoidCallback onTap;

  const _ActionBtn({required this.icon, required this.label, this.accent = false, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent ? kAccent : kCard2,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: accent ? Colors.white : kMuted),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.inter(color: accent ? Colors.white : kMuted, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}
