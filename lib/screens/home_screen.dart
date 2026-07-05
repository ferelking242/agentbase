import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/github_service.dart';
import '../services/prefs_service.dart';
import '../models/saved_prompt.dart';
import '../models/room.dart';
import '../theme.dart';
import '../widgets/app_components.dart';
import '../widgets/send_sheet.dart';
import '../widgets/prompts_sheet.dart';
import '../services/notification_service.dart';
import 'fullscreen_composer.dart';
import 'image_edit_screen.dart';
import 'notifications_screen.dart';
import 'openspace_screen.dart';
import 'templates_screen.dart';

class HomeScreen extends StatefulWidget {
  final GitHubService github;
  final VoidCallback onOpenDrawer;
  final void Function(SavedPrompt)? onPromptSaved;
  final List<SavedPrompt> prompts;
  final VoidCallback onSyncRequest;
  final void Function(String id) onDeletePrompt;

  const HomeScreen({
    super.key,
    required this.github,
    required this.onOpenDrawer,
    this.onPromptSaved,
    required this.prompts,
    required this.onSyncRequest,
    required this.onDeletePrompt,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<_Msg> _msgs = [];
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  bool _sending = false;
  List<AttachedFile> _files = [];

  // Single @ mention (local files)
  String? _mentionQuery;

  // Double @@ mention (OpenSpace)
  String? _openSpaceQuery;
  List<dynamic> _openSpaceImages = [];
  bool _openSpaceLoading = false;

  List<Room> _rooms = [];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onCtrlChange);
    _loadRooms();
    // Keyboard shortcut: Ctrl+Enter / Cmd+Enter to send
    _focus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter &&
          (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed) &&
          _ctrl.text.trim().isNotEmpty) {
        _send();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrlChange);
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    try {
      final r = await widget.github.fetchRooms();
      if (mounted) setState(() => _rooms = r);
    } catch (_) {}
  }

  void _onCtrlChange() {
    final pos = _ctrl.selection.baseOffset;
    if (!_ctrl.selection.isValid || pos < 0 || pos > _ctrl.text.length) {
      if (_mentionQuery != null || _openSpaceQuery != null) {
        setState(() { _mentionQuery = null; _openSpaceQuery = null; });
      }
      return;
    }
    final before = _ctrl.text.substring(0, pos);

    // Check for @@ (OpenSpace) first — must come before single @ check
    final osMatch = RegExp(r'@@(\w*)$').firstMatch(before);
    if (osMatch != null) {
      final q = osMatch.group(1)!;
      if (_openSpaceQuery != q || _openSpaceImages.isEmpty) {
        setState(() { _openSpaceQuery = q; _mentionQuery = null; });
        _loadOpenSpaceIfNeeded();
      }
      return;
    }

    // Check for single @ (local files)
    final match = RegExp(r'(?<!@)@(\w*)$').firstMatch(before);
    final q = match?.group(1);
    if (q != _mentionQuery || _openSpaceQuery != null) {
      setState(() { _mentionQuery = q; _openSpaceQuery = null; });
    }
  }

  Future<void> _loadOpenSpaceIfNeeded() async {
    if (_openSpaceLoading || _openSpaceImages.isNotEmpty) return;
    setState(() => _openSpaceLoading = true);
    try {
      final imgs = await widget.github.fetchOpenspaceImages();
      if (mounted) setState(() { _openSpaceImages = imgs; _openSpaceLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _openSpaceLoading = false);
    }
  }

  List<AttachedFile> get _mentionSuggestions {
    if (_mentionQuery == null || _files.isEmpty) return [];
    if (_mentionQuery!.isEmpty) return _files;
    return _files.where((f) => f.name.toLowerCase().contains(_mentionQuery!.toLowerCase())).toList();
  }

  List<dynamic> get _openSpaceSuggestions {
    if (_openSpaceQuery == null) return [];
    if (_openSpaceQuery!.isEmpty) return _openSpaceImages;
    final q = _openSpaceQuery!.toLowerCase();
    return _openSpaceImages.where((img) {
      final name = (img['name'] as String? ?? '').toLowerCase();
      final mention = (img['mention'] as String? ?? '').toLowerCase();
      return name.contains(q) || mention.contains(q);
    }).toList();
  }

  void _insertMention(AttachedFile f) {
    final pos = _ctrl.selection.baseOffset;
    if (pos < 0) return;
    final before = _ctrl.text.substring(0, pos);
    final after  = _ctrl.text.substring(pos);
    final match  = RegExp(r'@(\w*)$').firstMatch(before);
    final mention = '@${f.name.replaceAll(' ', '_').replaceAll('.', '_')}';
    final newBefore = match != null ? before.substring(0, match.start) + mention : before + mention;
    _ctrl.value = TextEditingValue(text: newBefore + after, selection: TextSelection.collapsed(offset: newBefore.length));
    setState(() => _mentionQuery = null);
  }

  void _insertOpenSpaceMention(Map<String, dynamic> img) {
    final pos = _ctrl.selection.baseOffset;
    if (pos < 0) return;
    final before = _ctrl.text.substring(0, pos);
    final after  = _ctrl.text.substring(pos);
    final match  = RegExp(r'@@(\w*)$').firstMatch(before);
    final mention = img['mention'] as String? ?? '@image';
    final newBefore = match != null ? before.substring(0, match.start) + mention : before + mention;
    _ctrl.value = TextEditingValue(text: newBefore + after, selection: TextSelection.collapsed(offset: newBefore.length));
    setState(() { _openSpaceQuery = null; });
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const AppDragHandle(),
          _AttachOption(icon: Icons.folder_outlined, title: 'Fichiers', subtitle: 'Tout type de fichier', onTap: () { Navigator.pop(context); _pickFiles(); }),
          _AttachOption(icon: Icons.photo_library_outlined, title: 'Galerie', subtitle: 'Photos et images', onTap: () { Navigator.pop(context); _pickFromGallery(); }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _pickFiles() async {
    try {
      final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true, type: FileType.any);
      if (res == null) return;
      setState(() {
        for (final f in res.files) {
          if (f.bytes == null) continue;
          final n = f.name.toLowerCase();
          _files.insert(0, AttachedFile(
            name: f.name, bytes: f.bytes!,
            isImage: n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.gif') || n.endsWith('.webp'),
          ));
        }
      });
    } catch (_) {}
  }

  Future<void> _pickFromGallery() async {
    try {
      final imgs = await ImagePicker().pickMultiImage(imageQuality: 90);
      if (imgs.isEmpty) return;
      for (int i = 0; i < imgs.length; i++) {
        final bytes = await imgs[i].readAsBytes();
        // Try name from .name, fallback to path basename, then stamp
        final fromName = imgs[i].name;
        final fromPath = imgs[i].path.split('/').last.split('\\').last;
        String name;
        if (!_isTempName(fromName)) {
          name = fromName;
        } else if (!_isTempName(fromPath)) {
          name = fromPath;
        } else {
          name = _stampName(i);
        }
        if (mounted) setState(() => _files.insert(0, AttachedFile(name: name, bytes: bytes, isImage: true)));
      }
    } catch (_) {}
  }

  bool _isTempName(String n) {
    if (n.isEmpty) return true;
    final l = n.toLowerCase();
    // UUID-style names
    if (RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}').hasMatch(l)) return true;
    // Known picker cache patterns
    if (RegExp(r'^image_picker_[0-9a-f]').hasMatch(l)) return true;
    if (RegExp(r'^scaled_[0-9a-f]').hasMatch(l)) return true;
    if (RegExp(r'^img_[0-9]{10,}\.').hasMatch(l)) return true;
    // Purely numeric names (timestamp-only)
    if (RegExp(r'^\d{10,}\.(jpg|jpeg|png|webp)$').hasMatch(l)) return true;
    return false;
  }

  String _stampName(int idx) {
    final t = DateTime.now();
    final s = idx > 0 ? '_$idx' : '';
    return 'photo_${t.year}${_p(t.month)}${_p(t.day)}_${_p(t.hour)}${_p(t.minute)}${_p(t.second)}$s.jpg';
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  Future<void> _editImage(int i) async {
    final f = _files[i];
    if (!f.isImage) return;
    final result = await Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(builder: (_) => ImageEditScreen(bytes: f.bytes, name: f.name)),
    );
    if (result != null && mounted) {
      setState(() => _files[i] = AttachedFile(name: f.name, bytes: result, isImage: true));
    }
  }

  Future<void> _renameFile(int i) async {
    final f   = _files[i];
    final dot = f.name.lastIndexOf('.');
    final nameOnly = dot > 0 ? f.name.substring(0, dot) : f.name;
    final ext      = dot > 0 ? f.name.substring(dot) : '';
    final ctrl = TextEditingController(text: nameOnly);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: kBorder, width: 0.5)),
        title: Text('Renommer', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600)),
        content: AppInput(controller: ctrl, autofocus: true, suffixText: ext, hint: 'Nom du fichier', onSubmitted: (v) => Navigator.pop(_, v.trim())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_), child: Text('Annuler', style: GoogleFonts.inter(color: kMuted))),
          AppButton(label: 'OK', onTap: () => Navigator.pop(_, ctrl.text.trim()), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
        ],
      ),
    );
    ctrl.dispose();
    if (newName != null && newName.isNotEmpty && mounted) {
      setState(() => _files[i] = AttachedFile(name: newName + ext, bytes: f.bytes, isImage: f.isImage));
    }
  }

  // ── Preview ────────────────────────────────────────────────────────────────
  void _showPreview() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) { showAppSnack(context, 'Écris quelque chose d\'abord'); return; }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, maxChildSize: 0.92, minChildSize: 0.3,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(top: BorderSide(color: kBorder, width: 0.5)),
          ),
          child: Column(children: [
            const AppDragHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(children: [
                Text('Prévisualisation', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w700)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(6)),
                  child: Text('${text.length} chars', style: GoogleFonts.inter(color: kMuted2, fontSize: 11.5)),
                ),
              ]),
            ),
            const AppDivider(),
            Expanded(child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(20),
              children: [
                SelectableText(
                  text,
                  style: GoogleFonts.inter(color: kText2, fontSize: 14, height: 1.7),
                ),
              ],
            )),
          ]),
        ),
      ),
    );
  }

  // ── Templates ──────────────────────────────────────────────────────────────
  Future<void> _showTemplates() async {
    final content = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (_) => const TemplatesScreen(pickMode: true)),
    );
    if (content == null || !mounted) return;
    final pos = _ctrl.selection.isValid ? _ctrl.selection.baseOffset : _ctrl.text.length;
    final before = _ctrl.text.substring(0, pos);
    final after = _ctrl.text.substring(pos);
    final separator = before.trim().isEmpty ? '' : '\n\n';
    final newText = before + separator + content;
    _ctrl.value = TextEditingValue(
      text: newText + after,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    setState(() {});
    _focus.requestFocus();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) return;
    final pos    = _ctrl.selection.isValid ? _ctrl.selection.baseOffset : _ctrl.text.length;
    final before = _ctrl.text.substring(0, pos);
    final after  = _ctrl.text.substring(pos);
    _ctrl.value = TextEditingValue(
      text: before + data.text! + after,
      selection: TextSelection.collapsed(offset: pos + data.text!.length),
    );
    setState(() {});
  }

  Future<void> _openFullscreen() async {
    final result = await Navigator.push<SavedPrompt?>(
      context,
      MaterialPageRoute(builder: (_) => FullscreenComposerScreen(
        initialText: _ctrl.text,
        initialFiles: List.from(_files),
        github: widget.github,
        preloadedRooms: _rooms,
      )),
    );
    if (result != null) {
      _ctrl.clear();
      setState(() => _files = []);
      widget.onPromptSaved?.call(result);
    }
  }

  Future<void> _send() async {
    if (_ctrl.text.trim().isEmpty && _files.isEmpty) return;
    final defaultName = _smartTitle(_ctrl.text.trim());
    final result = await showModalBottomSheet<SendResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SendSheet(promptText: _ctrl.text.trim(), preloadedRooms: _rooms, github: widget.github),
    );
    if (result == null) return;

    final text      = _ctrl.text;
    final filesCopy = List<AttachedFile>.from(_files);
    setState(() { _msgs.add(_Msg.user(text, filesCopy, result.room)); _ctrl.clear(); _files = []; _sending = true; });
    _scrollBottom();

    try {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      String? roomContext;
      if (result.room != null) roomContext = await widget.github.fetchContext(result.room!.id);
      final link   = await widget.github.pushDirectPrompt(id, text, filesCopy, room: result.room, roomContext: roomContext);
      final name   = result.name.isNotEmpty ? result.name : defaultName;
      final prompt = SavedPrompt(id: id, name: name, link: link, created: DateTime.now());
      final saved  = await PrefsService.addPrompt(prompt);
      if (!mounted) return;
      setState(() { _msgs.add(_Msg.promptSaved(saved)); _sending = false; });
      widget.onPromptSaved?.call(saved);
      NotificationService.notifyPromptSaved(promptName: name, link: link);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg.agentError('Configure ton token dans Paramètres. (${e.toString().replaceAll("Exception: ", "")})'));
        _sending = false;
      });
    }
    _scrollBottom();
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    });
  }

  void _showPromptsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PromptsSheet(
        prompts: widget.prompts,
        github: widget.github,
        onSync: () { Navigator.pop(context); widget.onSyncRequest(); },
        onDelete: (id) { widget.onDeletePrompt(id); },
      ),
    );
  }

  void _showImageFullscreen(Uint8List bytes, String name) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.95),
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(children: [
              const Spacer(),
              IconButton(icon: const Icon(Icons.close, color: Colors.white60), onPressed: () => Navigator.pop(_)),
            ]),
          ),
          Expanded(child: InteractiveViewer(minScale: 0.5, maxScale: 5, child: Center(child: Image.memory(bytes)))),
          Padding(padding: const EdgeInsets.all(12), child: Text(name, style: GoogleFonts.inter(color: Colors.white38, fontSize: 12), textAlign: TextAlign.center)),
        ])),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty  = _msgs.isEmpty && !_sending;
    final mentions = _mentionSuggestions;
    final osMentions = _openSpaceSuggestions;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _buildHeader(),
      Expanded(
        child: Stack(
          children: [
            Positioned.fill(child: isEmpty ? _buildHome() : _buildMsgs()),
            // OpenSpace @@ overlay (priority)
            if (_openSpaceQuery != null)
              Positioned(bottom: 0, left: 0, right: 0, child: _buildOpenSpaceOverlay(osMentions)),
            // Local @ overlay
            if (_openSpaceQuery == null && _mentionQuery != null && mentions.isNotEmpty)
              Positioned(bottom: 0, left: 0, right: 0, child: _buildMentionOverlay(mentions)),
            // Floating input bar
            Positioned(bottom: 0, left: 0, right: 0, child: _buildInput()),
          ],
        ),
      ),
    ]);
  }

  Widget _buildHeader() => SafeArea(
    bottom: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(color: kBg, border: Border(bottom: BorderSide(color: kBorder, width: 0.5))),
      child: Row(children: [
        GestureDetector(
          onTap: widget.onOpenDrawer,
          child: Container(width: 36, height: 36, decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
            child: const Icon(Icons.menu_rounded, size: 18, color: kMuted)),
        ),
        const SizedBox(width: 10),
        const _ABLogo(),
        const SizedBox(width: 9),
        Text('AgentBase', style: GoogleFonts.inter(color: kText, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        const Spacer(),
        _IconBtn(icon: Icons.sync_rounded, onTap: widget.onSyncRequest, tooltip: 'Sync'),
        const SizedBox(width: 6),
        const NotificationBell(),
        const SizedBox(width: 6),
        _IconBtn(icon: Icons.article_outlined, onTap: _showPromptsSheet, tooltip: 'Prompts',
          badge: widget.prompts.isNotEmpty ? '${widget.prompts.length}' : null),
      ]),
    ),
  );

  // ── @@ OpenSpace overlay ───────────────────────────────────────────────────
  Widget _buildOpenSpaceOverlay(List<dynamic> suggestions) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: kCard,
        border: const Border(
          top: BorderSide(color: kBorder, width: 0.5),
          bottom: BorderSide(color: kBorder, width: 0.5),
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Row(children: [
            Container(width: 20, height: 20, decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(5)),
              child: const Icon(Icons.photo_library_outlined, size: 12, color: kAccentMid)),
            const SizedBox(width: 8),
            Text('OpenSpace', style: GoogleFonts.inter(color: kText, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Text('(@@)', style: GoogleFonts.inter(color: kMuted2, fontSize: 11)),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _openSpaceQuery = null),
              child: const Icon(Icons.close, size: 14, color: kMuted2),
            ),
          ]),
        ),
        const Divider(height: 1, color: kBorder),
        if (_openSpaceLoading)
          const Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(color: kAccent, strokeWidth: 2),
          )
        else if (suggestions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              _openSpaceImages.isEmpty ? 'Aucune image dans OpenSpace' : 'Aucun résultat pour "${_openSpaceQuery}"',
              style: GoogleFonts.inter(color: kMuted2, fontSize: 12),
            ),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true, padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              itemBuilder: (_, i) {
                final img = suggestions[i] as Map<String, dynamic>;
                final name = img['name'] as String? ?? '';
                final mention = img['mention'] as String? ?? '';
                final rawUrl = img['rawUrl'] as String? ?? '';
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: rawUrl.isNotEmpty
                        ? Image.network(rawUrl, width: 40, height: 40, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(width: 40, height: 40, color: kCard2,
                              child: const Icon(Icons.broken_image_outlined, size: 18, color: kMuted2)))
                        : Container(width: 40, height: 40, color: kCard2,
                            child: const Icon(Icons.image_outlined, size: 18, color: kMuted2)),
                  ),
                  title: RichText(text: TextSpan(
                    style: GoogleFonts.inter(color: kText, fontSize: 13),
                    children: [
                      TextSpan(text: mention, style: GoogleFonts.inter(color: kAccentMid, fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  )),
                  subtitle: Text(name, style: GoogleFonts.inter(color: kMuted2, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => _insertOpenSpaceMention(img),
                );
              },
            ),
          ),
      ]),
    );
  }

  Widget _buildMentionOverlay(List<AttachedFile> suggestions) => Container(
    constraints: const BoxConstraints(maxHeight: 180),
    decoration: const BoxDecoration(color: kCard, border: Border(top: BorderSide(color: kBorder, width: 0.5), bottom: BorderSide(color: kBorder, width: 0.5))),
    child: ListView.builder(
      shrinkWrap: true, padding: EdgeInsets.zero, itemCount: suggestions.length,
      itemBuilder: (_, i) {
        final f = suggestions[i];
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: f.isImage
              ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.memory(f.bytes, width: 32, height: 32, fit: BoxFit.cover))
              : Container(width: 32, height: 32, decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(4)),
                  child: const Icon(Icons.insert_drive_file_outlined, size: 16, color: kAccentMid)),
          title: RichText(text: TextSpan(style: GoogleFonts.inter(color: kText, fontSize: 13), children: [
            TextSpan(text: '@', style: GoogleFonts.inter(color: kAccentMid, fontWeight: FontWeight.w700)),
            TextSpan(text: f.name.replaceAll(' ', '_').replaceAll('.', '_')),
          ])),
          onTap: () => _insertMention(f),
        );
      },
    ),
  );

  Widget _buildHome() => ListView(padding: const EdgeInsets.only(bottom: 120), children: [
    const SizedBox(height: 48),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(children: [
        Text('Que puis-je faire pour toi ?',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: kText, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.6, height: 1.3)),
        const SizedBox(height: 6),
        Text('Compose un prompt, attache des fichiers, envoie dans une room.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: kMuted2, fontSize: 13, height: 1.5)),
      ]),
    ),
    const SizedBox(height: 24),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(children: [
        Row(children: [
          Expanded(child: Padding(padding: const EdgeInsets.only(right: 6),
            child: _ActionCard(icon: Icons.open_in_full_rounded, label: 'Plein écran', subtitle: 'Composer', color: kAccentMid, onTap: _openFullscreen))),
          Expanded(child: _ActionCard(icon: Icons.workspaces_outlined, label: 'Mes Rooms', subtitle: 'Naviguer', color: kYellow, onTap: widget.onOpenDrawer)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Padding(padding: const EdgeInsets.only(right: 6),
            child: _ActionCard(icon: Icons.notifications_outlined, label: 'Notifications', subtitle: 'Activité', color: kGreen, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen()))))),
          Expanded(child: _ActionCard(icon: Icons.photo_library_outlined, label: 'OpenSpace', subtitle: 'Galerie partagée', color: const Color(0xFF8B5CF6), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OpenspaceScreen(github: widget.github))))),
        ]),
      ]),
    ),
    const SizedBox(height: 16),
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text('DÉMARRER AVEC', style: GoogleFonts.inter(color: kMuted2, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        Expanded(child: Padding(padding: const EdgeInsets.only(right: 6),
          child: _SuggCard(icon: Icons.lightbulb_outline, label: 'Analyser un problème',
            onTap: () { _ctrl.text = 'Analyser ce problème : '; _focus.requestFocus(); setState(() {}); }))),
        Expanded(child: _SuggCard(icon: Icons.rule_outlined, label: 'Créer une règle agent',
          onTap: () { _ctrl.text = 'Créer une règle agent : '; _focus.requestFocus(); setState(() {}); })),
      ]),
    ),
    const SizedBox(height: 40),
  ]);

  Widget _buildMsgs() => ListView.builder(
    controller: _scroll,
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
    itemCount: _msgs.length + (_sending ? 1 : 0),
    itemBuilder: (_, i) {
      if (i == _msgs.length) return const _TypingDots();
      final m = _msgs[i];
      return m.isUser ? _UserBubble(msg: m, onImageTap: _showImageFullscreen) : _AgentBubble(msg: m);
    },
  );

  Widget _buildInput() {
    final hasContent = _ctrl.text.trim().isNotEmpty || _files.isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Container(
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: kBorder, width: 0.5),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Images inside the box (like ChatGPT)
            if (_files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: SizedBox(
                  height: 76,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _files.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) => _FileChip(
                      file: _files[i],
                      onTap: _files[i].isImage ? () => _showImageFullscreen(_files[i].bytes, _files[i].name) : null,
                      onLongPress: () => _showFileMenu(i),
                      onRemove: () => setState(() => _files.removeAt(i)),
                    ),
                  ),
                ),
              ),
            TextField(
              controller: _ctrl, focusNode: _focus, maxLines: 6, minLines: 1,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.inter(color: kText, fontSize: 14, height: 1.5),
              cursorColor: kAccent, cursorWidth: 1.5,
              decoration: InputDecoration(
                hintText: 'Écris ton prompt… ou tape @ ou @@',
                hintStyle: GoogleFonts.inter(color: kMuted2, fontSize: 14),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                isDense: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Row(children: [
                _ToolBtn(icon: Icons.add, onTap: _showAttachMenu, tooltip: 'Joindre'),
                _ToolBtn(icon: Icons.auto_awesome_outlined, onTap: _showTemplates, tooltip: 'Templates'),
                const Spacer(),
                _ToolBtn(icon: Icons.open_in_full_rounded, onTap: _openFullscreen, tooltip: 'Plein écran'),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: hasContent ? _send : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: hasContent ? kAccent : kCard2,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: hasContent ? Colors.transparent : kBorder, width: 0.5),
                    ),
                    child: Icon(Icons.arrow_upward_rounded, size: 18, color: hasContent ? Colors.white : kMuted2),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  void _showFileMenu(int i) {
    final f = _files[i];
    showModalBottomSheet(
      context: context, backgroundColor: kCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
        const AppDragHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(children: [
            const Icon(Icons.insert_drive_file_outlined, size: 16, color: kMuted2),
            const SizedBox(width: 8),
            Expanded(child: Text(f.name, style: GoogleFonts.inter(color: kText, fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
        const AppDivider(),
        if (f.isImage)
          ListTile(
            leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.edit_outlined, size: 18, color: kAccentMid)),
            title: Text('Éditer l\'image', style: GoogleFonts.inter(color: kText, fontSize: 14)),
            subtitle: Text('Réglages · Rogner · Dessin · Rotation', style: GoogleFonts.inter(color: kMuted2, fontSize: 11.5)),
            onTap: () { Navigator.pop(context); _editImage(i); },
          ),
        ListTile(
          leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.drive_file_rename_outline, size: 18, color: kMuted)),
          title: Text('Renommer', style: GoogleFonts.inter(color: kText, fontSize: 14)),
          onTap: () { Navigator.pop(context); _renameFile(i); },
        ),
        ListTile(
          leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: kRedSub.withOpacity(0.5), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.delete_outline, size: 18, color: kRed)),
          title: Text('Supprimer', style: GoogleFonts.inter(color: kRed, fontSize: 14)),
          onTap: () { Navigator.pop(context); setState(() => _files.removeAt(i)); },
        ),
        const SizedBox(height: 8),
      ])),
    );
  }
}

