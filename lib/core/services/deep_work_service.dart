import 'package:flutter/services.dart';

/// Manages system Do Not Disturb (DND) state for Deep Work sessions via platform channels.
class DeepWorkService {
  static const MethodChannel _channel = MethodChannel('com.rigby.app/system_control');

  static bool _isDeepWorkActive = false;

  /// True if Deep Work mode was activated by Rigby and needs restoration on completion.
  static bool get isDeepWorkActive => _isDeepWorkActive;

  /// Activates Do Not Disturb mode. Returns true on success.
  /// If ACCESS_NOTIFICATION_POLICY is missing, opens system settings and returns false.
  static Future<bool> enableDnd() async {
    try {
      final success = await _channel.invokeMethod<bool>('enableDnd');
      if (success == true) {
        _isDeepWorkActive = true;
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Deactivates Do Not Disturb mode.
  static Future<bool> disableDnd() async {
    try {
      final success = await _channel.invokeMethod<bool>('disableDnd');
      if (success == true) {
        _isDeepWorkActive = false;
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Resets internal tracking state.
  static void markInactive() {
    _isDeepWorkActive = false;
  }
}
