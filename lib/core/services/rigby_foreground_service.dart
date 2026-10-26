import 'package:flutter/services.dart';

class RigbyForegroundService {
  static const _channel =
      MethodChannel('com.rigby.app/foreground_service');

  // Idempotent guard: prevents redundant service restarts when Flutter lifecycle
  // triggers repeated inactive transitions (e.g. pulling the notification shade).
  static bool _isRunning = false;

  static Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    try {
      await _channel.invokeMethod('start');
    } catch (_) {
      _isRunning = false;
    }
  }

  static Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}
