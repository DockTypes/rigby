import 'package:flutter/material.dart';
import 'features/splash/widgets/rigby_logo_painter.dart';
import 'features/island/overlay_island_app.dart';

@pragma('vm:entry-point')
void overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await RigbyLogoPaths.load();
  } catch (_) {
    // Continue without logo paths — overlay still renders
  }
  runApp(const OverlayIslandApp());
}
