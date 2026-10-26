import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../models/user_profile.dart';
import '../models/app_settings.dart';
import 'schedule_service.dart';
import 'gemini_service.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
void proactiveCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      debugPrint('[ProactiveEngine] Running background task...');
      WidgetsFlutterBinding.ensureInitialized();
      
      // Initialize required services in this headless isolate
      final prefs = await SharedPreferences.getInstance();
      await UserProfile.init();
      await AppSettings.init();
      await NotificationService().init();
      
      final scheduleService = ScheduleService();
      await scheduleService.ensureLoaded();
      
      final schedule = scheduleService.currentUserSchedule();
      if (schedule == null) {
        debugPrint('[ProactiveEngine] No schedule found (check UserProfile).');
        return true;
      }

      final now = DateTime.now();
      final dayNames = ['luni', 'marti', 'miercuri', 'joi', 'vineri', 'sambata', 'duminica'];
      final todayName = dayNames[now.weekday - 1];
      
      final todaySchedule = schedule.days.firstWhere(
        (d) => d.day.toLowerCase() == todayName,
        orElse: () => DaySchedule(day: todayName, slots: []),
      );
      
      if (todaySchedule.slots.isEmpty) {
        debugPrint('[ProactiveEngine] No classes today.');
        return true;
      }

      final slots = List<ScheduleSlot>.from(todaySchedule.slots)
        ..sort((a, b) => a.start.compareTo(b.start));

      int timeToMinutes(String t) {
        final parts = t.split(':');
        if (parts.length != 2) return 0;
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }

      final currentMinutes = now.hour * 60 + now.minute;
      
      bool gapFound = false;
      ScheduleSlot? nextClass;
      
      for (int i = 0; i < slots.length - 1; i++) {
        final currentSlotEnd = timeToMinutes(slots[i].end);
        final nextSlotStart = timeToMinutes(slots[i+1].start);
        
        // Gap of at least 60 minutes
        if (nextSlotStart - currentSlotEnd >= 60) {
          if (currentMinutes >= currentSlotEnd && currentMinutes < nextSlotStart) {
            gapFound = true;
            nextClass = slots[i+1];
            break;
          }
        }
      }

      if (gapFound && nextClass != null) {
        // Prevent duplicate notifications for the same gap
        final lastNotifiedKey = 'proactive_notified_${now.year}_${now.month}_${now.day}_${nextClass.start}';
        if (prefs.getBool(lastNotifiedKey) == true) {
          debugPrint('[ProactiveEngine] Already notified for this gap.');
          return true;
        }

        debugPrint('[ProactiveEngine] Gap detected before ${nextClass.course}. Contacting Gemini...');
        
        final gemini = GeminiService();
        final prompt = 'Sunt utilizatorul tău. Acum este o fereastră (pauză) între cursuri. '
            'Următorul meu curs este ${nextClass.course} (${nextClass.type ?? "curs"}) '
            'la ora ${nextClass.start}. Scrie-mi un mesaj super scurt (maxim o propoziție) '
            'prietenos și motivațional, legat de faptul că am o pauză și urmează acest curs.';
            
        // In the background isolate we do not execute interactive tools (UI sheets, timers, etc.).
        // If Gemini attempts a function call, return an immediate no-op result.
        final response = await gemini.sendMessage(
          prompt,
          onFunctionCall: (name, args) async {
            debugPrint('[ProactiveEngine] Ignoring tool call in background: $name');
            return {'result': 'Funcție indisponibilă în background.'};
          },
        );
        
        await NotificationService().scheduleReminder(
          'Rigby Proactiv',
          response,
          now.add(const Duration(seconds: 5)),
        );
        
        await prefs.setBool(lastNotifiedKey, true);
        debugPrint('[ProactiveEngine] Notification sent!');
      } else {
        debugPrint('[ProactiveEngine] Not in a gap right now.');
      }

    } catch (e) {
      debugPrint('[ProactiveEngine] Error: $e');
    }
    return true;
  });
}

class ProactiveEngine {
  static const String _taskName = "com.rigby.proactive_task";

  static Future<void> initialize() async {
    await Workmanager().initialize(
      proactiveCallbackDispatcher,
    );
  }

  static Future<void> startPeriodicChecks() async {
    // Schedule periodic gap checks (minimum 15 mins on Android)
    await Workmanager().registerPeriodicTask(
      "1",
      _taskName,
      frequency: const Duration(hours: 1),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
    debugPrint('[ProactiveEngine] Periodic checks started.');
  }
}
