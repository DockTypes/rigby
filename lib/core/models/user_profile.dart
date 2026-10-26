import 'package:shared_preferences/shared_preferences.dart';

class UserProfile {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static String get prenume => _prefs?.getString('profile_prenume') ?? '';
  static set prenume(String v) => _prefs?.setString('profile_prenume', v);

  static String get specializare => _prefs?.getString('profile_specializare') ?? '';
  static set specializare(String v) => _prefs?.setString('profile_specializare', v);

  static int get anul => _prefs?.getInt('profile_anul') ?? 1;
  static set anul(int v) => _prefs?.setInt('profile_anul', v);

  static String get grupa => _prefs?.getString('profile_grupa') ?? '';
  static set grupa(String v) => _prefs?.setString('profile_grupa', v);

  static bool get isComplete =>
      prenume.isNotEmpty && specializare.isNotEmpty && grupa.isNotEmpty;

  static void clear() {
    _prefs?.remove('profile_prenume');
    _prefs?.remove('profile_specializare');
    _prefs?.remove('profile_anul');
    _prefs?.remove('profile_grupa');
  }
}
