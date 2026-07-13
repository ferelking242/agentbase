import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/github_service.dart';
import '../services/prefs_service.dart';
import '../models/saved_prompt.dart';
import '../models/room.dart';
import '../theme.dart';
import '../widgets/app_components.dart';
import '../widgets/send_sheet.dart';

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

  /// Ferme le full screen et renvoie le texte+fichiers courants au parent
  /// pour qu'il les restaure dans le composer principal.
  void _close() {
    Navigator.pop(context, {'text': _ctrl.text, 'files': List<AttachedFile>.from(_files)});
  }

  @override
  Widget build(BuildContext context) {
    final hasContent = _ctrl.text.trim().isNotEmpty || _files.isNotEmpty;
    return Scaffold(
      backgroundColor: kBg,
      resizeToAvoidBottomInset: true,
      // Intercepte le swipe-back (iOS) pour aussi restaurer le texte
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) { if (!didPop) _close(); },
        child: SafeArea(
          child: Stack(
            children: [
              // ── Zone de texte plein écran ──────────────────────────────
              Positioned.fill(
                child: GestureDetector(
                  onTap: _focus.requestFocus,
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
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      // padding : 52px haut (sous le X), 100px bas (au-dessus du send)
                      contentPadding: const EdgeInsets.fromLTRB(22, 52, 22, 100),
                    ),
                  ),
                ),
              ),

              // ── X — fermer, haut droite ────────────────────────────────
              Positioned(
                top: 8, right: 12,
                child: GestureDetector(
                  onTap: _close,
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 17, color: kMuted),
                  ),
                ),
              ),

              // ── Envoyer — bas droite ───────────────────────────────────
              Positioned(
                bottom: 20, right: 16,
                child: GestureDetector(
                  onTap: (hasContent && !_sending) ? _send : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      color: hasContent ? kAccent : Colors.white.withOpacity(0.07),
                      shape: BoxShape.circle,
                    ),
                    child: _sending
                        ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5)))
                        : Icon(Icons.arrow_upward_rounded, size: 24, color: hasContent ? Colors.white : kMuted2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

