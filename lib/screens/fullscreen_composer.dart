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
  bool _showActions = false;
  List<Room> _rooms = [];

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
    _files = List.from(widget.initialFiles);
    _rooms = List.from(widget.preloadedRooms);
    _ctrl.addListener(() => setState(() {}));
    if (_rooms.isEmpty) _loadRooms();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
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
        final name = imgs[i].name.isNotEmpty ? imgs[i].name : 'photo_$i.jpg';
        if (mounted) setState(() => _files.insert(0, AttachedFile(name: name, bytes: bytes, isImage: true)));
      }
    } catch (_) {}
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

  @override
  Widget build(BuildContext context) {
    final hasContent = _ctrl.text.trim().isNotEmpty || _files.isNotEmpty;
    return Scaffold(
      backgroundColor: kBg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Full-screen text area ──────────────────────────────────────
            Positioned.fill(
              child: GestureDetector(
                onTap: () { _focus.requestFocus(); if (_showActions) setState(() => _showActions = false); },
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.inter(color: kText, fontSize: 17, height: 1.7),
                  cursorColor: kAccent,
                  cursorWidth: 2,
                  decoration: InputDecoration(
                    hintText: 'Écris ton prompt…',
                    hintStyle: GoogleFonts.inter(color: kMuted2, fontSize: 17, height: 1.7),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(22, 60, 22, 120),
                  ),
                ),
              ),
            ),

            // ── Top-left: close button (always visible, minimal) ───────────
            Positioned(
              top: 8, left: 12,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 16, color: kMuted),
                ),
              ),
            ),

            // ── Top-right: files count badge + toggle actions ─────────────
            Positioned(
              top: 8, right: 12,
              child: GestureDetector(
                onTap: () => setState(() => _showActions = !_showActions),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_files.isNotEmpty) ...[
                      const Icon(Icons.attach_file, size: 13, color: kMuted),
                      const SizedBox(width: 3),
                      Text('${_files.length}', style: GoogleFonts.inter(color: kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                    ],
                    Icon(Icons.more_horiz, size: 16, color: _showActions ? kAccentMid : kMuted),
                  ]),
                ),
              ),
            ),

            // ── Bottom-right: send button (always visible) ─────────────────
            Positioned(
              bottom: 16, right: 16,
              child: GestureDetector(
                onTap: (hasContent && !_sending) ? _send : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: hasContent ? kAccent : Colors.white.withOpacity(0.07),
                    shape: BoxShape.circle,
                  ),
                  child: _sending
                      ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5)))
                      : Icon(Icons.arrow_upward_rounded, size: 22, color: hasContent ? Colors.white : kMuted2),
                ),
              ),
            ),

            // ── Bottom-left: char count (subtle) ──────────────────────────
            if (_ctrl.text.isNotEmpty)
              Positioned(
                bottom: 22, left: 22,
                child: Text(
                  '${_ctrl.text.length} car.',
                  style: GoogleFonts.inter(color: kMuted2.withOpacity(0.5), fontSize: 11),
                ),
              ),

            // ── Expandable action strip (appears on toggle) ───────────────
            if (_showActions)
              Positioned(
                top: 48, right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kBorder, width: 0.5),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _ActionBtn(icon: Icons.add_photo_alternate_outlined, label: 'Image', onTap: () { setState(() => _showActions = false); _pickFromGallery(); }),
                    _ActionBtn(icon: Icons.attach_file, label: 'Fichier', onTap: () { setState(() => _showActions = false); _pickFiles(); }),
                    if (_files.isNotEmpty) ...[
                      const Divider(color: kBorder, height: 8, thickness: 0.5),
                      ..._files.asMap().entries.map((e) => _ActionBtn(
                        icon: e.value.isImage ? Icons.image_outlined : Icons.description_outlined,
                        label: e.value.name.length > 16 ? '${e.value.name.substring(0, 14)}…' : e.value.name,
                        onTap: () => setState(() => _files.removeAt(e.key)),
                        trailing: const Icon(Icons.close, size: 12, color: kMuted2),
                      )),
                    ],
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  const _ActionBtn({required this.icon, required this.label, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: kMuted),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.inter(color: kMuted, fontSize: 12.5)),
        if (trailing != null) ...[const SizedBox(width: 6), trailing!],
      ]),
    ),
  );
}
