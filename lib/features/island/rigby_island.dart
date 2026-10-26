import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../../features/splash/widgets/rigby_logo_painter.dart';
import '../../core/services/tts_service.dart';
import '../../core/services/deep_work_service.dart';

/// Background Dynamic Island overlay lifecycle manager.
///
/// Lifecycle model:
/// - A single overlay window is maintained while the app is in the background.
/// - `openOverlay()` initializes the window on app pause and waits for `__overlay_ready__`.
/// - `show*()` and `hide()` push state via coalesced `shareData` (~16ms throttle).
/// - `forceCloseOverlay()` tears down the window on app resume.
enum IslandMode { hidden, idle, listening, speaking, timer }

class RigbyIslandController {
  static final RigbyIslandController instance = RigbyIslandController._();
  RigbyIslandController._() {
    FlutterOverlayWindow.overlayListener.listen((raw) {
      if (raw == '__overlay_ready__') {
        debugPrint('[Rigby] ← __overlay_ready__');
        final c = _readyCompleter;
        if (c != null && !c.isCompleted) c.complete();
        _pushCurrentState();
      } else if (raw == '__stop_speaking__') {
        TtsService().stop();
      } else if (raw == '__dismiss_timer__') {
        dismissTimer();
      }
    });
  }

  final ValueNotifier<IslandMode> modeNotifier =
      ValueNotifier<IslandMode>(IslandMode.hidden);
  final ValueNotifier<String> textNotifier = ValueNotifier<String>('');
  final ValueNotifier<double> amplitudeNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<int> timerSecondsNotifier = ValueNotifier<int>(0);

  bool isAppInBackground = false;
  double devicePixelRatio = 3.0;
  double statusBarHeightDp = 24.0;

  // Overlay window is active only between openOverlay() and forceCloseOverlay().
  bool _overlayOpen = false;
  // Guard against concurrent openOverlay calls during rapid lifecycle transitions.
  bool _opening = false;
  // Re-created per openOverlay call to capture the new ready handshake.
  Completer<void>? _readyCompleter;
  // Overlay window flag: clickThrough allows touches to pass through;
  // defaultFlag captures touches (used during speaking and active timer).
  OverlayFlag _currentFlag = OverlayFlag.clickThrough;

  // Per-frame shareData coalescing for mode and amplitude updates.
  Map<String, dynamic>? _pendingMode;
  Map<String, dynamic>? _pendingAmplitude;
  bool _flushScheduled = false;

  Timer? _focusTimer;
  DateTime? _lastAmplitudeSend;

  /// Opens the overlay window once; idempotent and safe for repeated calls.
  Future<void> openOverlay() async {
    if (_overlayOpen || _opening) return;
    _opening = true;
    try {
      // Permission gate.
      bool hasPermission;
      try {
        final res = await FlutterOverlayWindow.isPermissionGranted();
        hasPermission = res == true;
      } catch (e) {
        debugPrint('[Rigby] permission check failed: $e');
        return;
      }
      if (!hasPermission) {
        debugPrint('[Rigby] ⚠️ overlay permission missing — skip openOverlay');
        return;
      }

      final completer = Completer<void>();
      _readyCompleter = completer;

      try {
        final int overlayHeight =
            (130 * (devicePixelRatio > 0 ? devicePixelRatio : 3.0)).toInt();
        await FlutterOverlayWindow.showOverlay(
          height: overlayHeight,
          width: WindowSize.matchParent,
          alignment: OverlayAlignment.topCenter,
          enableDrag: false,
          // Start with clickThrough (FLAG_NOT_TOUCHABLE | FLAG_NOT_FOCUSABLE).
          // Flags are dynamically updated when touch interaction is needed.
          flag: OverlayFlag.clickThrough,
          overlayTitle: 'Rigby',
          overlayContent: 'Rigby este activ',
          startPosition: OverlayPosition(0, 0),
        );
        _overlayOpen = true;
        _currentFlag = OverlayFlag.clickThrough;
        debugPrint('[Rigby] ✅ overlay opened (h=$overlayHeight)');
      } catch (e) {
        debugPrint('[Rigby] ❌ showOverlay failed: $e');
        _readyCompleter = null;
        return;
      }

      // Await overlay ready signal with a 3-second fallback.
      try {
        await completer.future.timeout(const Duration(seconds: 3));
      } catch (_) {
        debugPrint('[Rigby] ⚠️ __overlay_ready__ timeout — continuă oricum');
      }
      _enqueueMode({'mode': _modeName(modeNotifier.value)});
    } finally {
      _opening = false;
    }
  }

  void hide() {
    amplitudeNotifier.value = 0.0;
    // If a timer is running, revert to timer mode instead of hiding.
    // The timer remains visible until expiration or explicit swipe dismissal.
    if (_timerActive) {
      modeNotifier.value = IslandMode.timer;
      _enqueueMode({
        'mode': 'timer',
        'remaining': timerSecondsNotifier.value,
      });
      return;
    }
    modeNotifier.value = IslandMode.hidden;
    _enqueueMode({'mode': 'hidden'});
  }

