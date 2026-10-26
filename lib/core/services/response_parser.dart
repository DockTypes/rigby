import 'package:flutter/material.dart';
import '../../features/chat/widgets/rigby_schedule_sheet.dart';
import '../../features/island/rigby_island.dart';
import 'notification_service.dart';
import 'schedule_service.dart';

/// Parsed AI response containing cleaned text and extracted intent actions.
class ParsedResponse {
  final String cleanText;
  final bool timerCancelled;
  final int? timerMinutes;
  final bool showCapabilities;
  final ScheduleScope? scheduleScope;
  final ({String time, String body})? reminder;

  const ParsedResponse({
    required this.cleanText,
    this.timerCancelled = false,
    this.timerMinutes,
    this.showCapabilities = false,
    this.scheduleScope,
    this.reminder,
  });
}

/// Parses inline action tags from Gemini / QuickCommands into executable actions and clean text.
///
/// Supported tags:
/// - `[TIMER_CANCEL]` — cancels active timer
/// - `[TIMER: N]`     — starts an N-minute timer
/// - `[CAPABILITIES]` — opens capabilities sheet
/// - `[SCHEDULE: scope]` — opens schedule sheet
/// - `[REMINDER: time | body]` — schedules a local reminder
class ResponseParser {
  ResponseParser._();

  /// Parses text and extracts action tags, returning clean display text and actions.
  static ParsedResponse parse(String text) {
    String clean = text;
    bool timerCancelled = false;
    int? timerMinutes;
    bool showCapabilities = false;
    ScheduleScope? scheduleScope;
    ({String time, String body})? reminder;

    // Check cancel before start regex to prevent [TIMER_CANCEL] from falsely matching.
    if (clean.contains('[TIMER_CANCEL]')) {
      timerCancelled = true;
      clean = clean.replaceAll('[TIMER_CANCEL]', '').trim();
    }

    // Parse Timer
    final timerMatch = RegExp(r'\[TIMER:\s*(\d+)\]').firstMatch(clean);
    if (timerMatch != null) {
      timerMinutes = int.tryParse(timerMatch.group(1) ?? '0') ?? 0;
      if (timerMinutes <= 0) timerMinutes = null;
      clean = clean.replaceAll(timerMatch.group(0)!, '').trim();
    }

    // Parse Capabilities
    if (clean.contains('[CAPABILITIES]')) {
      showCapabilities = true;
      clean = clean.replaceAll('[CAPABILITIES]', '').trim();
    }

    // Parse Schedule
    final scheduleMatch =
        RegExp(r'\[SCHEDULE:\s*([a-zA-Z_]+)\s*\]').firstMatch(clean);
    if (scheduleMatch != null) {
      final scopeRaw = scheduleMatch.group(1) ?? '';
      clean = clean.replaceAll(scheduleMatch.group(0)!, '').trim();
      scheduleScope = parseScope(scopeRaw);
    }

    // Parse Reminder
    final reminderMatch =
        RegExp(r'\[REMINDER:\s*([^|]+)\|\s*(.+?)\]').firstMatch(clean);
    if (reminderMatch != null) {
      final timeStr = reminderMatch.group(1)?.trim();
      final body = reminderMatch.group(2)?.trim();
      if (timeStr != null && body != null) {
        reminder = (time: timeStr, body: body);
      }
      clean = clean.replaceAll(reminderMatch.group(0)!, '').trim();
    }

    return ParsedResponse(
      cleanText: clean,
      timerCancelled: timerCancelled,
      timerMinutes: timerMinutes,
      showCapabilities: showCapabilities,
      scheduleScope: scheduleScope,
      reminder: reminder,
    );
  }

  /// Executes side effects from a [ParsedResponse].
  static void executeActions(
    ParsedResponse parsed, {
    BuildContext? context,
    bool scheduleSheetOpened = false,
    VoidCallback? onScheduleSheetOpened,
  }) {
    if (parsed.timerCancelled) {
      RigbyIslandController.instance.dismissTimer();
    }

    if (parsed.timerMinutes != null && parsed.timerMinutes! > 0) {
      RigbyIslandController.instance.startTimer(parsed.timerMinutes!);
    }

    if (parsed.showCapabilities &&
        context != null &&
        context.mounted &&
        !RigbyIslandController.instance.isAppInBackground) {
      // Handled directly by callers to avoid circular imports.
    }

    if (parsed.scheduleScope != null &&
        !scheduleSheetOpened &&
        context != null &&
        context.mounted &&
        !RigbyIslandController.instance.isAppInBackground) {
      onScheduleSheetOpened?.call();
      _openScheduleSheet(context, parsed.scheduleScope!);
    }

    if (parsed.reminder != null) {
      try {
        final dt =
            DateTime.parse(parsed.reminder!.time.replaceAll(' ', 'T'));
        NotificationService()
            .scheduleReminder('Rigby Memento', parsed.reminder!.body, dt);
      } catch (e) {
        debugPrint('[ResponseParser] Failed to parse reminder time: ${parsed.reminder!.time}');
      }
    }
  }

  static Future<void> _openScheduleSheet(
      BuildContext context, ScheduleScope scope) async {
    await ScheduleService().ensureLoaded();
    final sched = ScheduleService().currentUserSchedule();
    if (sched != null && context.mounted) {
      showRigbyScheduleSheet(context, scope: scope, schedule: sched);
    }
  }
}
