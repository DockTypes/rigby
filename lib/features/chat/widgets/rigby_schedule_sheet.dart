import 'package:flutter/material.dart';
import '../../../core/services/schedule_service.dart';
import '../../../core/theme/app_colors.dart';

/// Schedule visualization scope parsed from Gemini's [SCHEDULE: ...] tag.
enum ScheduleScope {
  today,
  tomorrow,
  luni,
  marti,
  miercuri,
  joi,
  vineri,
  week,
  weekPara,
  weekImpara,
}

ScheduleScope? parseScope(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'today':
    case 'azi':
      return ScheduleScope.today;
    case 'tomorrow':
    case 'maine':
    case 'mâine':
      return ScheduleScope.tomorrow;
    case 'luni':
      return ScheduleScope.luni;
    case 'marti':
    case 'marți':
      return ScheduleScope.marti;
    case 'miercuri':
      return ScheduleScope.miercuri;
    case 'joi':
      return ScheduleScope.joi;
    case 'vineri':
      return ScheduleScope.vineri;
    case 'week':
    case 'saptamana':
    case 'săptămâna':
      return ScheduleScope.week;
    case 'week_para':
    case 'saptamana_para':
    case 'para':
      return ScheduleScope.weekPara;
    case 'week_impara':
    case 'saptamana_impara':
    case 'impara':
    case 'impară':
      return ScheduleScope.weekImpara;
  }
  return null;
}

class RigbyScheduleSheet extends StatefulWidget {
  final ScheduleScope scope;
  final UserSchedule schedule;

  const RigbyScheduleSheet({
    super.key,
    required this.scope,
    required this.schedule,
  });

  @override
  State<RigbyScheduleSheet> createState() => _RigbyScheduleSheetState();
}

