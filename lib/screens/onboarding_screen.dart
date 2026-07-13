import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/prefs_service.dart';
import '../theme.dart';
import 'shell_screen.dart';
import '../services/github_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _page = 0;

  final _pages = const [_Page0(), _Page1(), _Page2()];

  void _next() {
    HapticFeedback.lightImpact();
    if (_page < _pages.length - 1) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await PrefsService.setOnboardingSeen(true);
    if (!mounted) return;
    final github = GitHubService();
    await github.init();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ShellScreen(github: github)),
    );
  }

  @override
  void dispose() { _pageCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(children: [
          // Skip
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 20, 0),
              child: GestureDetector(
                onTap: _finish,
                child: Text('Passer', style: GoogleFonts.inter(color: kMuted, fontSize: 14)),
              ),
            ),
          ),

          // Pages
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl,
              onPageChanged: (i) => setState(() => _page = i),
              itemCount: _pages.length,
              itemBuilder: (_, i) => _pages[i],
            ),
          ),

          // Dots + CTA
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
            child: Column(children: [
              // Dots
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (int i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _page == i ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _page == i ? kAccent : kSubtle,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ]),
              const SizedBox(height: 24),

              // Button
              GestureDetector(
                onTap: _next,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF4338CA)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _page == _pages.length - 1 ? 'Commencer →' : 'Suivant →',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Page0 extends StatelessWidget {
  const _Page0();
  @override
  Widget build(BuildContext context) => _OnboardingPage(
    icon: Icons.bolt,
    iconColor: kAccent,
    title: 'Bienvenue sur\nAgentBase',
    subtitle: 'Ton workspace IA.\nCrée, organise et pousse tes prompts vers GitHub en un tap.',
    highlight: 'Versionné. Portable. Toujours dispo.',
  );
}

class _Page1 extends StatelessWidget {
  const _Page1();
  @override
  Widget build(BuildContext context) => _OnboardingPage(
    icon: Icons.key,
    iconColor: kGreen,
    title: 'Configure\nton token GitHub',
    subtitle: 'Va dans Paramètres → colle ton Personal Access Token (PAT) GitHub.\nL\'app n\'envoie rien vers nos serveurs.',
    highlight: 'Settings → Token → Tester la connexion',
  );
}

class _Page2 extends StatelessWidget {
  const _Page2();
  @override
  Widget build(BuildContext context) => _OnboardingPage(
    icon: Icons.send_rounded,
    iconColor: Color(0xFF8B5CF6),
    title: 'Pousse ton\npremier prompt',
    subtitle: 'Écris ton prompt dans la zone de texte, ajoute des images si besoin, puis appuie sur Envoyer.\nIl atterrit direct sur GitHub.',
    highlight: 'Compatible Claude · ChatGPT · Gemini',
  );
}

class _OnboardingPage extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title, subtitle, highlight;
  const _OnboardingPage({required this.icon, required this.iconColor, required this.title, required this.subtitle, required this.highlight});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 20, 32, 20),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: iconColor.withOpacity(0.25), width: 1),
        ),
        child: Icon(icon, size: 36, color: iconColor),
      ),
      const SizedBox(height: 32),
      Text(title,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(color: kText, fontSize: 26, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.5),
      ),
      const SizedBox(height: 16),
      Text(subtitle,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(color: kMuted, fontSize: 14.5, height: 1.65),
      ),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: iconColor.withOpacity(0.2)),
        ),
        child: Text(highlight,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: iconColor, fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    ]),
  );
}