// ── _FileChip ─────────────────────────────────────────────────────────────────
class _FileChip extends StatelessWidget {
  final AttachedFile file;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onRemove;
  const _FileChip({required this.file, this.onTap, this.onLongPress, required this.onRemove});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap, onLongPress: onLongPress,
    child: Stack(children: [
      file.isImage
          ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(file.bytes, width: 78, height: 78, fit: BoxFit.cover))
          : Container(
              width: 78, height: 78,
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder, width: 0.5)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.insert_drive_file_outlined, color: kAccentMid, size: 24),
                const SizedBox(height: 3),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(file.name, style: GoogleFonts.inter(color: kMuted2, fontSize: 8.5), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
              ])),
      if (file.isImage) Positioned(
        bottom: 3, left: 3,
        child: GestureDetector(
          onTap: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.75), borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.edit, size: 12, color: Colors.white),
              SizedBox(width: 3),
              Text('Éditer', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
      Positioned(
        top: 2, right: 2,
        child: GestureDetector(
          onTap: onRemove,
          child: Container(
            width: 18, height: 18,
            decoration: BoxDecoration(color: kBg.withOpacity(0.85), shape: BoxShape.circle, border: Border.all(color: kBorder, width: 0.5)),
            child: const Icon(Icons.close, size: 11, color: kText),
          ),
        ),
      ),
    ]),
  );
}

