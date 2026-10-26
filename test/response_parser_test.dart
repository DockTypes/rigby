import 'package:flutter_test/flutter_test.dart';
import 'package:rigby/core/services/response_parser.dart';
import 'package:rigby/features/chat/widgets/rigby_schedule_sheet.dart';

void main() {
  group('ResponseParser', () {
    test('Parsează tag-ul [TIMER: N] corect și curăță textul', () {
      final parsed = ResponseParser.parse('Am pornit. [TIMER: 15]');
      expect(parsed.timerMinutes, 15);
      expect(parsed.cleanText, 'Am pornit.');
    });

    test('Parsează tag-ul [SCHEDULE: scope] corect', () {
      final parsed = ResponseParser.parse('Iată orarul. [SCHEDULE: joi]');
      expect(parsed.scheduleScope, ScheduleScope.joi);
      expect(parsed.cleanText, 'Iată orarul.');
    });

    test('Parsează [REMINDER] cu text și timp', () {
      final parsed = ResponseParser.parse('Gata. [REMINDER: 2026-06-02 10:00|Cumpără lapte]');
      expect(parsed.reminder?.body, 'Cumpără lapte');
      expect(parsed.reminder?.time, '2026-06-02 10:00');
      expect(parsed.cleanText, 'Gata.');
    });

    test('Nu extrage nimic dintr-un text curat', () {
      final parsed = ResponseParser.parse('Salut, eu sunt Rigby.');
      expect(parsed.timerMinutes, isNull);
      expect(parsed.scheduleScope, isNull);
      expect(parsed.reminder, isNull);
      expect(parsed.showCapabilities, isFalse);
      expect(parsed.timerCancelled, isFalse);
      expect(parsed.cleanText, 'Salut, eu sunt Rigby.');
    });
  });
}