  bool get _timerActive => _focusTimer?.isActive ?? false;

  /// Cancels the active timer and hides the overlay (e.g. on horizontal swipe).
  void dismissTimer() {
    _focusTimer?.cancel();
    _focusTimer = null;
    timerSecondsNotifier.value = 0;
    if (DeepWorkService.isDeepWorkActive) {
      DeepWorkService.disableDnd();
    }
    modeNotifier.value = IslandMode.hidden;
    _enqueueMode({'mode': 'hidden'});
  }

  void showIdle() {
    if (modeNotifier.value == IslandMode.idle) return;
    modeNotifier.value = IslandMode.idle;
    _enqueueMode({'mode': 'idle'});
  }

  void showListening() {
    modeNotifier.value = IslandMode.listening;
    _enqueueMode({'mode': 'listening'});
  }

  void showSpeaking(String text) {
    textNotifier.value = text;
    modeNotifier.value = IslandMode.speaking;
    _enqueueMode({'mode': 'speaking', 'text': text});
  }

  void startTimer(int minutes) {
    _focusTimer?.cancel();
    int remaining = minutes * 60;
    timerSecondsNotifier.value = remaining;
    modeNotifier.value = IslandMode.timer;
    _enqueueMode({'mode': 'timer', 'remaining': remaining});

    _focusTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remaining <= 0) {
        timer.cancel();
        _focusTimer = null;
        timerSecondsNotifier.value = 0;
        if (DeepWorkService.isDeepWorkActive) {
          DeepWorkService.disableDnd();
        }
        TtsService().speak(
            "Timerul tău de $minutes minute s-a încheiat. Timp pentru o pauză!");
        showIdle();
      } else {
        remaining--;
        timerSecondsNotifier.value = remaining;
        if (_overlayOpen) {
          // Timer ticks bypass coalescing because every second is a discrete event.
          FlutterOverlayWindow.shareData(
                  jsonEncode({'mode': 'timer_tick', 'remaining': remaining}))
              .catchError((_) {});
        }
      }
    });
  }

  void stopTimer() {
    _focusTimer?.cancel();
    if (DeepWorkService.isDeepWorkActive) {
      DeepWorkService.disableDnd();
    }
    showIdle();
  }

  void updateAmplitude(double v) {
    amplitudeNotifier.value = v;
    if (!isAppInBackground || !_overlayOpen) return;
    final now = DateTime.now();
    if (_lastAmplitudeSend == null ||
        now.difference(_lastAmplitudeSend!) >
            const Duration(milliseconds: 50)) {
      _lastAmplitudeSend = now;
      _pendingAmplitude = {'mode': 'amplitude', 'value': v};
      _scheduleFlush();
    }
  }

  Future<void> forceCloseOverlay() async {
    _overlayOpen = false;
    _readyCompleter = null;
    _pendingMode = null;
    _pendingAmplitude = null;
    _currentFlag = OverlayFlag.clickThrough;
    modeNotifier.value = IslandMode.hidden;
    amplitudeNotifier.value = 0.0;
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
  }

  String _modeName(IslandMode m) => switch (m) {
        IslandMode.hidden => 'hidden',
        IslandMode.idle => 'idle',
        IslandMode.listening => 'listening',
        IslandMode.speaking => 'speaking',
        IslandMode.timer => 'timer',
      };

  void _enqueueMode(Map<String, dynamic> data) {
    if (!_overlayOpen) return;
    data['padding_top'] = statusBarHeightDp;
    // Most recent mode wins during rapid state transitions.
    _pendingMode = data;
    _scheduleFlush();
    _syncFlagForMode(data['mode'] as String);
  }

  // Switch window touch flags: capture touches only when user interaction is required
  // (speaking tap-to-stop or timer swipe-to-dismiss).
  void _syncFlagForMode(String mode) {
    final desired = (mode == 'speaking' || mode == 'timer')
        ? OverlayFlag.defaultFlag
        : OverlayFlag.clickThrough;
    if (desired == _currentFlag) return;
    _currentFlag = desired;
    FlutterOverlayWindow.updateFlag(desired).catchError((e) {
      debugPrint('[Rigby] updateFlag failed: $e');
      return false;
    });
  }

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    Future.delayed(const Duration(milliseconds: 16), _flush);
  }

  Future<void> _flush() async {
    _flushScheduled = false;
    if (!_overlayOpen) {
      _pendingMode = null;
      _pendingAmplitude = null;
      return;
    }
    final mode = _pendingMode;
    final amp = _pendingAmplitude;
    _pendingMode = null;
    _pendingAmplitude = null;
    if (mode != null) {
      try {
        await FlutterOverlayWindow.shareData(jsonEncode(mode));
      } catch (e) {
        debugPrint('[Rigby] shareData(mode) failed: $e');
      }
    }
    if (amp != null) {
      try {
        await FlutterOverlayWindow.shareData(jsonEncode(amp));
      } catch (_) {}
    }
  }

  // Resend current state once overlay ready handshake completes.
  void _pushCurrentState() {
    if (!_overlayOpen) return;
    final mode = modeNotifier.value;
    Map<String, dynamic> payload;
    switch (mode) {
      case IslandMode.speaking:
        payload = {'mode': 'speaking', 'text': textNotifier.value};
      case IslandMode.listening:
        payload = {'mode': 'listening'};
      case IslandMode.idle:
        payload = {'mode': 'idle'};
      case IslandMode.timer:
        payload = {'mode': 'timer', 'remaining': timerSecondsNotifier.value};
      case IslandMode.hidden:
        payload = {'mode': 'hidden'};
    }
    _enqueueMode(payload);
  }
}