// ── _ToolBtn / _IconBtn ───────────────────────────────────────────────────────
class _ToolBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap; final String tooltip;
  const _ToolBtn({required this.icon, required this.onTap, required this.tooltip});
  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon, size: 18, color: kMuted2), onPressed: onTap, tooltip: tooltip,
    splashRadius: 18, constraints: const BoxConstraints(minWidth: 34, minHeight: 34), padding: const EdgeInsets.all(6),
  );
}

class _IconBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap; final String tooltip; final String? badge;
  const _IconBtn({required this.icon, required this.onTap, required this.tooltip, this.badge});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Stack(clipBehavior: Clip.none, children: [
      Container(width: 36, height: 36, decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
        child: Icon(icon, size: 17, color: kMuted)),
      if (badge != null) Positioned(
        top: -4, right: -4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(99)),
          child: Text(badge!, style: GoogleFonts.inter(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );
}

class _ActionCard extends StatelessWidget {
  final IconData icon; final String label, subtitle; final Color color; final VoidCallback onTap;
  const _ActionCard({required this.icon, required this.label, required this.subtitle, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder, width: 0.5)),
      child: Row(children: [
        Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 17, color: color)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.inter(color: kText, fontSize: 12.5, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(subtitle, style: GoogleFonts.inter(color: kMuted2, fontSize: 11)),
        ])),
      ]),
    ),
  );
}

