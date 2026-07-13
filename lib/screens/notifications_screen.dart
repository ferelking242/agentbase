import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import '../widgets/app_components.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await NotificationService.getAll();
    if (mounted) setState(() { _notifications = list; _loading = false; });
  }

  Future<void> _markAllRead() async {
    await NotificationService.markAllRead();
    _load();
  }

  Future<void> _delete(String id) async {
    await NotificationService.delete(id);
    setState(() => _notifications.removeWhere((n) => n.id == id));
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: kBorder, width: 0.5)),
        title: Text('Tout effacer ?', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600)),
        content: Text('Toutes les notifications seront supprimées.', style: GoogleFonts.inter(color: kMuted2, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: Text('Annuler', style: GoogleFonts.inter(color: kMuted))),
          AppButton(label: 'Effacer', onTap: () => Navigator.pop(_, true), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
        ],
      ),
    );
    if (confirm != true) return;
    await NotificationService.clearAll();
    if (mounted) setState(() => _notifications = []);
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifications.where((n) => !n.read).length;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Container(
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
              Text('Notifications', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
              if (unread > 0) ...[
                const SizedBox(width: 8),
                AppBadge('$unread', bg: kAccent, fg: Colors.white),
              ],
              const Spacer(),
              if (_notifications.isNotEmpty) ...[
                if (unread > 0) GestureDetector(
                  onTap: _markAllRead,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
                    child: Text('Tout lire', style: GoogleFonts.inter(color: kMuted, fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _clearAll,
                  child: Container(width: 34, height: 34,
                    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
                    child: const Icon(Icons.delete_sweep_outlined, size: 17, color: kMuted)),
                ),
              ],
            ]),
          ),
          Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: kAccent, strokeWidth: 2))
            : _notifications.isEmpty
              ? _buildEmpty()
              : _buildList()),
        ]),
      ),
    );
  }

  Widget _buildEmpty() => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 64, height: 64,
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kBorder)),
        child: const Icon(Icons.notifications_none_outlined, size: 30, color: kMuted2)),
      const SizedBox(height: 16),
      Text('Aucune notification', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text('Les notifications apparaîtront ici quand l\'agent termine.', style: GoogleFonts.inter(color: kMuted2, fontSize: 13, height: 1.5), textAlign: TextAlign.center),
    ]),
  ));

  Widget _buildList() => ListView.separated(
    padding: const EdgeInsets.all(16),
    itemCount: _notifications.length,
    separatorBuilder: (_, __) => const SizedBox(height: 6),
    itemBuilder: (_, i) => _NotifCard(
      notification: _notifications[i],
      onRead: () async {
        await NotificationService.markRead(_notifications[i].id);
        setState(() => _notifications[i] = _notifications[i].copyWith(read: true));
      },
      onDelete: () => _delete(_notifications[i].id),
    ),
  );
}

class _NotifCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onRead;
  final VoidCallback onDelete;

  const _NotifCard({required this.notification, required this.onRead, required this.onDelete});

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    return 'Il y a ${diff.inDays}j';
  }

  @override
  Widget build(BuildContext context) {
    final isRead = notification.read;
    return GestureDetector(
      onTap: isRead ? null : onRead,
      child: Dismissible(
        key: Key(notification.id),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onDelete(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(color: kRedSub.withOpacity(0.6), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.delete_outline, color: kRed, size: 22),
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isRead ? kCard : kAccentSub.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isRead ? kBorder : kAccentMid.withOpacity(0.3), width: 0.5),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: isRead ? kCard2 : kAccentSub,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                notification.title.contains('Prompt') ? Icons.check_circle_outline : Icons.smart_toy_outlined,
                size: 18,
                color: isRead ? kMuted2 : kAccentMid,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(notification.title,
                  style: GoogleFonts.inter(color: kText, fontSize: 13, fontWeight: isRead ? FontWeight.w500 : FontWeight.w700))),
                if (!isRead) Container(width: 7, height: 7, decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle)),
              ]),
              const SizedBox(height: 2),
              Text(notification.body,
                style: GoogleFonts.inter(color: kMuted2, fontSize: 12.5, height: 1.4),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(_timeAgo(notification.createdAt),
                style: GoogleFonts.inter(color: kMuted2, fontSize: 11)),
            ])),
          ]),
        ),
      ),
    );
  }
}

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final c = await NotificationService.unreadCount();
    if (mounted) setState(() => _unread = c);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () async {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
      _refresh();
    },
    child: Stack(clipBehavior: Clip.none, children: [
      Container(width: 36, height: 36,
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
        child: const Icon(Icons.notifications_outlined, size: 17, color: kMuted)),
      if (_unread > 0) Positioned(
        top: -4, right: -4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(99)),
          child: Text('$_unread', style: GoogleFonts.inter(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );
}
