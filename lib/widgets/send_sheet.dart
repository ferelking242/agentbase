import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/room.dart';
import '../services/github_service.dart';
import '../theme.dart';
import 'app_components.dart';

typedef SendResult = ({String name, Room? room});

// ── Smart title from prompt text ──────────────────────────────────────────────
String _smartTitle(String raw) {
  if (raw.isEmpty) return '';
  var s = raw
      .replaceAll(RegExp(r'#{1,6}\s*'), '')
      .replaceAll(RegExp(r'[*_`~>]'), '')
      .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)', dotAll: true), r'$1')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final sentMatch = RegExp(r'^(.+?[.?!])(\s|$)').firstMatch(s);
  if (sentMatch != null && sentMatch.group(1)!.length >= 8) {
    s = sentMatch.group(1)!.trim();
  } else {
    final firstLine = s.split('\n').first.trim();
    if (firstLine.isNotEmpty) s = firstLine;
  }
  if (s.length > 60) {
    s = s.substring(0, 57);
    final last = s.lastIndexOf(' ');
    if (last > 15) s = s.substring(0, last);
    s = '$s…';
  }
  return s.isNotEmpty ? s : raw.split(' ').take(6).join(' ');
}

class SendSheet extends StatefulWidget {
  final String promptText;
  final List<Room> preloadedRooms;
  final GitHubService github;

  const SendSheet({
    super.key,
    required this.promptText,
    required this.preloadedRooms,
    required this.github,
  });

  @override
  State<SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<SendSheet> {
  late final TextEditingController _ctrl;
  Room? _room;
  List<Room> _rooms = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _smartTitle(widget.promptText));
    _rooms = List.from(widget.preloadedRooms);
    if (_rooms.isEmpty) _fetchRooms();
  }

  Future<void> _fetchRooms() async {
    setState(() => _loading = true);
    try {
      final r = await widget.github.fetchRooms();
      if (mounted) setState(() { _rooms = r; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _submit() => Navigator.pop(context, (name: _ctrl.text.trim(), room: _room));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          border: Border(top: BorderSide(color: kBorder, width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppDragHandle(),

              // Nom du prompt
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const AppLabel('Nom du prompt'),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _ctrl.text = _smartTitle(widget.promptText)),
                      child: Text('Regénérer', style: GoogleFonts.inter(color: kAccentMid, fontSize: 11.5)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  AppInput(
                    controller: _ctrl,
                    autofocus: true,
                    hint: 'Ex: Analyse de performance UI',
                    onSubmitted: (_) => _submit(),
                    suffix: GestureDetector(
                      onTap: () => _ctrl.clear(),
                      child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.close, size: 16, color: kMuted2)),
                    ),
                  ),
                ]),
              ),

              // Room
              Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: const AppLabel('Assigner à une room')),
              SizedBox(
                height: 44,
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Row(children: [
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)),
                          SizedBox(width: 10),
                          Text('Chargement…', style: TextStyle(color: kMuted2, fontSize: 13)),
                        ]),
                      )
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          RoomChip(label: 'Aucune', selected: _room == null, onTap: () => setState(() => _room = null)),
                          ..._rooms.map((r) => RoomChip(
                            label: r.name,
                            icon: r.iconData,
                            color: r.accentColor,
                            selected: _room?.id == r.id,
                            onTap: () => setState(() => _room = r),
                          )),
                        ],
                      ),
              ),

              // Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Row(children: [
                  Expanded(child: AppButton(
                    label: 'Annuler', variant: AppButtonVariant.outline, fullWidth: true,
                    onTap: () => Navigator.pop(context),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  )),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: AppButton(
                    label: _room != null ? 'Envoyer → ${_room!.name}' : 'Envoyer',
                    fullWidth: true, onTap: _submit,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  )),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── RoomChip ──────────────────────────────────────────────────────────────────
class RoomChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  const RoomChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? kAccent;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.withOpacity(0.12) : kBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? c.withOpacity(0.6) : kBorder, width: selected ? 1 : 0.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: selected ? c : kMuted2),
            const SizedBox(width: 5),
          ],
          Text(label, style: GoogleFonts.inter(
            color: selected ? c : kMuted,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          )),
        ]),
      ),
    );
  }
}