class _SuggCard extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _SuggCard({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder, width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 30, height: 30, decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 15, color: kAccentMid)),
        const SizedBox(height: 10),
        Text(label, style: GoogleFonts.inter(color: kText2, fontSize: 12.5, height: 1.4)),
      ]),
    ),
  );
}

class _AttachOption extends StatelessWidget {
  final IconData icon; final String title, subtitle; final VoidCallback onTap;
  const _AttachOption({required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: kAccentMid, size: 20)),
    title: Text(title, style: GoogleFonts.inter(color: kText, fontSize: 14, fontWeight: FontWeight.w500)),
    subtitle: Text(subtitle, style: GoogleFonts.inter(color: kMuted2, fontSize: 12)),
    onTap: onTap,
  );
}

// ── Msg model ─────────────────────────────────────────────────────────────────
enum _MsgKind { user, promptSaved, agentError }

class _Msg {
  final _MsgKind kind;
  final String text;
  final List<AttachedFile> files;
  final Room? room;
  final SavedPrompt? prompt;
  _Msg._({required this.kind, this.text = '', this.files = const [], this.room, this.prompt});
  factory _Msg.user(String t, List<AttachedFile> f, Room? r) => _Msg._(kind: _MsgKind.user, text: t, files: f, room: r);
  factory _Msg.promptSaved(SavedPrompt p) => _Msg._(kind: _MsgKind.promptSaved, prompt: p);
  factory _Msg.agentError(String t) => _Msg._(kind: _MsgKind.agentError, text: t);
  bool get isUser => kind == _MsgKind.user;
}

