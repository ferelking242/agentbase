import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/github_service.dart';
import '../services/prefs_service.dart';
import '../models/saved_prompt.dart';
import '../theme.dart';
import '../widgets/app_components.dart';
import 'dashboard_screen.dart';
import 'home_screen.dart';
import 'notifications_screen.dart';
import 'openspace_screen.dart';
import 'room_detail_screen.dart';
import 'rooms_screen.dart';
import 'prompts_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'templates_screen.dart';

class ShellScreen extends StatefulWidget {
  final GitHubService github;
  const ShellScreen({super.key, required this.github});
  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  List<SavedPrompt> _prompts = [];

  @override
  void initState() {
    super.initState();
    _loadPrompts();
  }

  Future<void> _loadPrompts() async {
    final list = await PrefsService.getPrompts();
    if (mounted) setState(() => _prompts = list);
  }

  void _onPromptSaved(SavedPrompt p) =>
      setState(() => _prompts.insert(0, p));

  Future<void> _syncPrompts() async {
    if (!widget.github.hasPat) {
      showAppSnack(context, 'Configure ton token dans Paramètres', isError: true);
      return;
    }
    showAppSnack(context, 'Synchronisation…', color: kBlue);
    try {
      final remote = await widget.github.fetchRemotePrompts();
      final local  = await PrefsService.getPrompts();
      final localIds = local.map((p) => p.id).toSet();
      final newOnes = remote.where((p) => !localIds.contains(p.id)).toList();
      for (final p in newOnes) await PrefsService.addPrompt(p);
      final merged = await PrefsService.getPrompts();
      if (!mounted) return;
      setState(() => _prompts = merged);
      showAppSnack(context, newOnes.isEmpty
        ? 'Déjà à jour (${merged.length} prompts)'
        : '+${newOnes.length} prompt${newOnes.length > 1 ? "s" : ""} ajouté${newOnes.length > 1 ? "s" : ""}');
    } catch (e) {
      if (mounted) showAppSnack(context, 'Erreur sync: $e', isError: true);
    }
  }

  Future<void> _deletePrompt(String id) async {
    await PrefsService.deletePrompt(id);
    if (mounted) setState(() => _prompts.removeWhere((p) => p.id == id));
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  void _navigateToRooms() {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => RoomsScreen(
        github: widget.github,
        onRoomSelected: (room) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => RoomDetailScreen(room: room, github: widget.github),
          ));
        },
      ),
    ));
  }

  void _navigateToPrompts() {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PromptsScreen(github: widget.github),
    )).then((_) => _loadPrompts());
  }

  void _navigateToOpenSpace() {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => OpenspaceScreen(github: widget.github),
    ));
  }

  void _navigateToNotifications() {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const NotificationsScreen(),
    ));
  }

  void _navigateToSettings() {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SettingsScreen(github: widget.github),
    ));
  }

  void _navigateToDashboard() {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => DashboardScreen(github: widget.github),
    ));
  }

  void _navigateToTemplates() {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const TemplatesScreen(),
    ));
  }

  void _navigateToSearch() {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SearchScreen(github: widget.github),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: _scaffoldKey,
    backgroundColor: kBg,
    drawer: _AppDrawer(
      github: widget.github,
      promptCount: _prompts.length,
      onRooms: _navigateToRooms,
      onPrompts: _navigateToPrompts,
      onOpenSpace: _navigateToOpenSpace,
      onNotifications: _navigateToNotifications,
      onSettings: _navigateToSettings,
      onDashboard: _navigateToDashboard,
      onTemplates: _navigateToTemplates,
      onSearch: _navigateToSearch,
    ),
    body: HomeScreen(
      github: widget.github,
      onOpenDrawer: _openDrawer,
      onPromptSaved: _onPromptSaved,
      prompts: _prompts,
      onSyncRequest: _syncPrompts,
      onDeletePrompt: _deletePrompt,
    ),
  );
}

// ── App Drawer ─────────────────────────────────────────────────────────────
class _AppDrawer extends StatelessWidget {
  final GitHubService github;
  final int promptCount;
  final VoidCallback onRooms;
  final VoidCallback onPrompts;
  final VoidCallback onOpenSpace;
  final VoidCallback onNotifications;
  final VoidCallback onSettings;
  final VoidCallback onDashboard;
  final VoidCallback onTemplates;
  final VoidCallback onSearch;

  const _AppDrawer({
    required this.github,
    required this.promptCount,
    required this.onRooms,
    required this.onPrompts,
    required this.onOpenSpace,
    required this.onNotifications,
    required this.onSettings,
    required this.onDashboard,
    required this.onTemplates,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: kCard,
      width: 260,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kAccent, Color(0xFF4F46E5)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bolt, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AgentBase', style: GoogleFonts.inter(color: kText, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
                Text('IA Workspace', style: GoogleFonts.inter(color: kMuted2, fontSize: 11.5)),
              ]),
            ]),
          ),

          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: AppDivider()),
          const SizedBox(height: 8),

          // Nav items
          _DrawerItem(icon: Icons.search, label: 'Rechercher', onTap: onSearch),
          _DrawerItem(icon: Icons.bar_chart_rounded, label: 'Dashboard', onTap: onDashboard),
          _DrawerItem(icon: Icons.workspaces_outlined, label: 'Rooms', onTap: onRooms),
          _DrawerItem(
            icon: Icons.article_outlined,
            label: 'Prompts',
            onTap: onPrompts,
            badge: promptCount > 0 ? '$promptCount' : null,
          ),
          _DrawerItem(icon: Icons.cloud_outlined, label: 'OpenSpace', onTap: onOpenSpace),
          _DrawerItem(icon: Icons.auto_awesome_outlined, label: 'Templates', onTap: onTemplates),
          _DrawerItem(icon: Icons.notifications_outlined, label: 'Notifications', onTap: onNotifications),

          const Spacer(),

          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: AppDivider()),
          const SizedBox(height: 4),

          _DrawerItem(icon: Icons.settings_outlined, label: 'Paramètres', onTap: onSettings),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;

  const _DrawerItem({required this.icon, required this.label, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(icon, size: 20, color: kMuted),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: GoogleFonts.inter(color: kText2, fontSize: 14, fontWeight: FontWeight.w500))),
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(99)),
            child: Text(badge!, style: GoogleFonts.inter(color: kAccentMid, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right_rounded, size: 16, color: kMuted2),
      ]),
    ),
  );
}
