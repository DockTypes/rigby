import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import 'rigby_mascot.dart';
import 'voice_visualizer.dart';

class ChatMessage {
  final String role;
  final String text;
  final DateTime time;
  final Uint8List? imageBytes;

  ChatMessage({required this.role, required this.text, this.imageBytes}) : time = DateTime.now();
}

class RigbyChatSheet extends StatefulWidget {
  final List<ChatMessage> messages;
  final VisualizerState mascotState;
  final ValueNotifier<double> amplitude;
  final Future<void> Function(String text) onSendMessage;
  final VoidCallback? onPickImage;

  const RigbyChatSheet({
    super.key,
    required this.messages,
    required this.mascotState,
    required this.amplitude,
    required this.onSendMessage,
    this.onPickImage,
  });

  @override
  State<RigbyChatSheet> createState() => _RigbyChatSheetState();
}

class _RigbyChatSheetState extends State<RigbyChatSheet> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _isSending = false;
  int _knownMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _knownMessageCount = widget.messages.length;
  }

  @override
  void didUpdateWidget(RigbyChatSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // widget.messages is the same List object as oldWidget.messages (passed by
    // reference), so comparing lengths via oldWidget would always be equal.
    // Compare against our locally tracked count instead.
    if (widget.messages.length != _knownMessageCount) {
      _knownMessageCount = widget.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _isSending) return;
    _ctrl.clear();
    setState(() => _isSending = true);
    await widget.onSendMessage(text);
    if (mounted) setState(() => _isSending = false);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.neonWhite : const Color(0xFF0D0D0D);
    final sheetBg = isDark ? const Color(0xFF0A0A0A) : Colors.white;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: BoxDecoration(
            color: sheetBg.withValues(alpha: isDark ? 0.92 : 0.97),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: fg.withValues(alpha: 0.10),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 3,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 8),

              AnimatedBuilder(
                animation: widget.amplitude,
                builder: (context, _) => RigbyMascot(
                  state: widget.mascotState == VisualizerState.thinking
                      ? VisualizerState.idle
                      : widget.mascotState,
                  amplitude: widget.amplitude,
                  size: 90,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Rigby',
                style: TextStyle(
                  color: fg.withValues(alpha: 0.40),
                  fontSize: 9,
                  letterSpacing: 3.5,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 8),
              Divider(
                color: fg.withValues(alpha: 0.08),
                height: 1,
                indent: 24,
                endIndent: 24,
              ),
              const SizedBox(height: 8),

              Expanded(
                child: widget.messages.isEmpty
                    ? Center(
                        child: Text(
                          'Scrie ceva...',
                          style: TextStyle(
                            color: fg.withValues(alpha: 0.20),
                            fontSize: 13,
                            letterSpacing: 0.5,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        itemCount: widget.messages.length,
                        itemBuilder: (context, i) =>
                            _MessageBubble(msg: widget.messages[i]),
                      ),
              ),

              if (_isSending)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _PulsingDot(delay: 0),
                      const SizedBox(width: 6),
                      _PulsingDot(delay: 200),
                      const SizedBox(width: 6),
                      _PulsingDot(delay: 400),
                    ],
                  ),
                ),

              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad + 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                      decoration: BoxDecoration(
                        color: fg.withValues(alpha: isDark ? 0.05 : 0.04),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: fg.withValues(alpha: 0.12),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _ctrl,
                              style: TextStyle(
                                color: fg.withValues(alpha: 0.88),
                                fontSize: 15,
                                height: 1.4,
                              ),
                              cursorColor: fg,
                              maxLines: 4,
                              minLines: 1,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Scrie un mesaj...',
                                hintStyle: TextStyle(
                                  color: fg.withValues(alpha: 0.25),
                                  fontSize: 15,
                                ),
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (widget.onPickImage != null)
                            GestureDetector(
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.onPickImage!();
                              },
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: fg.withValues(alpha: 0.10),
                                ),
                                child: Icon(
                                  Icons.camera_alt_outlined,
                                  size: 17,
                                  color: fg.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _send,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isSending
                                    ? fg.withValues(alpha: 0.08)
                                    : fg.withValues(alpha: 0.18),
                              ),
                              child: Icon(
                                Icons.arrow_upward_rounded,
                                size: 18,
                                color: fg.withValues(
                                    alpha: _isSending ? 0.25 : 0.75),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage msg;
  const _MessageBubble({required this.msg});

  bool get isUser => msg.role == 'user';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.neonWhite : const Color(0xFF0D0D0D);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(right: 8, bottom: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fg,
              ),
              child: Center(
                child: Text('R',
                    style: TextStyle(
                        color: isDark ? Colors.black : Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: isUser
                    ? fg.withValues(alpha: 0.10)
                    : fg.withValues(alpha: 0.05),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                border: Border.all(
                  color: fg.withValues(alpha: isUser ? 0.12 : 0.07),
                  width: 0.5,
                ),
              ),
              child: isUser
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (msg.imageBytes != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              msg.imageBytes!,
                              width: 180,
                              height: 180,
                              fit: BoxFit.cover,
                            ),
                          ),
                          if (msg.text.isNotEmpty) const SizedBox(height: 8),
                        ],
                        if (msg.text.isNotEmpty)
                          Text(
                            msg.text,
                            style: TextStyle(
                              color: fg.withValues(alpha: 0.85),
                              fontSize: 14,
                              height: 1.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                      ],
                    )
                  : MarkdownBody(
                      data: msg.text,
                      onTapLink: (text, href, title) async {
                        if (href != null) {
                          final uri = Uri.parse(href);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        }
                      },
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          color: fg.withValues(alpha: 0.72),
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: FontWeight.w300,
                        ),
                        a: const TextStyle(
                          color: Color(0xFF4FC3F7),
                          decoration: TextDecoration.underline,
                        ),
                        strong: TextStyle(
                          color: fg.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600,
                        ),
                        code: TextStyle(
                          color: fg.withValues(alpha: 0.80),
                          backgroundColor: fg.withValues(alpha: 0.08),
                          fontSize: 13,
                        ),
                      ),
                    ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final int delay;
  const _PulsingDot({required this.delay});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _a = Tween(begin: 0.25, end: 0.85).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.neonWhite : const Color(0xFF0D0D0D);
    return FadeTransition(
      opacity: _a,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fg.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
