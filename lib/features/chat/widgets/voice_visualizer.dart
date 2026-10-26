import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

enum VisualizerState { idle, listening, thinking, speaking }

class VoiceVisualizer extends StatefulWidget {
  final VisualizerState state;
  final double size;

  const VoiceVisualizer({
    super.key,
    this.state = VisualizerState.idle,
    this.size = 200,
  });

  @override
  State<VoiceVisualizer> createState() => _VoiceVisualizerState();
}

class _VoiceVisualizerState extends State<VoiceVisualizer>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _waveController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  bool get _isActive =>
      widget.state == VisualizerState.listening ||
      widget.state == VisualizerState.speaking;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_waveController, _pulseController]),
      builder: (context, _) {
        return Transform.scale(
          scale: _pulseAnim.value,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _VisualizerPainter(
                progress: _waveController.value,
                state: widget.state,
                isActive: _isActive,
                random: _random,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  final double progress;
  final VisualizerState state;
  final bool isActive;
  final Random random;

  _VisualizerPainter({
    required this.progress,
    required this.state,
    required this.isActive,
    required this.random,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseRadius = size.width * 0.28;

    _drawGlowRing(canvas, cx, cy, baseRadius * 1.6, 0.06);
    _drawGlowRing(canvas, cx, cy, baseRadius * 1.3, 0.1);

    final circlePaint = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), baseRadius, circlePaint);

    final borderPaint = Paint()
      ..color = AppColors.neonWhite.withValues(
          alpha: isActive ? 0.4 : 0.15)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(cx, cy), baseRadius, borderPaint);

    if (state != VisualizerState.idle) {
      _drawWaveBars(canvas, cx, cy, baseRadius);
    }

    _drawCenterIcon(canvas, cx, cy, baseRadius * 0.25);
  }

  void _drawGlowRing(Canvas canvas, double cx, double cy, double r, double alpha) {
    final paint = Paint()
      ..color = AppColors.neonWhite.withValues(alpha: alpha)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset(cx, cy), r, paint);
  }

  void _drawWaveBars(Canvas canvas, double cx, double cy, double baseRadius) {
    const barCount = 48;
    const innerPad = 4.0;
    final maxBarHeight = baseRadius * 0.45;

    for (int i = 0; i < barCount; i++) {
      final angle = (i / barCount) * 2 * pi - pi / 2;
      final phase = progress * 2 * pi;
      final wave1 = sin(i * 0.4 + phase * 2.5);
      final wave2 = sin(i * 0.2 + phase * 1.8 + 1.2);
      final combined = (wave1 * 0.6 + wave2 * 0.4).abs();
      final barH = isActive
          ? maxBarHeight * (0.15 + combined * 0.85)
          : maxBarHeight * 0.08;

      final innerR = baseRadius + innerPad;
      final outerR = innerR + barH;

      final x1 = cx + innerR * cos(angle);
      final y1 = cy + innerR * sin(angle);
      final x2 = cx + outerR * cos(angle);
      final y2 = cy + outerR * sin(angle);

      final opacity = isActive ? (0.4 + combined * 0.6) : 0.2;
      final paint = Paint()
        ..color = AppColors.neonWhite.withValues(alpha: opacity)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
  }

  void _drawCenterIcon(Canvas canvas, double cx, double cy, double r) {
    final color = isActive
        ? AppColors.neonWhite.withValues(alpha: 0.9)
        : AppColors.neonWhite.withValues(alpha: 0.3);

    if (state == VisualizerState.listening) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy - r * 0.2), width: r * 0.8, height: r * 1.2),
        Radius.circular(r * 0.4),
      );
      canvas.drawRRect(rect, paint);
      canvas.drawArc(
        Rect.fromCenter(center: Offset(cx, cy + r * 0.4), width: r * 1.4, height: r * 0.9),
        0, pi, false, paint,
      );
      canvas.drawLine(Offset(cx, cy + r * 0.85), Offset(cx, cy + r * 1.1), paint);
      canvas.drawLine(Offset(cx - r * 0.3, cy + r * 1.1), Offset(cx + r * 0.3, cy + r * 1.1), paint);
    } else {
      canvas.drawCircle(
        Offset(cx, cy),
        r * 0.35,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_VisualizerPainter old) =>
      old.progress != progress || old.state != state;
}
