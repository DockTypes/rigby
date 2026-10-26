import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Captures real speaker audio amplitude using the Android `Visualizer` API (session 0).
///
/// Emits normalized values (0.0-1.0) at the Visualizer capture rate for lip sync.
class AudioVisualizer {
  static const _channel = EventChannel('com.rigby.app/audio_visualizer');

  StreamSubscription<dynamic>? _sub;
  Function(double, double)? onFft;

  /// Starts visualizer capture emitting RMS amplitude and FFT formantRatio.
  void start() {
    if (_sub != null) return;

    _sub = _channel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          final amp = (event['amp'] as num?)?.toDouble() ?? 0.0;
          final formant = (event['formant'] as num?)?.toDouble() ?? 0.5;
          onFft?.call(amp, formant);
        }
      },
      onError: (dynamic error) {
        debugPrint('[AudioVisualizer] Stream error: $error');
      },
      cancelOnError: false,
    );
  }

  /// Stops visualizer capture.
  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// Releases resources.
  void dispose() {
    stop();
    onFft = null;
  }
}
