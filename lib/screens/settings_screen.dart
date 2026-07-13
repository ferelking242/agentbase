import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/github_service.dart';
import '../services/prefs_service.dart';
import '../theme.dart';
import '../widgets/app_components.dart';

class SettingsScreen extends StatefulWidget {
  final GitHubService github;
  const SettingsScreen({super.key, required this.github});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _tokenCtrl    = TextEditingController();
  final _ownerCtrl    = TextEditingController();
  final _repoCtrl     = TextEditingController();
  final _dataRepoCtrl = TextEditingController();
  bool _showToken = false;
  bool _saving = false;
  bool _testing = false;
  bool _testPassed = false;
  String? _testError;
  String _themeMode = 'dark';
  bool _autoSync = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final pat      = await PrefsService.getPat();
    final owner    = await PrefsService.getOwner();
    final repo     = await PrefsService.getRepo();
    final dataRepo = await PrefsService.getDataRepo();
    final theme    = await PrefsService.getThemeMode();
    final auto     = await PrefsService.getAutoSync();
    if (!mounted) return;
    setState(() {
      if (pat != null) _tokenCtrl.text = pat;
      _ownerCtrl.text    = owner;
      _repoCtrl.text     = repo;
      _dataRepoCtrl.text = dataRepo;
      _themeMode = theme;
      _autoSync  = auto;
    });
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _ownerCtrl.dispose();
    _repoCtrl.dispose();
    _dataRepoCtrl.dispose();
    super.dispose();
  }

  bool get _isConfigured => _tokenCtrl.text.trim().isNotEmpty;

  Future<void> _testConnection() async {
    if (!_isConfigured) { showAppSnack(context, 'Entre ton token d\'abord', isError: true); return; }
    setState(() { _testing = true; _testPassed = false; _testError = null; });
    try {
      final tmp = GitHubService(owner: _ownerCtrl.text.trim(), repo: _repoCtrl.text.trim());
      tmp.setPat(_tokenCtrl.text.trim());
      final ok = await tmp.validatePat();
      if (!mounted) return;
      if (ok) {
        setState(() { _testing = false; _testPassed = true; });
        showAppSnack(context, 'Connexion réussie !');
      } else {
        setState(() { _testing = false; _testError = 'Token invalide ou dépôt inaccessible'; });
        showAppSnack(context, _testError!, isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _testing = false; _testError = e.toString().replaceAll('Exception: ', ''); });
      showAppSnack(context, _testError!, isError: true);
    }
  }

  Future<void> _save() async {
    if (!_isConfigured) { showAppSnack(context, 'Token requis', isError: true); return; }
    setState(() => _saving = true);
    final pat      = _tokenCtrl.text.trim();
    final owner    = _ownerCtrl.text.trim();
    final repo     = _repoCtrl.text.trim();
    final dataRepo = _dataRepoCtrl.text.trim();
    await PrefsService.savePat(pat);
    if (owner.isNotEmpty) await PrefsService.setOwner(owner);
    if (repo.isNotEmpty)  await PrefsService.setRepo(repo);
    await PrefsService.setDataRepo(dataRepo);
    await PrefsService.setThemeMode(_themeMode);
    await PrefsService.setAutoSync(_autoSync);
    widget.github.setPat(pat);
    widget.github.setDataRepo(dataRepo);
    setState(() => _saving = false);
    if (mounted) showAppSnack(context, 'Paramètres sauvegardés ✓');
  }

  Future<void> _clearCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: kBorder)),
        title: Text('Vider le cache ?', style: GoogleFonts.inter(color: kText, fontSize: 15)),
        content: Text('Le contenu des prompts sera re-téléchargé au prochain accès.', style: GoogleFonts.inter(color: kMuted2, fontSize: 13, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: Text('Annuler', style: GoogleFonts.inter(color: kMuted))),
          AppButton(label: 'Vider', variant: AppButtonVariant.destructive, onTap: () => Navigator.pop(_, true), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
        ],
      ),
    );
    if (ok == true) {
      await PrefsService.clearContentCache();
      if (mounted) showAppSnack(context, 'Cache vidé');
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.github.hasPat;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // ── Header ───────────────────────────────────────────────────────
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
              Text('Paramètres', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
              const Spacer(),
              AppButton(
                label: 'Sauvegarder',
                loading: _saving,
                onTap: _saving ? null : _save,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ]),
          ),

          Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [

            // ── Connection status ─────────────────────────────────────────
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: connected ? kGreenSub : kRedSub.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(connected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                    size: 18, color: connected ? kGreen : kRed),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(connected ? 'GitHub connecté' : 'Non configuré',
                    style: GoogleFonts.inter(color: kText, fontSize: 13.5, fontWeight: FontWeight.w600)),
                  Text(connected ? '${widget.github.owner}/${widget.github.repo}' : 'Entre ton token PAT ci-dessous',
                    style: GoogleFonts.inter(color: kMuted2, fontSize: 12)),
                ])),
                if (_testPassed) const Icon(Icons.check_circle, size: 18, color: kGreen),
                if (_testError != null) const Icon(Icons.error_outline, size: 18, color: kRed),
              ]),
            ),
            const SizedBox(height: 20),

            // ── GitHub Token ──────────────────────────────────────────────
            const AppSectionHeader('Token GitHub (PAT)'),
            AppCard(padding: const EdgeInsets.all(14), child: Column(children: [
              Row(children: [
                Expanded(child: AppInput(
                  controller: _tokenCtrl,
                  hint: 'ghp_xxxxxxxxxxxxxxxxxxxx',
                  obscure: !_showToken,
                  suffix: GestureDetector(
                    onTap: () => setState(() => _showToken = !_showToken),
                    child: Icon(_showToken ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 16, color: kMuted2),
                  ),
                )),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: _testing ? null : _testConnection,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (_testing)
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: kAccent))
                      else ...[
                        const Icon(Icons.wifi_tethering_rounded, size: 15, color: kMuted),
                        const SizedBox(width: 6),
                        Text('Tester la connexion', style: GoogleFonts.inter(color: kMuted, fontSize: 13)),
                      ],
                    ]),
                  ),
                )),
              ]),
              if (_testError != null) ...[
                const SizedBox(height: 8),
                Text(_testError!, style: GoogleFonts.inter(color: kRed, fontSize: 12)),
              ],
            ])),
            const SizedBox(height: 8),
            AppCard(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Permissions requises', style: GoogleFonts.inter(color: kMuted2, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Ton PAT doit avoir la permission : repo (lecture + écriture) ou contents:write.', style: GoogleFonts.inter(color: kMuted2, fontSize: 12, height: 1.4)),
            ])),
            const SizedBox(height: 20),

            // ── Repository config ─────────────────────────────────────────
            const AppSectionHeader('Dépôt GitHub'),
            AppCard(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const AppLabel('Propriétaire (owner)'),
              const SizedBox(height: 6),
              AppInput(controller: _ownerCtrl, hint: 'ferelking242'),
              const SizedBox(height: 12),
              const AppLabel('Dépôt de code (repo)'),
              const SizedBox(height: 6),
              AppInput(controller: _repoCtrl, hint: 'agentbase'),
              const SizedBox(height: 12),
              Row(children: [
                const AppLabel('Dépôt de données'),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: kGreenSub, borderRadius: BorderRadius.circular(4)),
                  child: Text('recommandé', style: GoogleFonts.inter(color: kGreen, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 6),
              AppInput(controller: _dataRepoCtrl, hint: 'agentbase-data  (laisser vide = même repo)'),
              const SizedBox(height: 8),
              Text(
                'Si renseigné, tous les commits de données (prompts, rooms, images…) vont dans ce dépôt. '
                'Le dépôt de code reste propre et le CI ne se déclenche plus à chaque sauvegarde.',
                style: GoogleFonts.inter(color: kMuted2, fontSize: 11.5, height: 1.4),
              ),
            ])),
            const SizedBox(height: 20),

            // ── Appearance ────────────────────────────────────────────────
            const AppSectionHeader('Apparence'),
            AppCard(padding: const EdgeInsets.all(14), child: Column(children: [
              Row(children: [
                Container(width: 30, height: 30,
                  decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.palette_outlined, size: 15, color: kAccentMid)),
                const SizedBox(width: 12),
                Text('Thème', style: GoogleFonts.inter(color: kText, fontSize: 13.5, fontWeight: FontWeight.w500)),
                const Spacer(),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _ThemeBtn(label: '🌙 Sombre', value: 'dark', selected: _themeMode == 'dark', onTap: () => setState(() => _themeMode = 'dark')),
                const SizedBox(width: 8),
                _ThemeBtn(label: '☀️ Clair', value: 'light', selected: _themeMode == 'light', onTap: () => setState(() => _themeMode = 'light')),
                const SizedBox(width: 8),
                _ThemeBtn(label: '🔁 Système', value: 'system', selected: _themeMode == 'system', onTap: () => setState(() => _themeMode = 'system')),
              ]),
              const SizedBox(height: 6),
              Text('Rechargez l\'app après sauvegarde pour appliquer le thème.', style: GoogleFonts.inter(color: kMuted2, fontSize: 11)),
            ])),
            const SizedBox(height: 20),

            // ── Data & Sync ───────────────────────────────────────────────
            const AppSectionHeader('Données & Synchronisation'),
            AppCard(padding: EdgeInsets.zero, child: Column(children: [
              // Auto-sync toggle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Container(width: 30, height: 30,
                    decoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.sync_rounded, size: 15, color: kMuted)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Sync automatique', style: GoogleFonts.inter(color: kText, fontSize: 13.5, fontWeight: FontWeight.w500)),
                    Text('Syncsronise à chaque ouverture de l\'écran Prompts', style: GoogleFonts.inter(color: kMuted2, fontSize: 11.5)),
                  ])),
                  Switch(value: _autoSync, onChanged: (v) => setState(() => _autoSync = v), activeColor: kAccent),
                ]),
              ),
              const AppDivider(),
              // Clear cache
              GestureDetector(
                onTap: _clearCache,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    Container(width: 30, height: 30,
                      decoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.cleaning_services_outlined, size: 15, color: kMuted)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Vider le cache', style: GoogleFonts.inter(color: kText, fontSize: 13.5, fontWeight: FontWeight.w500)),
                      Text('Supprime le contenu des prompts mis en cache', style: GoogleFonts.inter(color: kMuted2, fontSize: 11.5)),
                    ])),
                    const Icon(Icons.chevron_right_rounded, size: 16, color: kMuted2),
                  ]),
                ),
              ),
            ])),
            const SizedBox(height: 20),

            // ── Notifications ─────────────────────────────────────────────
            const AppSectionHeader('Notifications'),
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 30, height: 30,
                  decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.notifications_outlined, size: 15, color: kAccentMid)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Notifications in-app', style: GoogleFonts.inter(color: kText, fontSize: 13.5, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text('Stockées localement (max 80). Accède-y via la cloche 🔔 en haut.',
                    style: GoogleFonts.inter(color: kMuted2, fontSize: 12, height: 1.45)),
                ])),
              ]),
            ),
            const SizedBox(height: 20),

            // ── About ─────────────────────────────────────────────────────
            const AppSectionHeader('Application'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _InfoRow(icon: Icons.info_outline, label: 'Version', value: '3.1.0'),
                const AppDivider(),
                _InfoRow(icon: Icons.bolt, label: 'AgentBase', value: 'Interface prompts IA'),
                const AppDivider(),
                GestureDetector(
                  onTap: () => Clipboard.setData(const ClipboardData(text: 'https://github.com/ferelking242/agentbase')).then((_) {
                    if (context.mounted) showAppSnack(context, 'URL copiée');
                  }),
                  child: _InfoRow(icon: Icons.code, label: 'GitHub', value: 'ferelking242/agentbase'),
                ),
              ]),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
          ])),
        ]),
      ),
    );
  }
}

// ── _ThemeBtn ─────────────────────────────────────────────────────────────────
class _ThemeBtn extends StatelessWidget {
  final String label, value;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeBtn({required this.label, required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(child: GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: selected ? kAccentSub : kBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? kAccent.withOpacity(0.5) : kBorder, width: selected ? 1 : 0.5),
      ),
      child: Text(label, textAlign: TextAlign.center,
        style: GoogleFonts.inter(color: selected ? kAccentMid : kMuted, fontSize: 11.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
    ),
  ));
}

// ── _InfoRow ──────────────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon; final String label, value;
  const _InfoRow({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(children: [
      Container(width: 30, height: 30,
        decoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 14, color: kMuted)),
      const SizedBox(width: 10),
      Text(label, style: GoogleFonts.inter(color: kMuted, fontSize: 13)),
      const Spacer(),
      Text(value, style: GoogleFonts.inter(color: kText2, fontSize: 13, fontWeight: FontWeight.w500)),
    ]),
  );
}
