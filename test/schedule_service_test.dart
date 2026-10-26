import 'package:flutter_test/flutter_test.dart';
import 'package:rigby/core/services/schedule_service.dart';

void main() {
  group('ScheduleService', () {
    test('dayNameRo() convertește indexul corect', () {
      expect(ScheduleService.dayNameRo(1), 'Luni');
      expect(ScheduleService.dayNameRo(3), 'Miercuri');
      expect(ScheduleService.dayNameRo(7), 'Duminică');
      expect(ScheduleService.dayNameRo(8), 'Duminică'); // Fallback (clamp la 7)
    });

    test('parseGroup() extrage numărul grupei corect', () {
      expect(ScheduleService.parseGroup('Grupa 3'), 3);
      expect(ScheduleService.parseGroup('grupa 2.1'), 2);
      expect(ScheduleService.parseGroup('gr 1'), 1);
      expect(ScheduleService.parseGroup('nimic'), isNull); // Fără cifre returnează null
    });
  });
}
