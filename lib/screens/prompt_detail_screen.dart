import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/saved_prompt.dart';
import '../services/github_service.dart';
import '../services/prefs_service.dart';
import '../theme.dart';
import '../widgets/app_components.dart';

class PromptDetailResult {
  final bool deleted;
  final String? newName;
  const PromptDetailResult({this.deleted = false, this.newName});
}

class PromptDetailScreen extends StatefulWidget {
  final SavedPrompt prompt;
  final GitHubService github;

  const PromptDetailScreen({super.key, required this.prompt, required this.github});

  @override
  State<PromptDetailScreen> createState() => _PromptDetailScreenState();
}

class _PromptDetailScreenState extends State<PromptDetailScreen> {
  String? _rawContent;
  bool _loadingContent = true;
  bool _editingName = false;
  late String _name;
  late final TextEditingController _nameCtrl;
  bool _copiedLink = false;
  bool _copiedMd = false;
  bool _loadingMd = false;
  bool _showMeta = false;
  bool _renderMd = true;
  bool _fromCache = false;

  @override
  void initState() {
    super.initState();
    _name = widget.prompt.name;
    _nameCtrl = TextEditingController(text: _name);
    _loadContent();
  }

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  Future<void> _loadContent() async {
    // Try cache first for instant display
    final cached = await PrefsService.getCachedContent(widget.prompt.id);
    if (cached != null && mounted) setState(() { _rawContent = cached; _fromCache = true; });

    try {
      final c = await widget.github.fetchPromptContent(widget.prompt.id);
      if (c != null) {
        await PrefsService.setCachedContent(widget.prompt.id, c);
        if (mounted) setState(() { _rawContent = c; _loadingContent = false; _fromCache = false; });
      } else {
        if (mounted) setState(() => _loadingContent = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingContent = false);
    }
  }

  /// Content visible to the user — strips the hidden metadata comment block.
  String get _displayContent {
    if (_rawContent == null) return '';
    // Remove <!-- AGENTBASE_META ... --> block
    String cleaned = _rawContent!.replaceAll(RegExp(r'<!--\s*AGENTBASE_META[\s\S]*?-->', multiLine: true), '').trim();
    // Also clean up old-style metadata lines if present
    cleaned = cleaned.split('\n').where((line) {
      final t = line.trim();
      if (t.startsWith('**ID:**')) return false;
      if (t.startsWith('**Created:**')) return false;
      if (t.startsWith('**Room:**')) return false;
      if (RegExp(r'^# Prompt\s*\d*$').hasMatch(t)) return false;
      return true;
    }).join('\n').trim();
    // Clean up triple blank lines
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return cleaned;
  }

  /// Metadata block extracted from the hidden comment
  Map<String, String> get _metaFields {
    if (_rawContent == null) return {};
    final match = RegExp(r'<!--\s*AGENTBASE_META\s*([\s\S]*?)-->', multiLine: true).firstMatch(_rawContent!);
    if (match == null) return {};
    final lines = match.group(1)!.trim().split('\n');
    final map = <String, String>{};
    for (final line in lines) {
      final colonIdx = line.indexOf(':');
      if (colonIdx > 0) {
        final key = line.substring(0, colonIdx).trim();
        final val = line.substring(colonIdx + 1).trim();
        map[key] = val;
      }
    }
    return map;
  }

  Future<void> _copyMd() async {
    if (_loadingMd || _rawContent == null) {
      if (_rawContent == null) { showAppSnack(context, 'Contenu non chargé', isError: true); return; }
      return;
    }
    setState(() => _loadingMd = true);
    // Copy the full raw content (with metadata) — AI gets everything
    await Clipboard.setData(ClipboardData(text: _rawContent!));
    setState(() { _loadingMd = false; _copiedMd = true; });
    Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _copiedMd = false); });
  }

  void _startEditName() => setState(() { _editingName = true; _nameCtrl.text = _name; });

  void _confirmName() {
    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty || newName == widget.prompt.name) { setState(() => _editingName = false); return; }
    setState(() { _name = newName; _editingName = false; });
    Navigator.pop(context, PromptDetailResult(newName: newName));
  }

  void _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: kBorder, width: 0.5)),
        title: Text('Supprimer ce prompt ?', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600)),
        content: Text('Cette action ne supprime que la copie locale. Le fichier GitHub reste intact.', style: GoogleFonts.inter(color: kMuted2, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: Text('Annuler', style: GoogleFonts.inter(color: kMuted))),
          TextButton(onPressed: () => Navigator.pop(_, true), child: Text('Supprimer', style: GoogleFonts.inter(color: kRed, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context, const PromptDetailResult(deleted: true));
  }

  @override
  Widget build(BuildContext context) {
    final p   = widget.prompt;
    final num = p.number > 0 ? '#${p.number}' : null;
    final meta = _metaFields;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(bottom: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // AppBar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBorder, width: 0.5))),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(width: 34, height: 34, decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
                child: const Icon(Icons.arrow_back_ios_new, size: 13, color: kMuted)),
            ),
            const SizedBox(width: 12),
            if (num != null) ...[AppBadge(num), const SizedBox(width: 8)],
            Expanded(child: Text('Détails du prompt', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.3))),
            GestureDetector(
              onTap: _delete,
              child: Container(width: 34, height: 34, decoration: BoxDecoration(color: kRedSub.withOpacity(0.5), borderRadius: BorderRadius.circular(8), border: Border.all(color: kRed.withOpacity(0.2), width: 0.5)),
                child: const Icon(Icons.delete_outline, size: 17, color: kRed)),
            ),
          ]),
        ),

        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          // Name section
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const AppLabel('Nom du prompt'),
                const Spacer(),
                if (!_editingName)
                  GestureDetector(
                    onTap: _startEditName,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.edit_outlined, size: 13, color: kMuted2),
                      const SizedBox(width: 4),
                      Text('Modifier', style: GoogleFonts.inter(color: kMuted2, fontSize: 11.5)),
                    ]),
                  ),
              ]),
              const SizedBox(height: 10),
              if (_editingName) ...[
                AppInput(controller: _nameCtrl, autofocus: true, hint: 'Nom du prompt', onSubmitted: (_) => _confirmName()),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  AppButton(label: 'Annuler', variant: AppButtonVariant.ghost, onTap: () => setState(() => _editingName = false), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7)),
                  const SizedBox(width: 8),
                  AppButton(label: 'Confirmer', onTap: _confirmName, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7)),
                ]),
              ] else
                Text(_name, style: GoogleFonts.inter(color: kText, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
            ]),
          ),
          const SizedBox(height: 10),

          // Local metadata (always shown)
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              if (num != null) ...[_MetaRow('Numéro', num, icon: Icons.tag), const AppDivider()],
              _MetaRow('ID', p.id, icon: Icons.fingerprint, mono: true),
              const AppDivider(),
              _MetaRow('Date', _fmtDate(p.created), icon: Icons.calendar_today_outlined),
              const AppDivider(),
              _MetaRow('Heure', _fmtTime(p.created), icon: Icons.access_time_outlined),
              if (meta.containsKey('Room')) ...[
                const AppDivider(),
                _MetaRow('Room', meta['Room']!, icon: Icons.workspaces_outlined),
              ],
            ]),
          ),
          const SizedBox(height: 10),

          // Link
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const AppLabel('Lien GitHub'),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
                child: Text(p.link, style: GoogleFonts.robotoMono(color: kBlue, fontSize: 11.5), maxLines: 3),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: AppButton(
                  label: _copiedLink ? 'Copié !' : 'Copier le lien',
                  icon: _copiedLink ? Icons.check : Icons.link,
                  variant: _copiedLink ? AppButtonVariant.secondary : AppButtonVariant.outline,
                  fullWidth: true,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: p.link));
                    setState(() => _copiedLink = true);
                    Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _copiedLink = false); });
                  },
                  padding: const EdgeInsets.symmetric(vertical: 10),
                )),
                const SizedBox(width: 8),
                Expanded(child: AppButton(
                  label: _copiedMd ? 'Copié !' : 'Copier MD',
                  icon: _copiedMd ? Icons.check : Icons.content_copy,
                  variant: _copiedMd ? AppButtonVariant.secondary : AppButtonVariant.ghost,
                  loading: _loadingMd || _loadingContent,
                  fullWidth: true,
                  onTap: (_loadingMd || _loadingContent) ? null : _copyMd,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                )),
              ]),
            ]),
          ),
          const SizedBox(height: 10),

          // Content (metadata filtered out — user sees clean content)
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const AppLabel('Contenu'),
                if (_fromCache) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: kYellow.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                    child: Text('cache', style: GoogleFonts.inter(color: kYellow, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ],
                const Spacer(),
                if (_rawContent != null) ...[
                  GestureDetector(
                    onTap: () { HapticFeedback.selectionClick(); setState(() => _renderMd = !_renderMd); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _renderMd ? kAccentSub : kCard2,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _renderMd ? kAccent.withOpacity(0.3) : kBorder, width: 0.5),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_renderMd ? Icons.format_align_left : Icons.code, size: 11, color: _renderMd ? kAccentMid : kMuted),
                        const SizedBox(width: 4),
                        Text(_renderMd ? 'Rendu' : 'Brut', style: GoogleFonts.inter(color: _renderMd ? kAccentMid : kMuted, fontSize: 11, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (_metaFields.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() => _showMeta = !_showMeta),
                      child: const Icon(Icons.code_outlined, size: 14, color: kMuted2),
                    ),
                ],
                const SizedBox(width: 4),
                if (_loadingContent && _rawContent == null)
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: kAccent)),
              ]),
              const SizedBox(height: 12),
              if (_loadingContent && _rawContent == null)
                const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: AppLoadingIndicator()))
              else if (_rawContent == null)
                const AppEmptyState(icon: Icons.cloud_off, title: 'Non disponible', subtitle: 'Vérifie ta connexion ou ton token')
              else if (_renderMd && !_showMeta)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
                  child: MarkdownBody(
                    data: _displayContent,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: GoogleFonts.inter(color: kText2, fontSize: 13, height: 1.65),
                      h1: GoogleFonts.inter(color: kText, fontSize: 18, fontWeight: FontWeight.w700),
                      h2: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600),
                      h3: GoogleFonts.inter(color: kText, fontSize: 13.5, fontWeight: FontWeight.w600),
                      code: GoogleFonts.robotoMono(color: kAccentMid, fontSize: 12, backgroundColor: kAccentSub),
                      codeblockDecoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
                      blockquoteDecoration: BoxDecoration(border: Border(left: BorderSide(color: kAccent, width: 3)), color: kAccentSub.withOpacity(0.3)),
                      listBullet: GoogleFonts.inter(color: kAccentMid, fontSize: 13),
                      strong: GoogleFonts.inter(color: kText, fontWeight: FontWeight.w700),
                      em: GoogleFonts.inter(color: kText2, fontStyle: FontStyle.italic),
                      a: GoogleFonts.inter(color: kBlue, decoration: TextDecoration.underline),
                      horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: kBorder, width: 0.5))),
                    ),
                    imageBuilder: (uri, title, alt) {
                      if (uri.data != null) {
                        try {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(uri.data!.contentAsBytes(), fit: BoxFit.contain),
                            ),
                          );
                        } catch (_) {}
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                )
              else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
                  child: SelectableText(
                    _showMeta ? _rawContent! : _displayContent,
                    style: GoogleFonts.robotoMono(color: kText2, fontSize: 12, height: 1.7),
                  ),
                ),
                if (_showMeta) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.lock_outline, size: 11, color: kMuted2),
                    const SizedBox(width: 4),
                    Expanded(child: Text('Les métadonnées sont cachées dans le rendu — l\'IA y a accès.', style: GoogleFonts.inter(color: kMuted2, fontSize: 11))),
                  ]),
                ],
              ],
            ]),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ])),
      ])),
    );
  }

  String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')} ${_month(d.month)} ${d.year}';
  String _fmtTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
  String _month(int m) => const ['jan', 'fév', 'mar', 'avr', 'mai', 'jun', 'jul', 'aoû', 'sep', 'oct', 'nov', 'déc'][m - 1];
}

class _MetaRow extends StatelessWidget {
  final String label, value; final IconData? icon; final bool mono;
  const _MetaRow(this.label, this.value, {this.icon, this.mono = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(children: [
      if (icon != null) ...[Icon(icon, size: 14, color: kMuted2), const SizedBox(width: 8)],
      Text(label, style: GoogleFonts.inter(color: kMuted, fontSize: 13)),
      const Spacer(),
      Text(value, style: mono ? GoogleFonts.robotoMono(color: kText2, fontSize: 12) : GoogleFonts.inter(color: kText2, fontSize: 13, fontWeight: FontWeight.w500), textAlign: TextAlign.end),
    ]),
  );
}
