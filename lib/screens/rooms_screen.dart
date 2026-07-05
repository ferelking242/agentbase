import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/room.dart';
import '../services/github_service.dart';
import '../services/prefs_service.dart';
import '../theme.dart';
import '../widgets/app_components.dart';

class RoomsScreen extends StatefulWidget {
  final GitHubService? github;
  final void Function(Room)? onRoomSelected;

  const RoomsScreen({super.key, this.github, this.onRoomSelected});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  List<Room> _rooms = [];
  Set<String> _pinned = {};
  bool _loading = true;
  String? _error;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.github == null) { setState(() { _loading = false; _error = 'GitHub non configuré'; }); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        widget.github!.fetchRooms(),
        PrefsService.getPinnedRooms(),
      ]);
      if (mounted) setState(() {
        _rooms = results[0] as List<Room>;
        _pinned = results[1] as Set<String>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _togglePin(Room room) async {
    HapticFeedback.lightImpact();
    final nowPinned = await PrefsService.togglePinRoom(room.id);
    if (mounted) setState(() {
      if (nowPinned) _pinned.add(room.id); else _pinned.remove(room.id);
    });
    if (mounted) showAppSnack(context, nowPinned ? '"${room.name}" épinglée' : '"${room.name}" désépinglée');
  }

  Future<void> _showCreateRoom() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String selectedColor = '#6366f1';
    final colors = ['#6366f1', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#06b6d4', '#f97316'];

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          WidgetsBinding.instance.addPostFrameCallback((_) => nameCtrl.addListener(() { if (ctx.mounted) setDlgState(() {}); }));
          return AlertDialog(
          backgroundColor: kCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: kBorder, width: 0.5)),
          title: Text('Nouvelle Room', style: GoogleFonts.inter(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
          content: SizedBox(width: 340, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppInput(controller: nameCtrl, hint: 'Nom de la room', autofocus: true),
            const SizedBox(height: 10),
            AppInput(controller: descCtrl, hint: 'Description (optionnel)', maxLines: 2),
            const SizedBox(height: 12),
            Text('Couleur', style: GoogleFonts.inter(color: kMuted2, fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: colors.map((c) {
              final color = Color(int.parse(c.replaceFirst('#', '0xFF')));
              return GestureDetector(
                onTap: () => setDlgState(() => selectedColor = c),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle,
                    border: Border.all(color: selectedColor == c ? Colors.white : Colors.transparent, width: 2),
                  ),
                  child: selectedColor == c ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                ),
              );
            }).toList()),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Annuler', style: GoogleFonts.inter(color: kMuted))),
            AppButton(
              label: 'Créer',
              onTap: nameCtrl.text.trim().isEmpty ? null : () => Navigator.pop(ctx, true),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            ),
          ],
        );
        },
      ),
    );

    if (result != true || nameCtrl.text.trim().isEmpty) { nameCtrl.dispose(); descCtrl.dispose(); return; }
    final name = nameCtrl.text.trim();
    final desc = descCtrl.text.trim();
    nameCtrl.dispose(); descCtrl.dispose();

    setState(() => _creating = true);
    try {
      final room = await widget.github!.createRoom(name, description: desc, color: selectedColor);
      if (mounted) { setState(() { _rooms.insert(0, room); _creating = false; }); showAppSnack(context, 'Room "$name" créée !'); }
    } catch (e) {
      if (mounted) { setState(() => _creating = false); showAppSnack(context, e.toString().replaceAll('Exception: ', ''), isError: true); }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBg,
    body: SafeArea(bottom: false, child: Column(children: [
      // Header
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
          Text('Rooms', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
          if (!_loading && _rooms.isNotEmpty) ...[
            const SizedBox(width: 8),
            AppBadge('${_rooms.length}'),
          ],
          const Spacer(),
          GestureDetector(
            onTap: _load,
            child: Container(width: 34, height: 34, decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
              child: const Icon(Icons.sync_rounded, size: 17, color: kMuted)),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.github == null ? null : _showCreateRoom,
            child: AnimatedOpacity(
              opacity: widget.github == null ? 0.4 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(8)),
                child: _creating
                    ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.add, size: 18, color: Colors.white),
              ),
            ),
          ),
        ]),
      ),

      // Body
      Expanded(child: _loading
          ? _buildSkeleton()
          : _error != null
              ? _buildError()
              : _rooms.isEmpty
                  ? _buildEmpty()
                  : _buildList()),
    ])),
  );

  Widget _buildSkeleton() => ListView.separated(
    padding: const EdgeInsets.all(16),
    itemCount: 5,
    separatorBuilder: (_, __) => const SizedBox(height: 8),
    itemBuilder: (_, __) => const _SkeletonCard(),
  );

  Widget _buildError() => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 56, height: 56, decoration: BoxDecoration(color: kRedSub.withOpacity(0.4), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.cloud_off_outlined, size: 26, color: kRed)),
      const SizedBox(height: 16),
      Text('Erreur de chargement', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(_error!, style: GoogleFonts.inter(color: kMuted2, fontSize: 13, height: 1.4), textAlign: TextAlign.center),
      const SizedBox(height: 20),
      AppButton(label: 'Réessayer', icon: Icons.refresh, onTap: _load, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10)),
    ]),
  ));

  Widget _buildEmpty() => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 64, height: 64, decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kBorder)),
        child: const Icon(Icons.workspaces_outlined, size: 30, color: kMuted2)),
      const SizedBox(height: 16),
      Text('Aucune room', style: GoogleFonts.inter(color: kText, fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text('Crée ta première room pour organiser tes prompts par contexte ou projet.', style: GoogleFonts.inter(color: kMuted2, fontSize: 13, height: 1.5), textAlign: TextAlign.center),
      const SizedBox(height: 20),
      if (widget.github != null)
        AppButton(label: 'Créer une room', icon: Icons.add, onTap: _showCreateRoom, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11)),
    ]),
  ));

  Widget _buildList() {
    final pinned   = _rooms.where((r) => _pinned.contains(r.id)).toList();
    final unpinned = _rooms.where((r) => !_pinned.contains(r.id)).toList();
    final sorted   = [...pinned, ...unpinned];
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: sorted.length + (pinned.isNotEmpty && unpinned.isNotEmpty ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        if (pinned.isNotEmpty && unpinned.isNotEmpty && i == pinned.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Container(height: 0.5, color: kBorder)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('Autres', style: GoogleFonts.inter(color: kMuted2, fontSize: 11, letterSpacing: 0.5)),
              ),
              Expanded(child: Container(height: 0.5, color: kBorder)),
            ]),
          );
        }
        final idx = (pinned.isNotEmpty && unpinned.isNotEmpty && i > pinned.length) ? i - 1 : i;
        final room = sorted[idx];
        return _RoomCard(
          room: room,
          isPinned: _pinned.contains(room.id),
          onTap: () { Navigator.pop(context); widget.onRoomSelected?.call(room); },
          onPin: () => _togglePin(room),
        );
      },
    );
  }
}

