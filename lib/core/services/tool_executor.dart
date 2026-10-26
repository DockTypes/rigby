import 'package:flutter/material.dart';
import 'notification_service.dart';
import 'schedule_service.dart';
import '../../features/chat/widgets/rigby_schedule_sheet.dart';
import '../../features/island/rigby_island.dart';
import 'deep_work_service.dart';

/// Centralized dispatcher for native tools invoked by Gemini via function calling.
class ToolExecutor {
  /// Executes a native tool by name and arguments received from Gemini.
  ///
  /// [context] — Current BuildContext for presenting UI sheets.
  /// [scheduleSheetOpened] — Prevents multiple schedule sheet presentations in a single turn.
  /// [onScheduleSheetOpened] — Callback invoked when the sheet opens.
  static Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> args, {
    BuildContext? context,
    bool scheduleSheetOpened = false,
    VoidCallback? onScheduleSheetOpened,
  }) async {
    switch (name) {
      case 'startTimer':
        return _startTimer(args);
      case 'startDeepWork':
        return _startDeepWork(args);
      case 'cancelTimer':
        return _cancelTimer();
      case 'scheduleReminder':
        return _scheduleReminder(args);
      case 'openScheduleSheet':
        return _openScheduleSheet(
          args,
          context: context,
          scheduleSheetOpened: scheduleSheetOpened,
          onScheduleSheetOpened: onScheduleSheetOpened,
        );
      case 'analyzePhoto':
        return {'result': 'CAMERA_REQUESTED: Aplicația va deschide camera pentru utilizator.'};
      default:
        return {'result': 'Funcție necunoscută: $name'};
    }
  }

  static Future<Map<String, dynamic>> _startTimer(
      Map<String, dynamic> args) async {
    final minutes = args['minutes'] as int? ?? 0;
    if (minutes > 0) {
      await NotificationService().scheduleReminder(
        'Timer Rigby',
        'Timpul a expirat!',
        DateTime.now().add(Duration(minutes: minutes)),
        customId: NotificationService.timerNotificationId,
      );
      RigbyIslandController.instance.startTimer(minutes);
      return {'result': 'Cronometrul a fost pornit pentru $minutes minute.'};
    }
    return {'result': 'Număr invalid de minute.'};
  }

  static Future<Map<String, dynamic>> _startDeepWork(
      Map<String, dynamic> args) async {
    final minutes = args['minutes'] as int? ?? 0;
    if (minutes > 0) {
      final success = await DeepWorkService.enableDnd();
      if (!success) {
        return {
          'result': 'Permisiunea Do Not Disturb nu a fost acordată. '
              'Am deschis setările pentru ca utilizatorul să o acorde manual.'
        };
      }
      await NotificationService().scheduleReminder(
        'Modul Studiu Rigby',
        'Sesiunea de deep work s-a încheiat!',
        DateTime.now().add(Duration(minutes: minutes)),
        customId: NotificationService.timerNotificationId,
      );
      RigbyIslandController.instance.startTimer(minutes);
      return {
        'result': 'Modul Deep Work (Fără deranj) a fost activat pentru $minutes minute.'
      };
    }
    return {'result': 'Număr invalid de minute.'};
  }

  static Future<Map<String, dynamic>> _cancelTimer() async {
    await NotificationService()
        .cancelNotification(NotificationService.timerNotificationId);
    if (DeepWorkService.isDeepWorkActive) {
      await DeepWorkService.disableDnd();
    }
    RigbyIslandController.instance.dismissTimer();
    return {'result': 'Cronometrul a fost oprit.'};
  }

  static Future<Map<String, dynamic>> _scheduleReminder(
      Map<String, dynamic> args) async {
    final time = args['time'] as String?;
    final body = args['body'] as String?;
    if (time != null && body != null) {
      final dt = DateTime.tryParse(time);
      if (dt != null) {
        await NotificationService()
            .scheduleReminder('Memento Rigby', body, dt);
        return {'result': 'Memento-ul a fost salvat cu succes.'};
      }
    }
    return {'result': 'Format de timp invalid.'};
  }

  static Future<Map<String, dynamic>> _openScheduleSheet(
    Map<String, dynamic> args, {
    BuildContext? context,
    bool scheduleSheetOpened = false,
    VoidCallback? onScheduleSheetOpened,
  }) async {
    final scopeStr = args['scope'] as String?;
    final scope = parseScope(scopeStr ?? 'today') ?? ScheduleScope.today;

    if (!scheduleSheetOpened &&
        !RigbyIslandController.instance.isAppInBackground &&
        context != null &&
        context.mounted) {
      onScheduleSheetOpened?.call();
      await ScheduleService().ensureLoaded();
      if (!context.mounted) return {'result': 'Eroare internă.'};
      final sched = ScheduleService().currentUserSchedule();
      if (sched != null) {
        showRigbyScheduleSheet(context, scope: scope, schedule: sched);
      }
    }
    return {
      'result': 'SUCCESS: Orarul a fost deschis pe ecran. ACUM ESTE OBLIGATORIU SĂ CITEȘTI ORARUL CU VOCE TARE UTILIZATORULUI (interval orar, materie, tip, profesor, sală). NU LĂSA RĂSPUNSUL GOL!'
    };
  }
}
