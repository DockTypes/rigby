import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_drawing/path_drawing.dart';
import 'dart:math' as math;

class PathData {
  final Path path;
  final Color color;
  final List<PathMetric> metrics;
  PathData(this.path, this.color)
      : metrics = path.computeMetrics().toList();
}

/// Runtime SVG path loader from `lib/assets/logo.svg`.
/// Call [RigbyLogoPaths.load] once before [runApp].
class RigbyLogoPaths {
  RigbyLogoPaths._();

  static List<PathData> _cached = [];

  static List<PathData> get allPaths => _cached;

  static Future<void> load() async {
    if (_cached.isNotEmpty) return;
    _cached = await _parseFromSvg();
  }

  static Future<List<PathData>> _parseFromSvg() async {
    final svg = await rootBundle.loadString('lib/assets/logo.svg');
    final result = <PathData>[];
    int cursor = 0;

    while (true) {
      final start = svg.indexOf('<path ', cursor);
      if (start == -1) break;

      final end = svg.indexOf('/>', start);
      if (end == -1) break;

      final elem = svg.substring(start, end + 2);

      Color color = const Color(0xFFFDFDFC);
      final fillMatch = RegExp(r'fill="([^"]+)"').firstMatch(elem);
      if (fillMatch != null) {
        final hex = fillMatch.group(1)!.trim();
        if (hex.startsWith('#') && hex.length == 7) {
          try {
            color = Color(int.parse('FF${hex.substring(1)}', radix: 16));
            // Black background paths: replace with near-black to stay consistent
            if (color == const Color(0xFF000000)) {
              color = const Color(0xFF060606);
            }
          } catch (_) {}
        }
      }

      final dIdx = elem.indexOf('d="');
      if (dIdx != -1) {
        final dStart = dIdx + 3;
        final dEnd = elem.lastIndexOf('"');
        if (dEnd > dStart) {
          final dStr = elem.substring(dStart, dEnd).trim();
          if (dStr.isNotEmpty) {
            try {
              final path = parseSvgPathData(dStr);
              // Skip the full-canvas background rectangle
              final bounds = path.getBounds();
              final isBackground = bounds.width > 1800 && bounds.height > 1800;
              if (!isBackground) {
                result.add(PathData(path, color));
              }
            } catch (_) {}
          }
        }
      }

      cursor = end + 2;
    }

    return result;
  }
}

/// Painter driving the mascot logo with parametric animations for mouth, eyes,
/// speech shockwave, and quantum deconstruction.
class RigbyLogoPainter extends CustomPainter {
  final double progress;
  final double mouthOpen;
  final double formantRatio;
  final double deconstructFactor;
  final double shockwaveFactor;
  final double tiltX;
  final double tiltY;
  final double thinkingPhase;
  final double eyeCloseFactor;

