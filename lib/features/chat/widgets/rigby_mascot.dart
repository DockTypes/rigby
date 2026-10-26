import 'dart:math' as math;
import 'dart:math' show sin, cos, pi;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import '../../splash/widgets/rigby_logo_painter.dart';
import 'voice_visualizer.dart';

class RigbyMascot extends StatefulWidget {
  final VisualizerState state;
  final double size;
  final ValueNotifier<double> amplitude;
  final ValueNotifier<double>? formantRatio;
  final VoidCallback? onTap;

  const RigbyMascot({
    super.key,
    required this.state,
    required this.amplitude,
    this.formantRatio,
    this.size = 180,
    this.onTap,
  });

  @override
  State<RigbyMascot> createState() => _RigbyMascotState();
}

class _RigbyMascotState extends State<RigbyMascot>
    with TickerProviderStateMixin {
  late AnimationController _ambientCtrl;
  late AnimationController _quantumCtrl;
  late AnimationController _thinkingLoopCtrl;
  late Ticker _renderingTicker;

  double _smoothMouth = 0.0;
  double _smoothFormant = 0.5;
  double _smoothShockwave = 0.0;
  double _smoothEyeClose = 0.0;

  int _lastBlinkMs = 0;
  int _nextBlinkInterval = 3000;
  bool _isBlinking = false;

  @override
  void initState() {
    super.initState();

    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _quantumCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
      reverseDuration: const Duration(milliseconds: 800),
    );

    // Continuous loop for thinking animations (rings, particles, glow pulse).
    _thinkingLoopCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _renderingTicker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(RigbyMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state != oldWidget.state) {
      if (widget.state == VisualizerState.thinking) {
        _quantumCtrl.forward();
        _thinkingLoopCtrl.repeat();
      } else {
        _quantumCtrl.reverse();
        _thinkingLoopCtrl.stop();
        _thinkingLoopCtrl.reset();
      }
    }
  }

  void _onTick(Duration elapsed) {
    final target = (widget.state == VisualizerState.speaking)
        ? widget.amplitude.value
        : 0.0;

    // Damped lerp (0.18) adds visual weight to mouth opening/closing transitions.
    var nextMouth = _smoothMouth + (target - _smoothMouth) * 0.18;

    // Subtle organic jitter to simulate natural speech phonemes.
    if (widget.state == VisualizerState.speaking && nextMouth > 0.05) {
      final ms = elapsed.inMilliseconds.toDouble();
      nextMouth = (nextMouth + sin(ms * 0.062) * 0.015 + sin(ms * 0.091) * 0.01)
          .clamp(0.0, 1.0);
    }

    final shockSpeed = target > _smoothShockwave ? 0.95 : 0.60;
    final nextShock = _smoothShockwave + (target - _smoothShockwave) * shockSpeed;

    final ms = elapsed.inMilliseconds;
    if (!_isBlinking && ms - _lastBlinkMs > _nextBlinkInterval) {
      _isBlinking = true;
      _lastBlinkMs = ms;
    }
    if (_isBlinking && ms - _lastBlinkMs > 150) {
      _isBlinking = false;
      _lastBlinkMs = ms;
      _nextBlinkInterval = 2000 + (ms % 4000);
    }

    double eyeTarget = _isBlinking ? 1.0 : 0.0;
    if (widget.state == VisualizerState.thinking && !_isBlinking) {
       eyeTarget = 0.75; // Squint when thinking
    }

    final nextEye = _smoothEyeClose + (eyeTarget - _smoothEyeClose) * 0.4;
    
    final targetFormant = widget.formantRatio?.value ?? 0.5;
    // Formant ratio transitions slowly (0.12) for smooth vowel morphing.
    final nextFormant = _smoothFormant + (targetFormant - _smoothFormant) * 0.12;

    const epsilon = 0.002;
    if ((nextMouth - _smoothMouth).abs() > epsilon ||
        (nextShock - _smoothShockwave).abs() > epsilon ||
        (nextEye - _smoothEyeClose).abs() > epsilon ||
        (nextFormant - _smoothFormant).abs() > epsilon) {
      setState(() {
        _smoothMouth = nextMouth;
        _smoothShockwave = nextShock;
        _smoothEyeClose = nextEye;
        _smoothFormant = nextFormant;
      });
    } else {
      _smoothMouth = nextMouth;
      _smoothShockwave = nextShock;
      _smoothEyeClose = nextEye;
      _smoothFormant = nextFormant;
    }
  }

  @override
  void dispose() {
    _renderingTicker.dispose();
    _ambientCtrl.dispose();
    _quantumCtrl.dispose();
    _thinkingLoopCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_ambientCtrl, _quantumCtrl, _thinkingLoopCtrl]),
        builder: (context, _) {
          final t = _ambientCtrl.value * pi * 2;
          // Organic breathing / ambient motion
          final baseTiltX = sin(t * 1.0) * 0.15 + sin(t * 2.3) * 0.05;
          final tiltY = cos(t * 1.3) * 0.15 + sin(t * 1.7) * 0.05;

          // Head bobs downward organically as the mouth opens wide
          final headBob = _smoothMouth * 0.18;
          final tiltX = baseTiltX - headBob;

          final qRaw = Curves.easeInOutBack.transform(_quantumCtrl.value);
          final qFactor = qRaw.clamp(0.0, 1.0);
          final phase = _thinkingLoopCtrl.value;

          final glowPulse = qFactor > 0.05
              ? (sin(phase * pi * 2) * 0.5 + 0.5)
              : 0.0;

          final matrix = Matrix4.identity()
            ..setEntry(3, 2, 0.002)
            ..rotateX(tiltX)
            ..rotateY(tiltY);

          if (qRaw > 0.0) {
            matrix.rotateZ(qFactor * pi * 0.5);
          }

          return Stack(
            alignment: Alignment.center,
            children: [
              if (qFactor > 0.05)
                Opacity(
                  opacity: (qFactor * (0.55 + glowPulse * 0.45)).clamp(0.0, 1.0),
                  child: Container(
                    width: widget.size * (0.45 + glowPulse * 0.18),
                    height: widget.size * (0.45 + glowPulse * 0.18),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFDFDFC)
                              .withValues(alpha: 0.30 + glowPulse * 0.18),
                          blurRadius: (45 + glowPulse * 35) * qFactor,
                          spreadRadius: (12 + glowPulse * 18) * qFactor,
                        ),
                        BoxShadow(
                          color: const Color(0xFFD1D0D5)
                              .withValues(alpha: 0.12 + glowPulse * 0.10),
                          blurRadius: (75 + glowPulse * 45) * qFactor,
                          spreadRadius: (28 + glowPulse * 22) * qFactor,
                        ),
                      ],
                    ),
                  ),
                ),

              if (qFactor > 0.08)
                CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _ThinkingFieldPainter(qFactor, phase),
                ),

              Transform(
                transform: matrix,
                alignment: Alignment.center,
                child: CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: RigbyLogoPainter(
                    progress: 1.0,
                    mouthOpen: _smoothMouth,
                    formantRatio: _smoothFormant,
                    deconstructFactor: qFactor,
                    shockwaveFactor: _smoothShockwave,
                    tiltX: tiltX,
                    tiltY: tiltY,
                    thinkingPhase: phase,
                    eyeCloseFactor: _smoothEyeClose,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
}

/// Fluid particle field simulating organic thought around the mascot logo.
///
/// Particles drift using synthetic noise (uncorrelated frequencies per particle)
/// to produce non-repeating organic motion with asynchronous alpha pulsing.
class _ThinkingFieldPainter extends CustomPainter {
  final double factor;
  final double phase;

  // Seeded deterministic particles to prevent jumping across repaints.
  static final List<_FieldParticle> _particles = _seedParticles();

  _ThinkingFieldPainter(this.factor, this.phase);

  static List<_FieldParticle> _seedParticles() {
    final rnd = math.Random(42);
    return List.generate(46, (_) {
      return _FieldParticle(
        homeAngle: rnd.nextDouble() * pi * 2,
        homeRadius: 0.50 + rnd.nextDouble() * 0.42,
        driftFreqA: 0.7 + rnd.nextDouble() * 1.1,
        driftFreqB: 1.3 + rnd.nextDouble() * 1.6,
        driftPhase: rnd.nextDouble() * pi * 2,
        driftAmpAngle: 0.05 + rnd.nextDouble() * 0.18,
        driftAmpRadial: 0.02 + rnd.nextDouble() * 0.06,
        alphaFreq: 0.5 + rnd.nextDouble() * 1.0,
        alphaPhase: rnd.nextDouble() * pi * 2,
        alphaBase: 0.20 + rnd.nextDouble() * 0.30,
        alphaSwing: 0.20 + rnd.nextDouble() * 0.30,
        size: 1.1 + rnd.nextDouble() * 1.8,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (factor <= 0.05) return;

    final center = Offset(size.width / 2, size.height / 2);
    final baseR = size.width * 0.5;
    final t = phase * pi * 2;

    final corePaint = Paint()..style = PaintingStyle.fill;
    final haloPaint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    for (final p in _particles) {
      final driftA = sin(t * p.driftFreqA + p.driftPhase);
      final driftB = cos(t * p.driftFreqB + p.driftPhase * 1.3);

      final angle = p.homeAngle + driftA * p.driftAmpAngle + driftB * p.driftAmpAngle * 0.4;
      final radius = baseR * (p.homeRadius + driftA * p.driftAmpRadial * 0.5
                                            + driftB * p.driftAmpRadial * 0.6);

      final x = center.dx + cos(angle) * radius;
      final y = center.dy + sin(angle) * radius;
      final pos = Offset(x, y);

      final pulse = sin(t * p.alphaFreq + p.alphaPhase);
      final particleAlpha = (p.alphaBase + pulse * p.alphaSwing).clamp(0.0, 1.0);
      final alpha = (factor * particleAlpha).clamp(0.0, 0.85);
      if (alpha < 0.015) continue;

      haloPaint.color = const Color(0xFFFAFAFA).withValues(alpha: alpha * 0.28);
      canvas.drawCircle(pos, p.size * 2.6, haloPaint);

      corePaint.color = const Color(0xFFFFFFFF).withValues(alpha: alpha);
      canvas.drawCircle(pos, p.size, corePaint);
    }
  }

  @override
  bool shouldRepaint(_ThinkingFieldPainter old) =>
      old.factor != factor || old.phase != phase;
}

class _FieldParticle {
  final double homeAngle;
  final double homeRadius;
  final double driftFreqA, driftFreqB, driftPhase;
  final double driftAmpAngle, driftAmpRadial;
  final double alphaFreq, alphaPhase, alphaBase, alphaSwing;
  final double size;

  const _FieldParticle({
    required this.homeAngle,
    required this.homeRadius,
    required this.driftFreqA,
    required this.driftFreqB,
    required this.driftPhase,
    required this.driftAmpAngle,
    required this.driftAmpRadial,
    required this.alphaFreq,
    required this.alphaPhase,
    required this.alphaBase,
    required this.alphaSwing,
    required this.size,
  });
}
