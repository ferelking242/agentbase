import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/saved_prompt.dart';
import '../services/github_service.dart';
import '../theme.dart';
import 'app_components.dart';

class PromptsSheet extends StatelessWidget {
  final List<SavedPrompt> prompts;
  final GitHubService github;
  final VoidCallback onSync;
  final void Function(String id) onDelete;

  const PromptsSheet({
    super.key,
    required this.prompts,
    required this.github,
    required this.onSync,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72, maxChildSize: 0.95, minChildSize: 0.4,
      expand: false,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          border: Border(top: BorderSide(color: kBorder, width: 0.5)),
        ),
        child: Column(children: [
          const AppDragHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
            child: Row(children: [
              Text('Prompts',
                style: GoogleFonts.inter(color: kText, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              if (prompts.isNotEmpty) AppBadge('${prompts.length}'),
              const Spacer(),
              AppButton(
                label: 'Sync',
                variant: AppButtonVariant.secondary,
                icon: Icons.sync_rounded,
                onTap: onSync,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              ),
            ]),
          ),
          const AppDivider(),
          Expanded(
            child: prompts.isEmpty
              ? const AppEmptyState(
                  icon: Icons.article_outlined,
                  title: 'Aucun prompt',
                  subtitle: 'Appuie sur Sync pour récupérer depuis GitHub',
                )
              : ListView.builder(
                  controller: ctrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: prompts.length,
                  itemBuilder: (_, i) => _PromptCard(
                    prompt: prompts[i],
                    github: github,
                    onDelete: () => onDelete(prompts[i].id),
                  ),
                ),
          ),
        ]),
      ),
    );
  }
}

class _PromptCard extends StatefulWidget {
  final SavedPrompt prompt;
  final GitHubService github;
  final VoidCallback onDelete;
  const _PromptCard({required this.prompt, required this.github, required this.onDelete});
  @override State<_PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends State<_PromptCard> {
  bool _copiedLink = false;
  bool _copiedContent = false;
  bool _loadingContent = false;

  Future<void> _copyContent() async {
    if (_loadingContent) return;
    setState(() => _loadingContent = true);
    try {
      final raw = await widget.github.fetchPromptContent(widget.prompt.id);
      if (!mounted) return;
      if (raw == null) {
        showAppSnack(context, 'Contenu introuvable', isError: true);
        setState(() => _loadingContent = false);
        return;
      }
      // Strip legacy metadata to get the clean prompt text
      final content = GitHubService.stripPromptMeta(raw);
      await Clipboard.setData(ClipboardData(text: content.isNotEmpty ? content : raw));
      setState(() { _loadingContent = false; _copiedContent = true; });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copiedContent = false);
      });
    } catch (_) {
      if (mounted) setState(() => _loadingContent = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.article_outlined, size: 15, color: kAccentMid),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.prompt.name,
            style: GoogleFonts.inter(color: kText, fontSize: 13.5, fontWeight: FontWeight.w600),
            maxLines: 2, overflow: TextOverflow.ellipsis)),
          GestureDetector(
            onTap: widget.onDelete,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 14, color: kMuted2),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(_fmtDate(widget.prompt.created),
          style: GoogleFonts.inter(color: kMuted2, fontSize: 11)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: kBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: kBorder, width: 0.5),
          ),
          child: Text(widget.prompt.link,
            style: GoogleFonts.robotoMono(color: kBlue, fontSize: 11),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: AppButton(
            label: _copiedLink ? 'Copié !' : 'Copier le lien',
            icon: _copiedLink ? Icons.check : Icons.link,
            variant: _copiedLink ? AppButtonVariant.secondary : AppButtonVariant.outline,
            fullWidth: true,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: widget.prompt.link));
              setState(() => _copiedLink = true);
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _copiedLink = false);
              });
            },
            padding: const EdgeInsets.symmetric(vertical: 9),
          )),
          const SizedBox(width: 8),
          Expanded(child: AppButton(
            label: _copiedContent ? 'Copié !' : 'Copier MD',
            icon: _copiedContent ? Icons.check : Icons.content_copy,
            variant: _copiedContent ? AppButtonVariant.secondary : AppButtonVariant.ghost,
            loading: _loadingContent,
            fullWidth: true,
            onTap: _loadingContent ? null : _copyContent,
            padding: const EdgeInsets.symmetric(vertical: 9),
          )),
        ]),
      ]),
    ),
  );

  String _fmtDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inHours < 1) return 'Il y a ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'Il y a ${diff.inHours}h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays}j';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}
