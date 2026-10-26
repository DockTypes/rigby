import '../models/app_settings.dart';

/// Local voice command handler that bypasses Gemini for trivial queries (time, date, cancel timer).
///
/// Returns the spoken response (possibly containing action tags like [TIMER_CANCEL]),
/// or `null` if the input does not match any quick command pattern (falling back to Gemini).
class QuickCommands {
  static String? tryHandle(String input) {
    final t = input.toLowerCase().trim();
    if (t.isEmpty) return null;

    if (_matches(t, _timePatterns)) return _sayTime();
    if (_matches(t, _datePatterns)) return _sayDate();
    if (_matches(t, _cancelTimerPatterns)) return _sayTimerCancel();
    if (_matches(t, _greetingPatterns)) return _sayGreeting();
    if (_matches(t, _capabilitiesPatterns)) return _sayCapabilities();

    return null;
  }

  static bool _matches(String text, List<String> patterns) {
    for (final p in patterns) {
      // Match whole phrase boundaries to avoid matching substrings in complex sentences.
      final re = RegExp('(?:^|\\b)${RegExp.escape(p)}(?:\$|\\b)');
      if (re.hasMatch(text)) return true;
    }
    return false;
  }

  static const _timePatterns = [
    'cât e ora', 'cat e ora', 'ce oră e', 'ce ora e', 'cât este ceasul',
    'cat este ceasul',
    'what time is it', "what's the time", 'tell me the time',
    'quelle heure est-il', 'quelle heure',
  ];

  static const _datePatterns = [
    'ce dată e azi', 'ce data e azi', 'ce zi e azi', 'în ce zi suntem',
    'in ce zi suntem', 'ce dată este', 'ce data este',
    "what's today's date", 'what is today', 'what day is it', "what's the date",
    'quelle date sommes-nous', 'quel jour sommes-nous', 'quelle est la date',
  ];

  static const _cancelTimerPatterns = [
    'anulează timerul', 'anuleaza timerul', 'oprește timerul',
    'opreste timerul', 'închide timerul', 'inchide timerul',
    'șterge timerul', 'sterge timerul', 'anulează cronometrul',
    'anuleaza cronometrul', 'oprește cronometrul', 'opreste cronometrul',
    'cancel the timer', 'cancel timer', 'stop the timer', 'stop timer',
    'close the timer',
    'annule le minuteur', 'arrête le minuteur', 'arrete le minuteur',
  ];

  static const _greetingPatterns = [
    'salut', 'bună', 'buna', 'bună rigby', 'buna rigby',
    'hello', 'hi rigby', 'hey rigby',
    'bonjour', 'salut rigby',
  ];

  static const _capabilitiesPatterns = [
    'ce poți face', 'ce poti face', 'cu ce mă poți ajuta', 'cu ce ma poti ajuta',
    'cu ce mă ajuți', 'cu ce ma ajuti', 'ce știi să faci', 'ce stii sa faci',
    'arată-mi ce poți face', 'arata-mi ce poti face', 'comenzile tale',
    'ce comenzi ai', 'ce funcții ai', 'ce functii ai', 'ajutor',
    'help', 'what can you do', 'show me what you can do', 'commands',
    'que peux-tu faire', 'aide',
  ];

  static String _pad(int v) => v.toString().padLeft(2, '0');

  static String _sayTime() {
    final now = DateTime.now();
    final h = _pad(now.hour);
    final m = _pad(now.minute);
    return switch (AppSettings.sttLocale) {
      'en_US' => "It's $h:$m.",
      'fr_FR' => 'Il est $h heures $m.',
      _       => 'Este ora $h:$m.',
    };
  }

  static String _sayDate() {
    final now = DateTime.now();
    final months = switch (AppSettings.sttLocale) {
      'en_US' => const [
          'January','February','March','April','May','June',
          'July','August','September','October','November','December'],
      'fr_FR' => const [
          'janvier','février','mars','avril','mai','juin',
          'juillet','août','septembre','octobre','novembre','décembre'],
      _       => const [
          'ianuarie','februarie','martie','aprilie','mai','iunie',
          'iulie','august','septembrie','octombrie','noiembrie','decembrie'],
    };
    final dows = switch (AppSettings.sttLocale) {
      'en_US' => const ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'],
      'fr_FR' => const ['lundi','mardi','mercredi','jeudi','vendredi','samedi','dimanche'],
      _       => const ['luni','marți','miercuri','joi','vineri','sâmbătă','duminică'],
    };
    final dow = dows[now.weekday - 1];
    final month = months[now.month - 1];
    return switch (AppSettings.sttLocale) {
      'en_US' => 'Today is $dow, $month ${now.day}.',
      'fr_FR' => "Nous sommes $dow ${now.day} $month.",
      _       => 'Astăzi este $dow, ${now.day} $month.',
    };
  }

  static String _sayTimerCancel() {
    return switch (AppSettings.sttLocale) {
      'en_US' => 'Timer cancelled. [TIMER_CANCEL]',
      'fr_FR' => 'Minuteur annulé. [TIMER_CANCEL]',
      _       => 'Am anulat timerul. [TIMER_CANCEL]',
    };
  }

  static String _sayGreeting() {
    return switch (AppSettings.sttLocale) {
      'en_US' => 'Hey! What can I do for you?',
      'fr_FR' => 'Salut ! Que puis-je faire pour toi ?',
      _       => 'Salut! Cu ce te pot ajuta?',
    };
  }

  static String _sayCapabilities() {
    return switch (AppSettings.sttLocale) {
      'en_US' => 'Here is everything I can do. [CAPABILITIES]',
      'fr_FR' => 'Voici tout ce que je peux faire. [CAPABILITIES]',
      _       => 'Uite tot ce pot să fac pentru tine. [CAPABILITIES]',
    };
  }
}
