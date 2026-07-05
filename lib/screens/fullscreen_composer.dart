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
import 'image_edit_screen.dart';

class FullscreenComposerScreen extends StatefulWidget {
  final String initialText;
  final List<AttachedFile> initialFiles;
  final GitHubService github;
  final List<Room> preloadedRooms;

  const FullscreenComposerScreen({
    super.key,
    this.initialText = '',
    this.initialFiles = const [],
    required this.github,
    this.preloadedRooms = const [],
  });

  @override
  State<FullscreenComposerScreen> createState() => _FullscreenComposerScreenState();
}

class _FullscreenComposerScreenState extends State<FullscreenComposerScreen> {
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();
  late List<AttachedFile> _files;
  bool _sending = false;
  String? _mentionQuery;
  List<Room> _rooms = [];

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
    _files = List.from(widget.initialFiles);
    _rooms = List.from(widget.preloadedRooms);
    _ctrl.addListener(_onCtrlChange);
    if (_rooms.isEmpty) _loadRooms();
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrlChange);
    _ctrl.dispose();
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
    if (!_ctrl.selection.isValid || pos < 0) {
      if (_mentionQuery != null) setState(() => _mentionQuery = null);
      return;
    }
    final before = _ctrl.text.substring(0, pos.clamp(0, _ctrl.text.length));
    final match  = RegExp(r'@(\w*)$').firstMatch(before);
    final q = match?.group(1);
    if (q != _mentionQuery) setState(() => _mentionQuery = q);
  }

  List<AttachedFile> get _mentionSuggestions {
    if (_mentionQuery == null || _files.isEmpty) return [];
    if (_mentionQuery!.isEmpty) return _files;
    return _files.where((f) => f.name.toLowerCase().contains(_mentionQuery!.toLowerCase())).toList();
  }

  void _insertMention(AttachedFile f) {
    final pos = _ctrl.selection.baseOffset;
    if (pos < 0) return;
    final before = _ctrl.text.substring(0, pos);
    final after  = _ctrl.text.substring(pos);
    final match  = RegExp(r'@(\w*)$').firstMatch(before);
    final mention = '@${f.name.replaceAll(' ', '_').replaceAll('.', '_')}';
    final newBefore = match != null ? before.substring(0, match.start) + mention : before + mention;
    _ctrl.value = TextEditingValue(
      text: newBefore + after,
      selection: TextSelection.collapsed(offset: newBefore.length),
    );
    setState(() => _mentionQuery = null);
  }

  // ── Name cleaning: img.name first, fallback to path ───────────────────────
  String _cleanImageName(dynamic img, int index) {
    // Prioritize img.name (original filename from gallery)
    final imgName = img.name as String? ?? '';
    final pathParts = (img.path as String).split('/');
    final pathName = pathParts.isNotEmpty ? pathParts.last : '';

    // Check img.name first — it preserves the original gallery filename
    for (final candidate in [imgName, pathName]) {
      if (candidate.isEmpty) continue;
      if (_isTempName(candidate)) continue;
      return _sanitizeName(candidate);
    }
    return _stampName(index);
  }

  bool _isTempName(String n) {
    final l = n.toLowerCase();
    return l.isEmpty ||
        l.startsWith('image_picker_') ||
        l.startsWith('picker_') ||
        l.startsWith('scaled_') ||
        l.startsWith('img_') ||
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}').hasMatch(l) ||
        RegExp(r'^\d{10,}').hasMatch(l.replaceAll(RegExp(r'\.\w+$'), ''));
  }

  String _sanitizeName(String n) {
    return n.replaceAll(' ', '_').replaceAll(RegExp(r'[^\w.\-]'), '');
  }

  String _stampName(int idx) {
    final t = DateTime.now();
    final s = idx > 0 ? '_$idx' : '';
    return 'photo_${t.year}${_p(t.month)}${_p(t.day)}_${_p(t.hour)}${_p(t.minute)}${_p(t.second)}$s.jpg';
  }

  String _p(int n) => n.toString().padLeft(2, '0');

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
        final name = _cleanImageName(imgs[i], i);
        if (mounted) setState(() => _files.insert(0, AttachedFile(name: name, bytes: bytes, isImage: true)));
      }
    } catch (_) {}
  }

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
        content: AppInput(controller: ctrl, autofocus: true, suffixText: ext, hint: 'Nom', onSubmitted: (v) => Navigator.pop(_, v.trim())),
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

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) return;
    final pos = _ctrl.selection.isValid ? _ctrl.selection.baseOffset : _ctrl.text.length;
    final before = _ctrl.text.substring(0, pos);
    final after  = _ctrl.text.substring(pos);
    _ctrl.value = TextEditingValue(
      text: before + data.text! + after,
      selection: TextSelection.collapsed(offset: pos + data.text!.length),
    );
    setState(() {});
  }

  Future<void> _send() async {
    if (_ctrl.text.trim().isEmpty && _files.isEmpty) return;
    final defaultName = _ctrl.text.trim().split(' ').take(5).join(' ');
    final result = await showModalBottomSheet<SendResult>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => SendSheet(promptText: _ctrl.text.trim(), preloadedRooms: _rooms, github: widget.github),
    );
    if (result == null) return;

    setState(() => _sending = true);
    try {
      final text  = _ctrl.text;
      final files = List<AttachedFile>.from(_files);
      final id    = DateTime.now().millisecondsSinceEpoch.toString();
      String? roomContext;
      if (result.room != null) roomContext = await widget.github.fetchContext(result.room!.id);
      final link   = await widget.github.pushDirectPrompt(id, text, files, room: result.room, roomContext: roomContext);
      final name   = result.name.isNotEmpty ? result.name : defaultName;
      final prompt = SavedPrompt(id: id, name: name, link: link, created: DateTime.now());
      final saved  = await PrefsService.addPrompt(prompt);
      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (e) {
      setState(() => _sending = false);
      if (mounted) showAppSnack(context, e.toString().replaceAll('Exception: ', ''), isError: true);
    }
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
            subtitle: Text('Luminosité · Contraste · Dessin', style: GoogleFonts.inter(color: kMuted2, fontSize: 11.5)),
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

  @override
  Widget build(BuildContext context) {
    final hasContent = _ctrl.text.trim().isNotEmpty || _files.isNotEmpty;
    final mentions = _mentionSuggestions;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(width: 34, height: 34, decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
                child: const Icon(Icons.close, size: 17, color: kMuted)),
            ),
            const SizedBox(width: 12),
            Text('Composer', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
            const Spacer(),
          ]),
        ),

        // Unified composer box — fills remaining space, one rounded container
        Expanded(child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: kBorder, width: 0.5),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Images preview strip (inside the box, ChatGPT-style)
              if (_files.any((f) => f.isImage))
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  child: SizedBox(
                    height: 76,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _files.where((f) => f.isImage).length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final imgFiles = _files.where((f) => f.isImage).toList();
                        final f = imgFiles[i];
                        final idx = _files.indexOf(f);
                        return GestureDetector(
                          onTap: () => _showImagePreview(f.bytes, f.name),
                          onLongPress: () => _showFileMenu(idx),
                          child: Stack(children: [
                            ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(f.bytes, width: 74, height: 74, fit: BoxFit.cover)),
                            Positioned(
                              bottom: 2, left: 2,
                              child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                                child: const Icon(Icons.edit, size: 9, color: Colors.white70)),
                            ),
                            Positioned(
                              top: 2, right: 2,
                              child: GestureDetector(
                                onTap: () => setState(() => _files.removeAt(idx)),
                                child: Container(width: 18, height: 18,
                                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, size: 11, color: Colors.white70)),
                              ),
                            ),
                          ]),
                        );
                      },
                    ),
                  ),
                ),

              // Non-image file chips (inside the box)
              if (_files.any((f) => !f.isImage))
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: Wrap(spacing: 6, runSpacing: 6, children: _files.where((f) => !f.isImage).map((f) {
                    final idx = _files.indexOf(f);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.attach_file, size: 14, color: kAccentMid),
                        const SizedBox(width: 4),
                        Text(f.name, style: GoogleFonts.inter(color: kMuted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(width: 4),
                        GestureDetector(onTap: () => setState(() => _files.removeAt(idx)), child: const Icon(Icons.close, size: 13, color: kMuted2)),
                      ]),
                    );
                  }).toList()),
                ),

              // Mention overlay (inside the box, above the text field)
              if (_mentionQuery != null && mentions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  constraints: const BoxConstraints(maxHeight: 150),
                  decoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder, width: 0.5)),
                  child: ListView.builder(
                    shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 4), itemCount: mentions.length,
                    itemBuilder: (_, i) {
                      final f = mentions[i];
                      return ListTile(
                        dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        leading: f.isImage
                            ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.memory(f.bytes, width: 30, height: 30, fit: BoxFit.cover))
                            : const Icon(Icons.attach_file, size: 20, color: kAccentMid),
                        title: Text('@${f.name.replaceAll(' ', '_').replaceAll('.', '_')}', style: GoogleFonts.inter(color: kAccentMid, fontSize: 13)),
                        onTap: () => _insertMention(f),
                      );
                    },
                  ),
                ),

              // Main text area — flexes to fill remaining box height
              Expanded(child: TextField(
                controller: _ctrl, focusNode: _focus,
                maxLines: null, expands: true,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.inter(color: kText, fontSize: 15, height: 1.65),
                cursorColor: kAccent, cursorWidth: 1.5,
                decoration: InputDecoration(
                  hintText: 'Écris ton prompt complet ici…\n\nUtilise @ pour mentionner une image.',
                  hintStyle: GoogleFonts.inter(color: kMuted2, fontSize: 15, height: 1.65),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                ),
              )),

              // Bottom toolbar — part of the same box
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
                child: Row(children: [
                  _ToolBtn(icon: Icons.add_photo_alternate_outlined, onTap: _pickFromGallery, tooltip: 'Image'),
                  _ToolBtn(icon: Icons.attach_file, onTap: _pickFiles, tooltip: 'Fichier'),
                  _ToolBtn(icon: Icons.content_paste_rounded, onTap: _paste, tooltip: 'Coller'),
                  const Spacer(),
                  Text('${_ctrl.text.length} car.', style: GoogleFonts.inter(color: kMuted2, fontSize: 11.5)),
                  if (_files.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text('• ${_files.length} fichier${_files.length > 1 ? "s" : ""}', style: GoogleFonts.inter(color: kMuted2, fontSize: 11.5)),
                  ],
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: (hasContent && !_sending) ? _send : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: hasContent ? kAccent : kCard2,
                        shape: BoxShape.circle,
                        border: Border.all(color: hasContent ? Colors.transparent : kBorder, width: 0.5),
                      ),
                      child: _sending
                          ? const Center(child: SizedBox(width: 15, height: 15, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5)))
                          : Icon(Icons.arrow_upward_rounded, size: 18, color: hasContent ? Colors.white : kMuted2),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        )),
      ])),
    );
  }

  void _showImagePreview(Uint8List bytes, String name) {
    showDialog(
      context: context, barrierColor: Colors.black.withOpacity(0.95),
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
}

class _ToolBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap; final String tooltip;
  const _ToolBtn({required this.icon, required this.onTap, required this.tooltip});
  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon, size: 20, color: kMuted), onPressed: onTap, tooltip: tooltip,
    splashRadius: 20, constraints: const BoxConstraints(minWidth: 38, minHeight: 38), padding: const EdgeInsets.all(7),
  );
}
