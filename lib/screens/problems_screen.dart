import 'package:flutter/material.dart';
  import '../services/github_service.dart';
  import '../theme.dart';

  class ProblemsScreen extends StatelessWidget {
    final GitHubService github;
    const ProblemsScreen({super.key, required this.github});
    @override
    Widget build(BuildContext context) => Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 52, height: 52, decoration: BoxDecoration(color: kYellow.withOpacity(0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: kYellow.withOpacity(0.2))),
          child: const Icon(Icons.lightbulb_outlined, color: kYellow, size: 24)),
        const SizedBox(height: 14),
        const Text("Problemes & Solutions", style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text("Bientot disponible", style: TextStyle(color: kMuted, fontSize: 13)),
      ]),
    );
  }