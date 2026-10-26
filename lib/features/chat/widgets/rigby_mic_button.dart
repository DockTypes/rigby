import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class RigbyMicButton extends StatefulWidget {
  final bool isListening;
  final bool isEnabled;
  final VoidCallback onTap;
  final ValueNotifier<double> amplitude;

  const RigbyMicButton({
    super.key,
    required this.isListening,
    required this.isEnabled,
    required this.onTap,
    required this.amplitude,
  });

  @override
  State<RigbyMicButton> createState() => _RigbyMicButtonState();
}

class _RigbyMicButtonState extends State<RigbyMicButton> {
  double _smoothAmp = 0.0;

  @override
  void initState() {
    super.initState();
    widget.amplitude.addListener(_onAmpUpdate);
  }

  void _onAmpUpdate() {
    if (mounted) {
      setState(() {
        _smoothAmp = _smoothAmp + (widget.amplitude.value - _smoothAmp) * 0.70;
      });
    }
  }

  @override
  void didUpdateWidget(RigbyMicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.amplitude != oldWidget.amplitude) {
      oldWidget.amplitude.removeListener(_onAmpUpdate);
      widget.amplitude.addListener(_onAmpUpdate);
    }
    if (!widget.isListening && oldWidget.isListening) {
      _smoothAmp = 0.0;
    }
  }

  @override
  void dispose() {
    widget.amplitude.removeListener(_onAmpUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double amp = widget.isListening ? _smoothAmp : 0.0;
    
    final double baseWidth = 110.0;
    final double baseHeight = 52.0;

    // Physical micro-scaling reacting to voice amplitude.
    final double wActive = baseWidth + (amp * 16.0);
    final double hActive = baseHeight + (amp * 6.0);
    
    final double w = widget.isListening ? wActive : baseWidth;
    final double h = widget.isListening ? hActive : baseHeight;

    return GestureDetector(
      onTap: widget.isEnabled ? widget.onTap : null,
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        height: 90,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            color: widget.isListening
                ? Colors.white.withValues(alpha: 0.08 + amp * 0.15)
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: Colors.white.withValues(
                alpha: widget.isListening ? 0.35 + amp * 0.5 : 0.12,
              ),
              width: 0.8,
            ),
            boxShadow: widget.isListening && amp > 0.05
                ? [
                    BoxShadow(
                      color: AppColors.neonWhite.withValues(alpha: 0.15 + amp * 0.25),
                      blurRadius: 15 + amp * 25,
                      spreadRadius: 2 + amp * 8,
                    ),
                  ]
                : [],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedScale(
                 duration: const Duration(milliseconds: 150),
                 scale: widget.isListening ? (1.0 + amp * 0.15) : 1.0, 
                 child: Icon(
                    widget.isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: widget.isListening
                        ? Colors.white
                        : Colors.white.withValues(
                            alpha: widget.isEnabled ? 0.75 : 0.25,
                          ),
                    size: 24,
                 ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
