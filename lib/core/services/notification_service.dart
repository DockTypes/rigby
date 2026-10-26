import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();
    // Default to Bucharest timezone
    tz.setLocalLocation(tz.getLocation('Europe/Bucharest'));

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('[Rigby] Notification clicked: ${response.payload}');
      },
    );
  }

  static const int timerNotificationId = 9999;

  Future<int?> scheduleReminder(
    String title,
    String body,
    DateTime scheduledTime, {
    int? customId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final int notificationId = customId ?? (prefs.getInt('next_notification_id') ?? 1000);
    
    // Attempt to request permissions safely (may fail or be unavailable in background isolates)
    try {
      final androidImplementation = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        final notificationsEnabled = await androidImplementation.areNotificationsEnabled();
        if (notificationsEnabled != true) {
          await androidImplementation.requestNotificationsPermission();
        }
        
        final canScheduleExact = await androidImplementation.canScheduleExactNotifications();
        if (canScheduleExact != true) {
          await androidImplementation.requestExactAlarmsPermission();
        }
      }
    } catch (e) {
      debugPrint('[Rigby] permission check skipped/failed: $e');
    }

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        notificationId,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'rigby_reminders',
            'Rigby Reminders',
            channelDescription: 'Task and reminder notifications from Rigby',
            importance: Importance.max,
            priority: Priority.high,
            ticker: 'ticker',
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: jsonEncode({'id': notificationId, 'title': title}),
      );
      
      // Save reminder metadata only for user reminders (not the transient timer)
      if (customId == null) {
        List<String> reminders = prefs.getStringList('rigby_saved_reminders') ?? [];
        reminders.add(jsonEncode({
          'id': notificationId,
          'title': title,
          'body': body,
          'time': scheduledTime.toIso8601String(),
        }));
        await prefs.setStringList('rigby_saved_reminders', reminders);
        await prefs.setInt('next_notification_id', notificationId + 1);
      }
      
      debugPrint('[Rigby] Scheduled reminder $notificationId for $scheduledTime');
      return notificationId;
    } catch (e) {
      debugPrint('[Rigby] Failed to schedule reminder: $e');
      return null;
    }
  }

  Future<void> cancelNotification(int id) async {
    try {
      await flutterLocalNotificationsPlugin.cancel(id);
      debugPrint('[Rigby] Cancelled notification $id');
    } catch (e) {
      debugPrint('[Rigby] Failed to cancel notification $id: $e');
    }
  }
}
