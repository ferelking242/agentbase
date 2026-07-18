import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/gemini_service.dart';
import '../theme.dart';
import '../widgets/app_components.dart';

class GeminiChatScreen extends StatefulWidget {
  const GeminiChatScreen({super.key});

  @override
  State<GeminiChatScreen> createState() => _GeminiChatScreenState();
}

class _GeminiChatScreenState extends State<GeminiChatScreen> {
  final List<_GMsg> _msgs = [];
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _msgs.add(_GMsg(role: 'user', content: text));
      _ctrl.clear();
      _sending = true;
    });
    _scrollBottom();

    final history = _msgs
        .where((m) => m.role != 'error')
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    final result = await GeminiService().chat(history);

    if (!mounted) return;
    setState(() {
      _sending = false;
      if (result.success) {
        _msgs.add(_GMsg(role: 'model', content: result.text));
      } else {
        _msgs.add(_GMsg(role: 'error', content: result.error ?? 'Erreur inconnue'));
      }
    });
    _scrollBottom();
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _copyMsg(String text) {
    Clipboard.setData(ClipboardData(text: text));
    showAppSnack(context, 'Copié');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _buildHeader(),
        Expanded(
          child: _msgs.isEmpty ? _buildEmpty() : _buildMsgs(),
        ),
        _buildInput(),
      ]),
    );
  }

  Widget _buildHeader() => SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: const BoxDecoration(
            color: kBg,
            border: Border(bottom: BorderSide(color: kBorder, width: 0.5)),
          ),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kBorder, width: 0.5),
                ),
                child: const Icon(Icons.arrow_back_ios_new, size: 13, color: kMuted),
              ),
            ),
            const SizedBox(width: 12),
            // Gemini icon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4285F4), Color(0xFF9C27B0)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Gemini', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w700)),
              Text(GeminiService().statusText,
                  style: GoogleFonts.inter(color: kMuted2, fontSize: 11)),
            ]),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _msgs.clear()),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kBorder, width: 0.5),
                ),
                child: const Icon(Icons.refresh_rounded, size: 17, color: kMuted),
              ),
            ),
          ]),
        ),
      );

  Widget _buildEmpty() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4285F4), Color(0xFF9C27B0)],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.auto_awesome, size: 32, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text(
              'Chat avec Gemini',
              style: GoogleFonts.inter(
                  color: kText, fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Pose tes questions, explore des idées, améliore tes prompts.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: kMuted2, fontSize: 13.5, height: 1.5),
            ),
            if (!GeminiService().hasKeys) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kYellow.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kYellow.withOpacity(0.4), width: 0.5),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: kYellow),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Configure tes clés Gemini dans Paramètres.',
                      style: GoogleFonts.inter(color: kYellow, fontSize: 12.5),
                    ),
                  ),
                ]),
              ),
            ],
          ]),
        ),
      );

  Widget _buildMsgs() => ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        itemCount: _msgs.length + (_sending ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _msgs.length) return const _TypingDots();
          return _MsgBubble(msg: _msgs[i], onCopy: _copyMsg);
        },
      );

  Widget _buildInput() {
    final hasContent = _ctrl.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Container(
          decoration: BoxDecoration(
            color: kCard2,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: kBorder2, width: 1),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    onChanged: (_) => setState(() {}),
                    style: GoogleFonts.inter(color: kText, fontSize: 14.5, height: 1.55),
                    cursorColor: kAccent,
                    cursorWidth: 1.5,
                    decoration: InputDecoration(
                      hintText: 'Pose ta question à Gemini…',
                      hintStyle: GoogleFonts.inter(color: kMuted2, fontSize: 14.5),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: true,
                      fillColor: Colors.transparent,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(children: [
                const Spacer(),
                GestureDetector(
                  onTap: hasContent && !_sending ? _send : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: hasContent && !_sending
                          ? const Color(0xFF4285F4)
                          : const Color(0xFF2A2A2D),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: hasContent ? Colors.transparent : kBorder,
                          width: 0.5),
                    ),
                    child: Icon(
                      _sending ? Icons.hourglass_top_rounded : Icons.arrow_upward_rounded,
                      size: 18,
                      color: hasContent && !_sending ? Colors.white : kMuted2,
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _GMsg {
  final String role; // 'user' | 'model' | 'error'
  final String content;
  _GMsg({required this.role, required this.content});
}

class _MsgBubble extends StatelessWidget {
  final _GMsg msg;
  final void Function(String) onCopy;
  const _MsgBubble({required this.msg, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    final isError = msg.role == 'error';

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: kAccent,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(3),
                ),
              ),
              child: Text(msg.content,
                  style:
                      GoogleFonts.inter(color: Colors.white, fontSize: 13.5, height: 1.5)),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(right: 10, top: 2),
          decoration: BoxDecoration(
            gradient: isError
                ? null
                : const LinearGradient(
                    colors: [Color(0xFF4285F4), Color(0xFF9C27B0)]),
            color: isError ? kRed.withOpacity(0.15) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isError ? Icons.error_outline : Icons.auto_awesome,
            size: 14,
            color: isError ? kRed : Colors.white,
          ),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onLongPress: () => onCopy(msg.content),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isError ? kRed.withOpacity(0.08) : kCard,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(3),
                    topRight: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  ),
                  border: Border.all(
                    color: isError ? kRed.withOpacity(0.3) : kBorder,
                    width: 0.5,
                  ),
                ),
                child: Text(
                  msg.content,
                  style: GoogleFonts.inter(
                    color: isError ? kRed : kText2,
                    fontSize: 13.5,
                    height: 1.6,
                  ),
                ),
              ),
            ),
            if (!isError)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: GestureDetector(
                  onTap: () => onCopy(msg.content),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.copy_outlined, size: 12, color: kMuted2),
                    const SizedBox(width: 4),
                    Text('Copier',
                        style: GoogleFonts.inter(color: kMuted2, fontSize: 11)),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 10, top: 2),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF4285F4), Color(0xFF9C27B0)]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(3),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              border: Border.all(color: kBorder, width: 0.5),
            ),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                return Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
                  final offset = ((_ctrl.value * 3) - i).clamp(0.0, 1.0);
                  final scale = 0.6 + 0.4 * (1 - (offset - 0.5).abs() * 2).clamp(0.0, 1.0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4285F4).withOpacity(0.5 + 0.5 * scale),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }));
              },
            ),
          ),
        ]),
      );
}
