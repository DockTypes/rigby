import 'package:flutter/services.dart';

/// Controls Android audio stream volumes to suppress native SpeechRecognizer prompt beeps.
///
/// Temporarily mutes STREAM_MUSIC and STREAM_NOTIFICATION (streams used by SpeechRecognizer
/// for feedback tones) and restores them shortly after the listening session begins.
class AudioBeepSuppressor {
  static const _channel = MethodChannel('com.rigby.app/audio_control');

  /// Temporarily mutes audio streams before `speech.listen()`.
  static Future<void> mute() async {
    try {
      await _channel.invokeMethod('muteBeep');
    } catch (_) {}
  }

  /// Restores stream volumes after the listening session is established.
  static Future<void> unmute() async {
    try {
      await _channel.invokeMethod('unmuteBeep');
    } catch (_) {}
  }
}
