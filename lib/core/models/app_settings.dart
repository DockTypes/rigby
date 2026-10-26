import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static SharedPreferences? _prefs;

  static String _theme = 'dark';
  static String get theme => _theme;

  static final ValueNotifier<ThemeMode> themeNotifier =
      ValueNotifier(ThemeMode.dark);

  static void applyTheme(String value) {
    _theme = value;
    _prefs?.setString('theme', value);
    themeNotifier.value = switch (value) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  static String _sttLocale = 'ro_RO';
  static String get sttLocale => _sttLocale;
  static set sttLocale(String value) {
    _sttLocale = value;
    _prefs?.setString('sttLocale', value);
  }

  static String _aiPersonality = 'prietenos';
  static String get aiPersonality => _aiPersonality;
  static set aiPersonality(String value) {
    _aiPersonality = value;
    _prefs?.setString('aiPersonality', value);
  }

  // When true, uses free device-local TTS; when false, uses ElevenLabs cloud TTS.
  static bool _useLocalTts = true;
  static bool get useLocalTts => _useLocalTts;
  static set useLocalTts(bool value) {
    _useLocalTts = value;
    _prefs?.setBool('useLocalTts', value);
  }

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _theme = _prefs!.getString('theme') ?? 'dark';
    _sttLocale = _prefs!.getString('sttLocale') ?? 'ro_RO';
    _aiPersonality = _prefs!.getString('aiPersonality') ?? 'prietenos';
    _useLocalTts = _prefs!.getBool('useLocalTts') ?? true;
    themeNotifier.value = switch (_theme) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }
}
