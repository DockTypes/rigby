import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app/app.dart';
import 'core/models/app_settings.dart';
import 'core/models/user_profile.dart';
import 'core/services/tts_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/rag_service.dart';
import 'core/services/schedule_service.dart';
import 'core/services/proactive_engine.dart';
import 'features/splash/widgets/rigby_logo_painter.dart';
import 'features/island/overlay_island_app.dart';

@pragma('vm:entry-point')
void overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[OverlayEngine] overlayMain started!');
  try {
    await RigbyLogoPaths.load();
  } catch (_) {}
  runApp(const OverlayIslandApp());
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await AppSettings.init();
  await UserProfile.init();
  await NotificationService().init();
  // Sync TTS engine with persisted setting.
  TtsService.useLocal = AppSettings.useLocalTts;
  await RigbyLogoPaths.load();
  // Preload RAG embeddings (~3MB) in background so first user query has zero lazy-loading delay.
  unawaited(RagService().ensureLoaded());
  unawaited(ScheduleService().ensureLoaded());
  
  // Initialize and start background proactive engine
  await ProactiveEngine.initialize();
  await ProactiveEngine.startPeriodicChecks();
  
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF080808),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const RigbyApp());
}