// ── _UserBubble ───────────────────────────────────────────────────────────────
class _UserBubble extends StatelessWidget {
  final _Msg msg;
  final void Function(Uint8List, String) onImageTap;
  const _UserBubble({required this.msg, required this.onImageTap});

  AttachedFile? _findFile(String mention) {
    final needle = mention.toLowerCase();
    for (final f in msg.files) {
      final normalized = f.name.replaceAll(' ', '_').replaceAll('.', '_').toLowerCase();
      if (normalized == needle || f.name.toLowerCase() == needle) return f;
      if (normalized.startsWith(needle) || needle.startsWith(normalized.split('_').first)) return f;
    }
    return null;
  }

  Set<String> _mentionedFileNames() {
    final pattern = RegExp(r'@(\w+)');
    final found = <String>{};
    for (final m in pattern.allMatches(msg.text)) {
      final f = _findFile(m.group(1)!);
      if (f != null) found.add(f.name);
    }
    return found;
  }

  Widget _buildContent() {
    final text = msg.text;
    final pattern = RegExp(r'@(\w+)');
    final matches = pattern.allMatches(text).toList();
    final textStyle = GoogleFonts.inter(color: Colors.white, fontSize: 13.5, height: 1.5);
    if (matches.isEmpty) return Text(text, style: textStyle);
    final seenFiles = <String>{};
    final widgets = <Widget>[];
    int lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        final t = text.substring(lastEnd, match.start).trimRight();
        if (t.isNotEmpty) widgets.add(Text(t, style: textStyle));
      }
      final f = _findFile(match.group(1)!);
      if (f != null && f.isImage) {
        if (seenFiles.contains(f.name)) {
          widgets.add(Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(6)),
            child: Text('${match.group(0)} ↑', style: GoogleFonts.inter(color: Colors.white60, fontSize: 11.5)),
          ));
        } else {
          seenFiles.add(f.name);
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: GestureDetector(
              onTap: () => onImageTap(f.bytes, f.name),
              child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(f.bytes, width: double.infinity, fit: BoxFit.cover)),
            ),
          ));
        }
      } else {
        widgets.add(Text(match.group(0)!, style: GoogleFonts.inter(color: kAccentMid, fontSize: 13.5, fontWeight: FontWeight.w600)));
      }
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      final t = text.substring(lastEnd).trimLeft();
      if (t.isNotEmpty) widgets.add(Padding(padding: const EdgeInsets.only(top: 4), child: Text(t, style: textStyle)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  @override
  Widget build(BuildContext context) {
    final mentioned = _mentionedFileNames();
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (msg.files.any((f) => f.isImage && !mentioned.contains(f.name)))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.end,
                  children: msg.files.where((f) => f.isImage && !mentioned.contains(f.name)).map((f) =>
                    GestureDetector(
                      onTap: () => onImageTap(f.bytes, f.name),
                      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(f.bytes, width: 64, height: 64, fit: BoxFit.cover)),
                    )
                  ).toList(),
                ),
              ),
            ...msg.files.where((f) => !f.isImage).map((f) => Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(6), border: Border.all(color: kBorder, width: 0.5)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.attach_file, size: 12, color: kAccentMid),
                const SizedBox(width: 4),
                Text(f.name, style: GoogleFonts.inter(color: kMuted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            )),
            if (msg.text.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: const BoxDecoration(
                  color: kAccent,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(14), topRight: Radius.circular(14),
                    bottomLeft: Radius.circular(14), bottomRight: Radius.circular(3),
                  ),
                ),
                child: _buildContent(),
              ),
            if (msg.room != null) Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.workspaces_outlined, size: 10, color: kAccentMid.withOpacity(0.7)),
                const SizedBox(width: 3),
                Text(msg.room!.name, style: GoogleFonts.inter(color: kMuted2, fontSize: 10.5)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── _AgentBubble ──────────────────────────────────────────────────────────────
class _AgentBubble extends StatelessWidget {
  final _Msg msg;
  const _AgentBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isError = msg.kind == _MsgKind.agentError;
    if (msg.kind == _MsgKind.promptSaved) {
      final p = msg.prompt!;
      final num = p.number > 0 ? ' #${p.number}' : '';
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppCard(
          padding: const EdgeInsets.all(12),
          color: kGreenSub.withOpacity(0.5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.check_circle_outline, size: 15, color: kGreen),
              const SizedBox(width: 6),
              if (p.number > 0) ...[AppBadge('Prompt$num', bg: kGreenSub, fg: kGreen), const SizedBox(width: 8)],
              Expanded(child: Text(p.name, style: GoogleFonts.inter(color: kText, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async { await Clipboard.setData(ClipboardData(text: p.link)); showAppSnack(context, 'Lien copié !'); },
              child: Text(p.link, style: GoogleFonts.robotoMono(color: kBlue, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 6),
            Row(children: [
              GestureDetector(
                onTap: () async {
                  final md = '[${p.name}](${p.link})';
                  await Clipboard.setData(ClipboardData(text: md));
                  if (context.mounted) showAppSnack(context, 'Lien Markdown copié !');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: kGreenSub, borderRadius: BorderRadius.circular(6), border: Border.all(color: kGreen.withOpacity(0.2), width: 0.5)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.copy, size: 11, color: kGreen),
                    const SizedBox(width: 4),
                    Text('Copier MD', style: GoogleFonts.inter(color: kGreen, fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ]),
          ]),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isError ? kRedSub.withOpacity(0.6) : kCard,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(3), topRight: Radius.circular(14), bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
              border: Border.all(color: isError ? kRed.withOpacity(0.3) : kBorder, width: 0.5),
            ),
            child: Text(msg.text, style: GoogleFonts.inter(color: isError ? kRed : kText2, fontSize: 13.5, height: 1.5)),
          ),
        ),
      ),
    );
  }
}

// ── _TypingDots ───────────────────────────────────────────────────────────────
class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override State<_TypingDots> createState() => _TypingDotsState();
}
class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = ((_ctrl.value - i * 0.15) % 1.0).clamp(0.0, 1.0);
        final opacity = (0.3 + 0.7 * (t < 0.5 ? t * 2 : (1 - t) * 2)).clamp(0.3, 1.0);
        return Container(margin: const EdgeInsets.only(right: 4), width: 7, height: 7,
          decoration: BoxDecoration(color: kMuted2.withOpacity(opacity), shape: BoxShape.circle));
      },
    ))),
  );
}

