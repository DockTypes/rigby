import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'rigby_logo_painter.dart';

class RigbyLogo extends StatefulWidget {
  final double size;
  final VoidCallback? onDrawComplete;

  const RigbyLogo({super.key, this.size = 120, this.onDrawComplete});

  @override
  State<RigbyLogo> createState() => _RigbyLogoState();
}

class _RigbyLogoState extends State<RigbyLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    );
    _ctrl.forward().then((_) => widget.onDrawComplete?.call());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final v = _ctrl.value;

        // Fade + scale in (0–5%)
        final fadeIn =
            Curves.easeOut.transform((v / 0.05).clamp(0.0, 1.0));
        final scaleIn = Tween(begin: 0.93, end: 1.0).transform(
          Curves.easeOutCubic.transform((v / 0.05).clamp(0.0, 1.0)),
        );

        // Drawing runs 3%–100%
        final drawProgress = Curves.easeInOut.transform(
          ((v - 0.03) / 0.97).clamp(0.0, 1.0),
        );

        return Opacity(
          opacity: fadeIn.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scaleIn,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _AdvancedSvgPainter(progress: drawProgress),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Traces all SVG paths with staggering + pop-in for face features
class _AdvancedSvgPainter extends CustomPainter {
  final double progress;

  const _AdvancedSvgPainter({required this.progress});

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final paths = RigbyLogoPaths.allPaths;
    if (paths.isEmpty) return;

    canvas.save();
    canvas.scale(size.width / 2000, size.height / 2000);

    final int count = paths.length;

    for (int i = 0; i < count; i++) {
      final p = paths[i];

      final double staggerStart = (i / count) * 0.6;
      final double staggerEnd = staggerStart + 0.4;

      if (progress < staggerStart) continue;

      final double rawProgress =
          ((progress - staggerStart) / (staggerEnd - staggerStart))
              .clamp(0.0, 1.0);
      final double drawProgress =
          Curves.easeOutCubic.transform(rawProgress);
      final isComplete = rawProgress >= 1.0;

      // Fill fades in as stroke completes
      final double fillOpacity =
          ((rawProgress - 0.5) / 0.5).clamp(0.0, 1.0);
      if (fillOpacity > 0.0) {
        canvas.drawPath(
          p.path,
          Paint()
            ..style = PaintingStyle.fill
            ..color = p.color.withValues(alpha: fillOpacity),
        );
      }

      // Stroke tracing with laser spark
      if (!isComplete && drawProgress > 0.0) {
        final double currentStrokeWidth =
            2.0 + 4.0 * (1.0 - rawProgress * 0.5);
        final strokePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = currentStrokeWidth
          ..strokeCap = ui.StrokeCap.round
          ..color =
              Color.lerp(const Color(0xFFFFFFFF), p.color, rawProgress)!
                  .withValues(alpha: (1.0 - rawProgress * 0.4).clamp(0.0, 1.0));

        for (final metric in p.metrics) {
          final segmentLen = metric.length;
          if (segmentLen <= 0) continue;
          final double currentLen = segmentLen * drawProgress;
          final ui.Path extract = metric.extractPath(0, currentLen);
          canvas.drawPath(extract, strokePaint);

          final tipOffset = metric.getTangentForOffset(currentLen);
          if (tipOffset != null) {
            canvas.drawCircle(
              tipOffset.position,
              3.0,
              Paint()..color = const Color(0xFFFFFFFF),
            );
            canvas.drawCircle(
              tipOffset.position,
              8.0 * (1.0 - drawProgress),
              Paint()
                ..color = p.color.withValues(alpha: 0.8)
                ..maskFilter =
                    const ui.MaskFilter.blur(ui.BlurStyle.normal, 4.0),
            );
          }
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_AdvancedSvgPainter old) => old.progress != progress;
}
