import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/models/app_settings.dart';
import '../core/theme/app_theme.dart';
import '../features/splash/screens/splash_screen.dart';

class RigbyApp extends StatelessWidget {
  const RigbyApp({super.key});

  void _applyStatusBarStyle(ThemeMode mode, BuildContext context) {
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final isDark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system && platformBrightness == Brightness.dark);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: isDark ? const Color(0xFF080808) : Colors.white,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.themeNotifier,
      builder: (context, themeMode, _) {
        _applyStatusBarStyle(themeMode, context);
        return MaterialApp(
          title: 'Rigby',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          home: const SplashScreen(),
        );
      },
    );
  }
}
