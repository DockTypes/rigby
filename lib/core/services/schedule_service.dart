import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import '../models/user_profile.dart';
import 'rag_service.dart';

class ScheduleSlot {
  final String start;
  final String end;
  final String course;
  final String? type;
  final String? groupTarget;
  final String? professor;
  final String? room;
  final String? parity;

  ScheduleSlot({
    required this.start,
    required this.end,
    required this.course,
    this.type,
    this.groupTarget,
    this.professor,
    this.room,
    this.parity,
  });

  factory ScheduleSlot.fromJson(Map<String, dynamic> j) => ScheduleSlot(
        start: (j['start'] ?? '').toString(),
        end: (j['end'] ?? '').toString(),
        course: (j['course'] ?? '').toString(),
        type: j['type'] as String?,
        groupTarget: j['group_target'] as String?,
        professor: j['professor'] as String?,
        room: j['room'] as String?,
        parity: _normParity(j['parity']),
      );

  static String? _normParity(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim().toUpperCase();
    if (s.isEmpty || s == 'NULL' || s == 'NONE') return null;
    return s;
  }
}

class DaySchedule {
  final String day;
  final List<ScheduleSlot> slots;

  DaySchedule({required this.day, required this.slots});

  factory DaySchedule.fromJson(Map<String, dynamic> j) => DaySchedule(
        day: (j['day'] ?? '').toString(),
        slots: ((j['slots'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ScheduleSlot.fromJson)
            .toList(),
      );
}

class UserSchedule {
  final String specialization;
  final int year;
  final int group;
  final String? academicYear;
  final int? semester;
  final List<DaySchedule> days;

  UserSchedule({
    required this.specialization,
    required this.year,
    required this.group,
    required this.days,
    this.academicYear,
    this.semester,
  });

  factory UserSchedule.fromJson(Map<String, dynamic> j) => UserSchedule(
        specialization: j['specialization'] as String,
        year: (j['year'] as num).toInt(),
        group: (j['group'] as num).toInt(),
        academicYear: j['academic_year'] as String?,
        semester: (j['semester'] as num?)?.toInt(),
        days: ((j['days'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(DaySchedule.fromJson)
            .toList(),
      );
}

class ScheduleService {
  static final ScheduleService _instance = ScheduleService._();
  factory ScheduleService() => _instance;
  ScheduleService._();

  List<UserSchedule>? _all;
  Future<void>? _loadFuture;

  Future<void> ensureLoaded() => _loadFuture ??= _load();

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString('assets/rag/schedules.json');
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _all = list.map(UserSchedule.fromJson).toList(growable: false);
      debugPrint('[Schedule] loaded ${_all!.length} schedules');
    } catch (e) {
      debugPrint('[Schedule] load failed: $e');
      _all = const [];
    }
  }

  /// Returns the current user's schedule based on UserProfile, extracting the first integer from group text.
  UserSchedule? currentUserSchedule() {
    final all = _all;
    if (all == null) return null;
    final spec = RagService.normalizeSpec(UserProfile.specializare);
    final year = UserProfile.anul;
    final group = parseGroup(UserProfile.grupa);
    if (spec == null || group == null) return null;
    for (final s in all) {
      if (s.specialization == spec && s.year == year && s.group == group) {
        return s;
      }
    }
    return null;
  }

  static int? parseGroup(String raw) {
    final m = RegExp(r'\d+').firstMatch(raw);
    if (m == null) return null;
    return int.tryParse(m.group(0)!);
  }

  /// Romanian day name for a given DateTime weekday (1=Luni .. 7=Duminică).
  static String dayNameRo(int weekday) {
    const names = ['Luni', 'Marți', 'Miercuri', 'Joi', 'Vineri', 'Sâmbătă', 'Duminică'];
    return names[weekday.clamp(1, 7) - 1];
  }
}
