import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/github_service.dart';
import 'screens/shell_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: kBg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final github = GitHubService();
  try { await github.init(); } catch (_) {}
  runApp(AgentBaseApp(github: github));
}

class AgentBaseApp extends StatelessWidget {
  final GitHubService github;
  const AgentBaseApp({super.key, required this.github});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AgentBase',
    theme: buildTheme(),
    debugShowCheckedModeBanner: false,
    home: ShellScreen(github: github),
  );
}