class _RigbyScheduleSheetState extends State<RigbyScheduleSheet>
    with SingleTickerProviderStateMixin {
  // Row stagger animation configuration (stagger * rows + itemDuration).
  static const int _stagger = 45;
  static const int _itemDuration = 380;
  static const double _slideFrom = 18.0;

  late final List<DaySchedule> _filteredDays;
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _filteredDays = _filterDays();
    int rows = 1;
    for (final d in _filteredDays) {
      rows += 1 + d.slots.length;
    }
    final totalMs = rows * _stagger + _itemDuration;
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final title = _titleForScope();
    final subtitle = _subtitleForUser();

    int idx = 0;
    final headerWidget = _animatedRow(idx++, _Header(
      title: title,
      subtitle: subtitle,
      onClose: () => Navigator.of(context).pop(),
    ));

    final List<Widget> bodyRows = [];
    if (_filteredDays.isEmpty) {
      bodyRows.add(_animatedRow(idx++, _empty()));
    } else {
      for (final d in _filteredDays) {
        bodyRows.add(_animatedRow(idx++, _DayHeader(day: d.day)));
        for (final slot in d.slots) {
          bodyRows.add(_animatedRow(
            idx++,
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SlotTile(slot: slot),
            ),
          ));
        }
      }
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textMuted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          headerWidget,
          const Divider(height: 1, color: AppColors.borderSubtle),
          Flexible(
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, 12, 20, mq.padding.bottom + 24),
              physics: const BouncingScrollPhysics(),
              children: bodyRows,
            ),
          ),
        ],
      ),
    );
  }

  // Staggered fade and translation per row index.
  Widget _animatedRow(int index, Widget child) {
    final total = _ctrl.duration!.inMilliseconds;
    final start = (index * _stagger) / total;
    final end = ((index * _stagger) + _itemDuration) / total;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final raw = (_ctrl.value - start) / (end - start);
        final t = Curves.easeOutCubic.transform(raw.clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * _slideFrom),
            child: child,
          ),
        );
      },
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Text(
            'Nicio oră în acest interval.',
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.85),
              fontSize: 13.5,
              letterSpacing: 0.3,
            ),
          ),
        ),
      );

  String _titleForScope() {
    switch (widget.scope) {
      case ScheduleScope.today:
        return 'Astăzi · ${ScheduleService.dayNameRo(DateTime.now().weekday)}';
      case ScheduleScope.tomorrow:
        return 'Mâine · ${ScheduleService.dayNameRo(_tomorrowWeekday())}';
      case ScheduleScope.luni: return 'Luni';
      case ScheduleScope.marti: return 'Marți';
      case ScheduleScope.miercuri: return 'Miercuri';
      case ScheduleScope.joi: return 'Joi';
      case ScheduleScope.vineri: return 'Vineri';
      case ScheduleScope.week: return 'Săptămâna';
      case ScheduleScope.weekPara: return 'Săptămâna pară';
      case ScheduleScope.weekImpara: return 'Săptămâna impară';
    }
  }

  String _subtitleForUser() {
    final s = widget.schedule.specialization
        .replaceAll('-', ' ')
        .replaceFirstMapped(RegExp(r'^[a-z]'), (m) => m.group(0)!.toUpperCase());
    final parts = <String>[s, 'an ${widget.schedule.year}', 'gr. ${widget.schedule.group}'];
    if (widget.schedule.semester != null) parts.add('sem. ${widget.schedule.semester}');
    return parts.join(' · ').toUpperCase();
  }

  int _tomorrowWeekday() {
    final w = DateTime.now().weekday + 1;
    return w > 7 ? 1 : w;
  }

  List<DaySchedule> _filterDays() {
    final all = widget.schedule.days;
    String? targetDay;
    String? parityFilter;
    switch (widget.scope) {
      case ScheduleScope.today:
        targetDay = ScheduleService.dayNameRo(DateTime.now().weekday);
        break;
      case ScheduleScope.tomorrow:
        targetDay = ScheduleService.dayNameRo(_tomorrowWeekday());
        break;
      case ScheduleScope.luni: targetDay = 'Luni'; break;
      case ScheduleScope.marti: targetDay = 'Marți'; break;
      case ScheduleScope.miercuri: targetDay = 'Miercuri'; break;
      case ScheduleScope.joi: targetDay = 'Joi'; break;
      case ScheduleScope.vineri: targetDay = 'Vineri'; break;
      case ScheduleScope.week: break;
      case ScheduleScope.weekPara: parityFilter = 'PARA'; break;
      case ScheduleScope.weekImpara: parityFilter = 'IMPARA'; break;
    }

    Iterable<DaySchedule> days = all;
    if (targetDay != null) {
      final t = _normRo(targetDay);
      days = days.where((d) => _normRo(d.day) == t);
    }
    final result = <DaySchedule>[];
    for (final d in days) {
      List<ScheduleSlot> slots = d.slots;
      if (parityFilter != null) {
        slots = slots
            .where((s) => s.parity == null || s.parity == parityFilter)
            .toList();
      }
      if (slots.isEmpty) continue;
      result.add(DaySchedule(day: d.day, slots: slots));
    }
    return result;
  }

  static String _normRo(String s) => s
      .toLowerCase()
      .replaceAll('ă', 'a').replaceAll('â', 'a').replaceAll('î', 'i')
      .replaceAll('ș', 's').replaceAll('ț', 't');
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onClose;
  const _Header({required this.title, required this.subtitle, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    letterSpacing: 0.4,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                color: AppColors.textSecondary, size: 22),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String day;
  const _DayHeader({required this.day});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 18, bottom: 12),
      child: Row(
        children: [
          Text(
            day.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 0.5,
              color: AppColors.border,
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  final ScheduleSlot slot;
  const _SlotTile({required this.slot});

  @override
  Widget build(BuildContext context) {
    final timeText = '${slot.start}\n${slot.end}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              timeText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.neonWhiteDim,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                fontFeatures: [FontFeature.tabularFigures()],
                height: 1.35,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Container(
            width: 0.5,
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: AppColors.border,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  slot.course,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 5),
                _MetaLine(slot: slot),
              ],
            ),
          ),
          if (slot.parity != null) ...[
            const SizedBox(width: 8),
            _ParityPill(parity: slot.parity!),
          ],
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final ScheduleSlot slot;
  const _MetaLine({required this.slot});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (slot.type != null && slot.type!.isNotEmpty) {
      parts.add(_typeBadge(slot.type!));
    }
    if (slot.professor != null && slot.professor!.isNotEmpty) {
      parts.add(slot.professor!);
    }
    if (slot.room != null && slot.room!.isNotEmpty) {
      parts.add(slot.room!);
    }
    return Text(
      parts.join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 11.5,
        height: 1.35,
        letterSpacing: 0.15,
      ),
    );
  }

  String _typeBadge(String type) {
    switch (type.toLowerCase()) {
      case 'curs':
        return 'C';
      case 'seminar':
        return 'S';
      case 'laborator':
        return 'L';
    }
    return type;
  }
}

class _ParityPill extends StatelessWidget {
  final String parity;
  const _ParityPill({required this.parity});

  @override
  Widget build(BuildContext context) {
    final isPara = parity.toUpperCase() == 'PARA';
    final color = isPara ? const Color(0xFF6FA8DC) : const Color(0xFFE0AA6F);
    final label = isPara ? 'PARĂ' : 'IMPARĂ';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

Future<void> showRigbyScheduleSheet(
  BuildContext context, {
  required ScheduleScope scope,
  required UserSchedule schedule,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => RigbyScheduleSheet(scope: scope, schedule: schedule),
  );
}
