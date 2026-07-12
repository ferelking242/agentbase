import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SHADCN-INSPIRED FLUTTER COMPONENT LIBRARY
// ═══════════════════════════════════════════════════════════════════════════════

// ── AppCard ──────────────────────────────────────────────────────────────────
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final VoidCallback? onTap;
  final double radius;
  final bool hasBorder;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.onTap,
    this.radius = 10,
    this.hasBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? kCard,
        borderRadius: BorderRadius.circular(radius),
        border: hasBorder ? Border.all(color: kBorder, width: 0.5) : null,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(
      onTap: onTap,
      child: card,
    );
  }
}

// ── AppButton ─────────────────────────────────────────────────────────────────
enum AppButtonVariant { primary, secondary, ghost, destructive, outline }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;
  final EdgeInsetsGeometry? padding;

  const AppButton({
    super.key,
    required this.label,
    this.onTap,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.fullWidth = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    Color bg, fg, border;
    switch (variant) {
      case AppButtonVariant.primary:
        bg = kAccent; fg = Colors.white; border = Colors.transparent;
      case AppButtonVariant.secondary:
        bg = kCard2; fg = kText2; border = kBorder;
      case AppButtonVariant.ghost:
        bg = Colors.transparent; fg = kMuted; border = Colors.transparent;
      case AppButtonVariant.destructive:
        bg = kRedSub; fg = kRed; border = kRed.withOpacity(0.3);
      case AppButtonVariant.outline:
        bg = Colors.transparent; fg = kText; border = kBorder;
    }

    final content = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading) ...[
          SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation(fg),
            ),
          ),
          const SizedBox(width: 8),
        ] else if (icon != null) ...[
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 6),
        ],
        Text(label, style: GoogleFonts.inter(color: fg, fontSize: 13.5, fontWeight: FontWeight.w500)),
      ],
    );

    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedOpacity(
        opacity: onTap == null && !loading ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border, width: 0.5),
          ),
          child: content,
        ),
      ),
    );
  }
}

// ── AppInput ──────────────────────────────────────────────────────────────────
class AppInput extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final Widget? suffix;
  final Widget? prefix;
  final String? suffixText;
  final bool autofocus;
  final int? maxLines;
  final TextStyle? style;
  final void Function(String)? onSubmitted;
  final void Function(String)? onChanged;
  final bool isDense;
  final Color? fillColor;
  final Color? borderColor;
  final FocusNode? focusNode;

  const AppInput({
    super.key,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.suffix,
    this.prefix,
    this.suffixText,
    this.autofocus = false,
    this.maxLines = 1,
    this.style,
    this.onSubmitted,
    this.onChanged,
    this.isDense = false,
    this.fillColor,
    this.borderColor,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autofocus: autofocus,
      maxLines: maxLines,
      focusNode: focusNode,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      style: style ?? GoogleFonts.inter(color: kText, fontSize: 14),
      cursorColor: kAccent,
      cursorWidth: 1.5,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: kMuted2, fontSize: 14),
        suffixIcon: suffix,
        prefixIcon: prefix,
        suffixText: suffixText,
        suffixStyle: GoogleFonts.inter(color: kMuted2, fontSize: 14),
        filled: true,
        fillColor: fillColor ?? kInput,
        isDense: isDense,
        contentPadding: isDense
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor ?? kBorder, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor ?? kBorder, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kAccent, width: 1.5),
        ),
      ),
    );
  }
}

// ── AppBadge ──────────────────────────────────────────────────────────────────
class AppBadge extends StatelessWidget {
  final String label;
  final Color? bg;
  final Color? fg;

  const AppBadge(this.label, {super.key, this.bg, this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg ?? kAccentSub,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: (fg ?? kAccentMid).withOpacity(0.2)),
      ),
      child: Text(label,
        style: GoogleFonts.inter(
          color: fg ?? kAccentMid,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        )),
    );
  }
}

// ── AppLabel ──────────────────────────────────────────────────────────────────
class AppLabel extends StatelessWidget {
  final String text;
  const AppLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: GoogleFonts.inter(
      color: kMuted2,
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    ),
  );
}

// ── AppDivider ────────────────────────────────────────────────────────────────
class AppDivider extends StatelessWidget {
  final double? height;
  const AppDivider({super.key, this.height});

  @override
  Widget build(BuildContext context) =>
      Divider(height: height ?? 1, thickness: 0.5, color: kBorder);
}

// ── AppDragHandle ─────────────────────────────────────────────────────────────
class AppDragHandle extends StatelessWidget {
  const AppDragHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      width: 36, height: 4,
      decoration: BoxDecoration(
        color: kSubtle,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

// ── AppLoadingIndicator ───────────────────────────────────────────────────────
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: CircularProgressIndicator(
      color: kAccent,
      strokeWidth: 2,
    ),
  );
}

// ── AppEmptyState ─────────────────────────────────────────────────────────────
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBorder),
          ),
          child: Icon(icon, size: 24, color: kSubtle),
        ),
        const SizedBox(height: 14),
        Text(title, style: GoogleFonts.inter(color: kMuted, fontSize: 14, fontWeight: FontWeight.w500)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!,
            style: GoogleFonts.inter(color: kMuted2, fontSize: 12.5),
            textAlign: TextAlign.center),
        ],
        if (action != null) ...[
          const SizedBox(height: 16),
          action!,
        ],
      ],
    ),
  );
}

// ── AppSnack — top-right overlay toast ───────────────────────────────────────
void showAppSnack(BuildContext context, String msg, {Color? color, bool isError = false}) {
  final c = isError ? kRed : (color ?? kGreen);
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _AppToastOverlay(
      msg: msg,
      color: c,
      isError: isError,
      padding: MediaQuery.of(context).padding,
      screenWidth: MediaQuery.of(context).size.width,
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(milliseconds: 2200), () {
    try { entry.remove(); } catch (_) {}
  });
}

class _AppToastOverlay extends StatefulWidget {
  final String msg;
  final Color color;
  final bool isError;
  final EdgeInsets padding;
  final double screenWidth;
  const _AppToastOverlay({
    required this.msg, required this.color, required this.isError,
    required this.padding, required this.screenWidth,
  });
  @override State<_AppToastOverlay> createState() => _AppToastOverlayState();
}

class _AppToastOverlayState extends State<_AppToastOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))..forward();
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, -0.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    // Begin fade-out before removal
    Future.delayed(const Duration(milliseconds: 1700), () {
      if (mounted) _ctrl.reverse();
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final top = widget.padding.top + 12;
    final right = 12.0;
    final width = (widget.screenWidth * 0.72).clamp(220.0, 360.0);
    return Positioned(
      top: top, right: right,
      width: width,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: kCard2,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: kBorder2, width: 0.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(children: [
                Icon(widget.isError ? Icons.error_outline : Icons.check_circle_outline,
                    size: 16, color: widget.color),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.msg,
                    style: GoogleFonts.inter(color: kText, fontSize: 13, height: 1.4))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── AppSectionHeader ──────────────────────────────────────────────────────────
class AppSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const AppSectionHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
    child: Row(children: [
      AppLabel(title),
      const Spacer(),
      if (trailing != null) trailing!,
    ]),
  );
}
