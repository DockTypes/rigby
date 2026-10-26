import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../splash/widgets/rigby_logo_painter.dart';

class OverlayIslandApp extends StatelessWidget {
  const OverlayIslandApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: const ColorScheme.dark(),
      ),
      home: const Scaffold(
        backgroundColor: Colors.transparent,
        body: _OverlayRoot(),
      ),
    );
  }
}

enum _OMode { hidden, idle, listening, speaking, timer }

class _OverlayRoot extends StatefulWidget {
  const _OverlayRoot();

  @override
  State<_OverlayRoot> createState() => _OverlayRootState();
}

class _OverlayRootState extends State<_OverlayRoot> {
  final ValueNotifier<_OMode> _modeNotifier = ValueNotifier(_OMode.hidden);
  String _text = '';
  final ValueNotifier<double> _amplitude = ValueNotifier(0.0);
  final ValueNotifier<int> _timerRemaining = ValueNotifier(0);
  double _paddingTop = 24.0;

  StreamSubscription<dynamic>? _overlaySub;

  @override
  void initState() {
    super.initState();
    _overlaySub = FlutterOverlayWindow.overlayListener.listen(_onData);
    FlutterOverlayWindow.shareData('__overlay_ready__');
  }

  void _onData(dynamic raw) {
    try {
      final map = jsonDecode(raw as String) as Map<String, dynamic>;
      final mode = map['mode'] as String;

      final newPadding = (map['padding_top'] as num?)?.toDouble() ?? _paddingTop;

      switch (mode) {
        case 'timer':
          setState(() {
            _paddingTop = newPadding;
            _modeNotifier.value = _OMode.timer;
          });
          _timerRemaining.value = map['remaining'] as int? ?? 0;
        case 'timer_tick':
          _timerRemaining.value = map['remaining'] as int? ?? 0;
        case 'listening':
          setState(() {
            _paddingTop = newPadding;
            _modeNotifier.value = _OMode.listening;
          });
        case 'speaking':
          setState(() {
            _paddingTop = newPadding;
            _text = map['text'] as String? ?? '';
            _modeNotifier.value = _OMode.speaking;
          });
        case 'amplitude':
          _amplitude.value = (map['value'] as num?)?.toDouble() ?? 0.0;
        case 'idle':
          setState(() {
            _paddingTop = newPadding;
            _modeNotifier.value = _OMode.idle;
          });
          _amplitude.value = 0.0;
        case 'hidden':
          setState(() {
            _paddingTop = newPadding;
            _modeNotifier.value = _OMode.hidden;
          });
          _amplitude.value = 0.0;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _overlaySub?.cancel();
    _amplitude.dispose();
    _modeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mqPad = MediaQuery.of(context).padding.top;
    final topPad = mqPad > 0 ? mqPad : _paddingTop;

    return Stack(
      children: [
        Positioned(
          top: topPad + 8,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: () {
                if (_modeNotifier.value == _OMode.speaking) {
                  FlutterOverlayWindow.shareData('__stop_speaking__');
                }
              },
              // Horizontal swipe dismisses the active timer.
              onHorizontalDragEnd: (details) {
                if (_modeNotifier.value != _OMode.timer) return;
                final v = details.primaryVelocity ?? 0;
                if (v.abs() < 200) return; // Ignore accidental or slow drags.
                FlutterOverlayWindow.shareData('__dismiss_timer__');
              },
              behavior: HitTestBehavior.opaque,
              child: ValueListenableBuilder<_OMode>(
                valueListenable: _modeNotifier,
                builder: (context, mode, _) => _OverlayIsland(
                  mode: mode,
                  text: _text,
                  amplitude: _amplitude,
                  modeNotifier: _modeNotifier,
                  timerRemaining: _timerRemaining,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OverlayIsland extends StatefulWidget {
  final _OMode mode;
  final String text;
  final ValueNotifier<double> amplitude;
  final ValueNotifier<_OMode> modeNotifier;
  final ValueNotifier<int> timerRemaining;

  const _OverlayIsland({
    required this.mode,
    required this.text,
    required this.amplitude,
    required this.modeNotifier,
    required this.timerRemaining,
  });

  @override
  State<_OverlayIsland> createState() => _OverlayIslandState();
}

class _OverlayIslandState extends State<_OverlayIsland>
    with SingleTickerProviderStateMixin {
  late AnimationController _appearCtrl;
  late Animation<double> _scaleCurve;
  late Animation<double> _opacityCurve;
  bool _showText = false;

  @override
  void initState() {
    super.initState();
    _appearCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _scaleCurve = CurvedAnimation(
      parent: _appearCtrl,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    _opacityCurve = CurvedAnimation(
      parent: _appearCtrl,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    if (widget.mode != _OMode.hidden) {
      _appearCtrl.forward();
      _scheduleTextDelay();
    }
  }

  @override
  void didUpdateWidget(_OverlayIsland oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mode != oldWidget.mode) {
      if (widget.mode == _OMode.hidden) {
        _showText = false;
        _appearCtrl.reverse();
      } else {
        _appearCtrl.forward();
        if (widget.mode == _OMode.speaking) {
          _scheduleTextDelay();
        } else {
          _showText = false;
        }
      }
    }
  }

  void _scheduleTextDelay() {
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted && widget.mode == _OMode.speaking) {
        setState(() => _showText = true);
      }
    });
  }

  @override
  void dispose() {
    _appearCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isVisible = widget.mode != _OMode.hidden;
    final isSpeaking = widget.mode == _OMode.speaking;
    final isIdle = widget.mode == _OMode.idle;
    final isTimer = widget.mode == _OMode.timer;

    final targetWidth = isSpeaking ? screenWidth * 0.90 : (isIdle ? 74.0 : (isTimer ? 160.0 : 130.0));
    final targetHeight = isSpeaking ? 62.0 : 58.0;

    // Avoid rendering overhead (ClipRRect, animations) when fully hidden
    // and exit animation has completed.
    if (!isVisible && _appearCtrl.value < 0.01) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      // Allow gestures only for interactive modes: speaking (tap-to-stop) and timer (swipe-to-dismiss).
      ignoring: !isSpeaking && !isTimer,
      child: FadeTransition(
      opacity: _opacityCurve,
      child: ScaleTransition(
        scale: _scaleCurve,
        alignment: Alignment.topCenter,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOutCubic,
          width: isVisible ? targetWidth : 130.0,
          height: isVisible ? targetHeight : 58.0,
          decoration: BoxDecoration(
            // BackdropFilter does not blur native Android windows behind Flutter overlay windows;
            // using a semi-transparent solid color instead.
            color: const Color(0xEB0E0E0E),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.40),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOutCubic,
                    alignment: isSpeaking
                        ? Alignment.centerLeft
                        : (isTimer ? Alignment.centerLeft : Alignment.center),
                    child: _OverlayIslandLogo(
                      amplitude: widget.amplitude,
                      modeNotifier: widget.modeNotifier,
                    ),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: (_showText && isSpeaking) ? 1.0 : 0.0,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 56, right: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _MarqueeText(
                          text: widget.text,
                          style: const TextStyle(
                            color: Color(0xFFD8D8D8),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w400,
                            height: 1.35,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: isTimer ? 1.0 : 0.0,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: ValueListenableBuilder<int>(
                          valueListenable: widget.timerRemaining,
                          builder: (context, rem, _) {
                            final m = rem ~/ 60;
                            final s = rem % 60;
                            final timeStr = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.timer_outlined, color: Colors.orangeAccent.withValues(alpha: 0.9), size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  timeStr,
                                  style: const TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: widget.mode == _OMode.listening ? 1.0 : 0.0,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _OverlayListeningDot(delay: 0),
                            const SizedBox(width: 4),
                            _OverlayListeningDot(delay: 150),
                            const SizedBox(width: 4),
                            _OverlayListeningDot(delay: 300),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class _OverlayIslandLogo extends StatefulWidget {
  final ValueNotifier<double> amplitude;
  final ValueNotifier<_OMode> modeNotifier;

  const _OverlayIslandLogo({
    required this.amplitude,
    required this.modeNotifier,
  });

  @override
  State<_OverlayIslandLogo> createState() => _OverlayIslandLogoState();
}

class _OverlayIslandLogoState extends State<_OverlayIslandLogo>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _proceduralAmp = 0.08;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final mode = widget.modeNotifier.value;
      // Rebuild only in listening or idle mode
      if (mode != _OMode.listening && mode != _OMode.idle) return;
      final sec = elapsed.inMilliseconds / 1000.0;
      _proceduralAmp = (math.sin(sec * 3.0) * 0.07 + 0.09).clamp(0.0, 1.0);
      setState(() {});
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.amplitude,
      builder: (context, amplitude, _) {
        final mode = widget.modeNotifier.value;
        final effectiveAmp =
            mode == _OMode.speaking ? amplitude : _proceduralAmp;
        return SizedBox(
          width: 46,
          height: 46,
          child: CustomPaint(
            size: const Size(46, 46),
            painter: RigbyLogoPainter(
              progress: 1.0,
              mouthOpen: effectiveAmp,
              deconstructFactor: 0.0,
              shockwaveFactor: 0.0,
              tiltX: 0.0,
              tiltY: 0.0,
              thinkingPhase: 0.0,
              eyeCloseFactor: 0.0,
            ),
          ),
        );
      },
    );
  }
}

class _OverlayListeningDot extends StatefulWidget {
  final int delay;
  const _OverlayListeningDot({required this.delay});

  @override
  State<_OverlayListeningDot> createState() => _OverlayListeningDotState();
}

class _OverlayListeningDotState extends State<_OverlayListeningDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _anim = Tween(begin: 0.20, end: 0.75)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

/// Auto-scrolling horizontal marquee text when content exceeds available width.
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _MarqueeText({required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  final ScrollController _scrollCtrl = ScrollController();
  bool _scrolling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartScroll());
  }

  @override
  void didUpdateWidget(_MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _scrolling = false;
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartScroll());
    }
  }

  Future<void> _maybeStartScroll() async {
    if (!mounted || !_scrollCtrl.hasClients || _scrolling) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max <= 0) return;
    _scrolling = true;
    final myText = widget.text;
    await Future.delayed(const Duration(milliseconds: 900));
    while (mounted && _scrollCtrl.hasClients && widget.text == myText) {
      final dist = _scrollCtrl.position.maxScrollExtent;
      if (dist <= 0) break;
      await _scrollCtrl.animateTo(
        dist,
        duration: Duration(milliseconds: (dist * 28).toInt().clamp(800, 12000)),
        curve: Curves.linear,
      );
      if (!mounted || widget.text != myText) break;
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted || !_scrollCtrl.hasClients || widget.text != myText) break;
      await _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
      );
      await Future.delayed(const Duration(milliseconds: 900));
    }
    _scrolling = false;
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _scrollCtrl,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        maxLines: 1,
        softWrap: false,
        style: widget.style,
      ),
    );
  }
}