class RigbyIslandOverlay extends StatelessWidget {
  const RigbyIslandOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<IslandMode>(
      valueListenable: RigbyIslandController.instance.modeNotifier,
      builder: (context, mode, _) {
        if (mode == IslandMode.hidden) {
          return const SizedBox.shrink();
        }
        return _IslandWidget(mode: mode);
      },
    );
  }
}

class _IslandWidget extends StatefulWidget {
  final IslandMode mode;
  const _IslandWidget({required this.mode});

  @override
  State<_IslandWidget> createState() => _IslandWidgetState();
}

class _IslandWidgetState extends State<_IslandWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _appearCtrl;
  late Animation<double> _scaleCurve;
  late Animation<double> _opacityCurve;

  // Delay text appearance slightly after expansion starts
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

    if (widget.mode != IslandMode.hidden) {
      _appearCtrl.forward();
      _scheduleTextDelay();
    }
  }

  @override
  void didUpdateWidget(_IslandWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mode != oldWidget.mode) {
      if (widget.mode == IslandMode.hidden) {
        _showText = false;
        _appearCtrl.reverse();
      } else {
        _appearCtrl.forward();
        if (widget.mode == IslandMode.speaking) {
          _scheduleTextDelay();
        } else {
          _showText = false;
        }
      }
    }
  }

  void _scheduleTextDelay() {
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted && widget.mode == IslandMode.speaking) {
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
    final topPad = MediaQuery.of(context).padding.top;

    final isVisible = widget.mode != IslandMode.hidden;
    final isSpeaking = widget.mode == IslandMode.speaking;
    final isIdle = widget.mode == IslandMode.idle;
    final isTimer = widget.mode == IslandMode.timer;

    final targetWidth = isSpeaking ? screenWidth * 0.90 : (isIdle ? 74.0 : (isTimer ? 150.0 : 130.0));
    final targetHeight = isSpeaking ? 62.0 : 58.0;

    return Positioned(
      top: topPad + 8,
      left: 0,
      right: 0,
      child: Center(
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
                color: const Color(0xFF0E0E0E).withValues(alpha: 0.92),
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
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
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
                          child: const _IslandLogo(),
                        ),

                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: (_showText && isSpeaking) ? 1.0 : 0.0,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 56),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ValueListenableBuilder<String>(
                                valueListenable:
                                    RigbyIslandController.instance.textNotifier,
                                builder: (context, text, _) => Text(
                                  text,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
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
                        ),

                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: isTimer ? 1.0 : 0.0,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 50),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ValueListenableBuilder<int>(
                                valueListenable: RigbyIslandController.instance.timerSecondsNotifier,
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
                          opacity: widget.mode == IslandMode.listening ? 1.0 : 0.0,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ListeningDot(delay: 0),
                                  const SizedBox(width: 4),
                                  _ListeningDot(delay: 150),
                                  const SizedBox(width: 4),
                                  _ListeningDot(delay: 300),
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
        ),
      ),
    );
  }
}

class _IslandLogo extends StatefulWidget {
  const _IslandLogo();

  @override
  State<_IslandLogo> createState() => _IslandLogoState();
}

class _IslandLogoState extends State<_IslandLogo>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _proceduralAmp = 0.08;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final mode = RigbyIslandController.instance.modeNotifier.value;
      // Rebuild only in listening or idle mode
      if (mode != IslandMode.listening && mode != IslandMode.idle) return;
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
      valueListenable: RigbyIslandController.instance.amplitudeNotifier,
      builder: (context, amplitude, _) {
        final mode = RigbyIslandController.instance.modeNotifier.value;
        final effectiveAmp =
            mode == IslandMode.speaking ? amplitude : _proceduralAmp;

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

class _ListeningDot extends StatefulWidget {
  final int delay;
  const _ListeningDot({required this.delay});

  @override
  State<_ListeningDot> createState() => _ListeningDotState();
}

class _ListeningDotState extends State<_ListeningDot>
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