  RigbyLogoPainter({
    required this.progress,
    this.mouthOpen = 0.0,
    this.formantRatio = 0.5,
    this.deconstructFactor = 0.0,
    this.shockwaveFactor = 0.0,
    this.tiltX = 0.0,
    this.tiltY = 0.0,
    this.thinkingPhase = 0.0,
    this.eyeCloseFactor = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paths = RigbyLogoPaths.allPaths;
    if (paths.isEmpty) return;

    canvas.save();
    canvas.scale(size.width / 2000, size.height / 2000);

    final int count = paths.length;
    final int mouthPathIndex = count > 132 ? 131 : count - 3;
    final center = const Offset(1000, 1000);

    for (int i = 0; i < count; i++) {
      final p = paths[i];
      final double start = (i / count) * 0.8;
      final double end = start + 0.2;

      double localProgress = 0.0;
      if (progress > start) {
        localProgress = (progress - start) / (end - start);
        if (localProgress > 1.0) localProgress = 1.0;
      }

      if (localProgress > 0.0) {
        canvas.save();

        // Quantum deconstruction (thinking)
        if (deconstructFactor > 0) {
          final ringIndex = i % 4;
          final orbitRadius = 150.0 + (ringIndex * 250.0) * deconstructFactor;
          final sysSpin = deconstructFactor * math.pi *
              ((ringIndex % 2 == 0) ? 2.5 : -2.5);
          final continuousSpin = thinkingPhase * math.pi * 2 *
              (ringIndex % 2 == 0 ? 1.2 : -1.8) *
              (0.4 + ringIndex * 0.3);
          final initialAngle = (i / count) * math.pi * 2;
          final currentAngle = initialAngle + sysSpin + continuousSpin;
          canvas.translate(center.dx, center.dy);
          canvas.rotate(sysSpin * 0.5);
          canvas.translate(
            -center.dx + math.cos(currentAngle) * orbitRadius,
            -center.dy + math.sin(currentAngle) * orbitRadius,
          );
        }

        // Shockwave (speaking)
        if (shockwaveFactor > 0.1) {
          canvas.translate(center.dx, center.dy);
          canvas.scale(1.0 + shockwaveFactor * 0.08);
          canvas.translate(-center.dx, -center.dy);
        }

        // Spatial filtering for Eyes and Ears
        if (deconstructFactor == 0.0 && i != mouthPathIndex) {
          // Exclude center-bottom pieces to avoid animating nose/mouth corners as eyes
          final bounds = p.path.getBounds();
          final c = bounds.center;

          // Exclude strictly central items under Y:1000
          bool isMouthArea = c.dy > 1150 && c.dx > 850 && c.dx < 1150;
          
          if (!isMouthArea) {
            bool isLeftEye = c.dx >= 750 && c.dx <= 980 && c.dy >= 650 && c.dy <= 1100;
            bool isRightEye = c.dx >= 1020 && c.dx <= 1250 && c.dy >= 650 && c.dy <= 1100;

            if ((isLeftEye || isRightEye) && eyeCloseFactor > 0.0) {
              canvas.translate(c.dx, c.dy);
              // Squash on Y axis to blink/squint
              canvas.scale(1.0, 1.0 - (eyeCloseFactor * 0.9)); 
              canvas.translate(-c.dx, -c.dy);
            }
          }
        }

        // Suppress mouthPathIndex+1
        if (i == mouthPathIndex + 1 && deconstructFactor == 0.0) {
          canvas.restore();
          continue;
        }

        // Bezier mouth
        if (i == mouthPathIndex && deconstructFactor == 0.0) {
          const double cx = 1000.0;
          const double cy = 1289.0;
          // Formant ratio modifiers:
          // 0.0 (wide mouth for E/I/S) <-> 0.5 (neutral) <-> 1.0 (round tall mouth for O/U).
          final double fRatio = formantRatio.clamp(0.0, 1.0);
          final double widthMod = (0.5 - fRatio) * 70.0;
          final double heightMod = (fRatio - 0.5) * 60.0;

          final double flexX = math.sin(mouthOpen * math.pi) * 12.0;
          
          // Apply formant modifiers to base mouth dimensions.
          final double halfW = 45.0 + flexX + mouthOpen * (25.0 + widthMod); 
          final double upperH = 7.0 + mouthOpen * (18.0 + heightMod * 0.3);
          final double lowerH = 7.0 + mouthOpen * (88.0 + heightMod);

          // Curved organic lip contour adapting to volume amplitude.
          final mouth = Path();
          mouth.moveTo(cx - halfW, cy);
          mouth.cubicTo(
              cx - halfW * 0.5, cy - upperH * 1.3,
              cx + halfW * 0.5, cy - upperH * 1.3, 
              cx + halfW, cy);
          mouth.cubicTo(
              cx + halfW * 0.65, cy + lowerH,
              cx - halfW * 0.65, cy + lowerH, 
              cx - halfW, cy);
          mouth.close();

          canvas.drawPath(
            mouth,
            Paint()
              ..style = PaintingStyle.fill
              ..color = const Color(0xFF060606),
          );

          if (mouthOpen > 0.25) {
            final double ta = ((mouthOpen - 0.25) / 0.35).clamp(0.0, 1.0);
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTRB(cx - halfW * 0.58, cy - upperH * 0.55,
                    cx + halfW * 0.58, cy + lowerH * 0.20),
                const Radius.circular(5),
              ),
              Paint()
                ..style = PaintingStyle.fill
                ..color =
                    const Color(0xFFDDDDDD).withValues(alpha: ta * 0.70),
            );
          }
        } else {
          final fillAlpha = ((localProgress - 0.4) / 0.6).clamp(0.0, 1.0);
          final wireframeAlpha =
              fillAlpha * (1.0 - deconstructFactor).clamp(0.0, 1.0);

          if (localProgress < 1.0 || deconstructFactor > 0) {
            final strokePaint = Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.0 + (shockwaveFactor * 6.0)
              ..color = p.color.withValues(alpha: fillAlpha);

            for (final metric in p.metrics) {
              final extract =
                  metric.extractPath(0.0, metric.length * localProgress);
              canvas.drawPath(extract, strokePaint);

              if (localProgress > 0.0 &&
                  localProgress < 1.0 &&
                  deconstructFactor == 0.0 &&
                  shockwaveFactor == 0.0) {
                final tangent =
                    metric.getTangentForOffset(metric.length * localProgress);
                if (tangent != null) {
                  canvas.drawCircle(
                      tangent.position,
                      5.0,
                      Paint()
                        ..style = PaintingStyle.fill
                        ..color = p.color.withValues(alpha: 0.8)
                        ..maskFilter = const MaskFilter.blur(
                            BlurStyle.normal, 6.0));
                  canvas.drawCircle(
                      tangent.position,
                      1.5,
                      Paint()
                        ..style = PaintingStyle.fill
                        ..color = const Color(0xFFFFFFFF)
                        ..maskFilter = const MaskFilter.blur(
                            BlurStyle.normal, 1.5));
                }
              }
            }
          }

          if (localProgress > 0.4) {
            if (shockwaveFactor > 0.1 &&
                (i % 3 == 0) &&
                deconstructFactor == 0.0) {
              canvas.save();
              canvas.translate(center.dx, center.dy);
              canvas.scale(1.0 + shockwaveFactor * 0.15);
              canvas.translate(-center.dx, -center.dy);
              canvas.drawPath(
                  p.path,
                  Paint()
                    ..style = PaintingStyle.fill
                    ..color = const Color(0xFFFDFDFC)
                        .withValues(alpha: wireframeAlpha * 0.15 * shockwaveFactor));
              canvas.restore();
            }

            canvas.drawPath(
              p.path,
              Paint()
                ..style = PaintingStyle.fill
                ..color = p.color.withValues(alpha: wireframeAlpha),
            );
          }
        }

        canvas.restore();
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RigbyLogoPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.mouthOpen != mouthOpen ||
        oldDelegate.formantRatio != formantRatio ||
        oldDelegate.deconstructFactor != deconstructFactor ||
        oldDelegate.shockwaveFactor != shockwaveFactor ||
        oldDelegate.tiltX != tiltX ||
        oldDelegate.tiltY != tiltY ||
        oldDelegate.thinkingPhase != thinkingPhase ||
        oldDelegate.eyeCloseFactor != eyeCloseFactor;
  }
}