// ── _RoomCard ─────────────────────────────────────────────────────────────────
class _RoomCard extends StatelessWidget {
  final Room room;
  final bool isPinned;
  final VoidCallback onTap;
  final VoidCallback onPin;
  const _RoomCard({required this.room, required this.onTap, required this.onPin, this.isPinned = false});

  @override
  Widget build(BuildContext context) {
    Color accent;
    try {
      accent = Color(int.parse(room.color.replaceFirst('#', '0xFF')));
    } catch (_) {
      accent = kAccentMid;
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder, width: 0.5)),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: accent.withOpacity(0.15), borderRadius: BorderRadius.circular(11)),
            child: Icon(Icons.workspaces_outlined, size: 20, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(room.name, style: GoogleFonts.inter(color: kText, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
            if (room.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(room.description, style: GoogleFonts.inter(color: kMuted2, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ])),
          const SizedBox(width: 8),
          Row(children: [
            if (room.promptCount > 0) ...[
              Text('${room.promptCount}', style: GoogleFonts.inter(color: kMuted2, fontSize: 12)),
              const SizedBox(width: 2),
              const Icon(Icons.article_outlined, size: 12, color: kMuted2),
              const SizedBox(width: 6),
            ],
            GestureDetector(
              onTap: onPin,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 15, color: isPinned ? kAccentMid : kMuted2),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, size: 18, color: kMuted2),
          ]),
        ]),
      ),
    );
  }
}

// ── _SkeletonCard — shimmer effect ────────────────────────────────────────────
class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard();
  @override State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _anim = Tween<double>(begin: -1.5, end: 2.5).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder, width: 0.5)),
      child: ShaderMask(
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [kCard2, kSubtle, kCard2],
          stops: [
            (_anim.value - 0.5).clamp(0.0, 1.0),
            _anim.value.clamp(0.0, 1.0),
            (_anim.value + 0.5).clamp(0.0, 1.0),
          ],
        ).createShader(rect),
        child: Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 13, width: 140, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 6),
            Container(height: 11, width: 90, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
          ])),
        ]),
      ),
    ),
  );
}