// ── Smart title generator ─────────────────────────────────────────────────────
String _smartTitle(String raw) {
  if (raw.isEmpty) return '';
  var s = raw
      .replaceAll(RegExp(r'#{1,6}\s*'), '')
      .replaceAll(RegExp(r'[*_`~>]'), '')
      .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)', dotAll: true), r'$1')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // Take first sentence (end at . ? ! followed by space or end)
  final sentMatch = RegExp(r'^(.+?[.?!])(\s|$)').firstMatch(s);
  if (sentMatch != null && sentMatch.group(1)!.length >= 8) {
    s = sentMatch.group(1)!.trim();
  }
  // Fallback: first line
  final firstLine = s.split('\n').first.trim();
  if (firstLine.isNotEmpty) s = firstLine;
  // Truncate at word boundary
  if (s.length > 60) {
    s = s.substring(0, 57);
    final last = s.lastIndexOf(' ');
    if (last > 15) s = s.substring(0, last);
    s = '$s…';
  }
  return s.isNotEmpty ? s : raw.split(' ').take(5).join(' ');
}

// ── Professional AB Logo ──────────────────────────────────────────────────────
class _ABLogo extends StatelessWidget {
  const _ABLogo();

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(28, 28),
    painter: _ABLogoPainter(),
  );
}

class _ABLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final r = w * 0.22;

    // Background rect
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(r)), bgPaint);

    // Draw ">" symbol — terminal / agent feel
    final stroke = Paint()
      ..color = Colors.white.withOpacity(0.95)
      ..strokeWidth = w * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final cx = w * 0.42, cy = h * 0.5, hw = w * 0.18, hh = h * 0.22;
    final path = Path()
      ..moveTo(cx - hw, cy - hh)
      ..lineTo(cx + hw, cy)
      ..lineTo(cx - hw, cy + hh);
    canvas.drawPath(path, stroke);

    // Small dot after ">"
    final dot = Paint()..color = Colors.white.withOpacity(0.75)..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx + hw * 1.9, cy), w * 0.065, dot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
