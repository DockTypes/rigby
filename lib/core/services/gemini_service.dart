import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../config/api_keys.dart';
import '../models/app_settings.dart';
import '../models/user_profile.dart';
import 'rag_service.dart';
import 'schedule_service.dart';

class GeminiService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  static const String _apiKey = ApiKeys.gemini;

  // Use v1beta REST API which fully supports system_instruction
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:streamGenerateContent';

  // Chat history for context
  final List<Map<String, dynamic>> _history = [];
  static const int _maxHistoryEntries = 20;

  String get _systemPrompt {
    final langRule = switch (AppSettings.sttLocale) {
      'en_US' => 'You ALWAYS respond in English, no matter what language the user writes in.',
      'fr_FR' => 'Tu réponds TOUJOURS en français, quelle que soit la langue utilisée par l\'utilisateur.',
      _        => 'Răspunzi MEREU în limba română, indiferent de limba în care scrie utilizatorul.',
    };

    final personalityRule = switch (AppSettings.aiPersonality) {
      'formal' => switch (AppSettings.sttLocale) {
          'en_US' => 'Use a formal, polite and professional tone. Avoid casual expressions.',
          'fr_FR' => 'Utilise un ton formel, poli et professionnel. Évite les expressions familières.',
          _       => 'Folosești un ton formal, politicos și profesionist. Evită expresiile familiare.',
        },
      'concis' => switch (AppSettings.sttLocale) {
          'en_US' => 'Be VERY brief — one sentence, two at most. Be direct.',
          'fr_FR' => 'Sois TRÈS bref — une phrase, deux au maximum. Va droit au but.',
          _       => 'Răspunzi FOARTE SCURT — o singură propoziție, maxim două. Fii direct și la obiect.',
        },
      _ => switch (AppSettings.sttLocale) {
          'en_US' => 'Be enthusiastic, warm and friendly. Use a relaxed, natural conversational tone.',
          'fr_FR' => 'Sois enthousiaste, chaleureux et amical. Utilise un ton détendu et naturel.',
          _       => 'Ești entuziast, cald și prietenos. Folosești un ton relaxat și natural.',
        },
    };

    // Short-answer rules in the prompt header suffice without a separate completeness rule.
    const completenessRule = '';

    final scheduleRule = switch (AppSettings.sttLocale) {
      'en_US' => 'If the user asks about their class schedule (today, tomorrow, a '
          'specific weekday, the week, even/odd week), call the openScheduleSheet tool and '
          'READ OUT each class with FULL details: time interval, course name, type (curs/seminar/laborator), '
          'PROFESSOR, and ROOM. Speak conversationally — no bullet points or markdown.',
      'fr_FR' => 'Si l\'utilisateur demande son emploi du temps, appelle l\'outil openScheduleSheet et '
          'ÉNUMÈRE chaque cours avec TOUS les détails: intervalle horaire, matière, type, PROFESSEUR et '
          'SALLE. Parle de manière conversationnelle (pas de puces, pas de markdown).',
      _       => 'Pentru întrebări despre orar, regula de răspuns scurt NU se '
          'aplică. Vorbește FLUENT și NATURAL, ca un coleg care îți povestește '
          'orarul. Folosește instrumentul openScheduleSheet. Pentru fiecare oră menționează: '
          'intervalul, „cursul"/„seminarul"/„laboratorul", și SALA. '
          'CONSOLIDARE: dacă două ore consecutive sunt în AceEAȘI sală, menționează sala O SINGURĂ DATĂ.',
    };

    final currentTime = DateTime.now().toIso8601String();

    // User profile: injected into system prompt so Rigby addresses the user by name
    // and filters context (schedule, announcements) to their group.
    final pName = UserProfile.prenume;
    final pSpec = UserProfile.specializare;
    final pYear = UserProfile.anul;
    final pGroup = UserProfile.grupa;
    final profileLine = (pName.isNotEmpty || pSpec.isNotEmpty)
        ? 'Utilizatorul: ${pName.isNotEmpty ? pName : "student"}'
            '${pSpec.isNotEmpty ? ", specializarea $pSpec" : ""}'
            ', anul $pYear${pGroup.isNotEmpty ? ", grupa $pGroup" : ""}.'
        : '';

    return 'You are Rigby, an AI voice assistant for students at the Faculty of '
        'Mathematics and Informatics, Ovidius University of Constanța (FMI Ovidius). '
        'Your job is to help bachelor students with academic info: schedules, exam '
        'sessions, scholarships, fees, regulations, internships, Erasmus. '
        'When the user asks something academic, ALWAYS prefer the "Context relevant" '
        'block (if provided) over your general knowledge — that block is from the '
        'official faculty PDFs. If the context does not contain the answer, say so '
        'plainly instead of inventing details (no fake course names, professors, rooms). '
        'You communicate through SPEECH, so keep responses SHORT and conversational — '
        'no bullet points, no headers, no markdown formatting, no long paragraphs. '
        'One to three sentences maximum unless the user asks for a detailed explanation. '
        'You have access to native tools for timers, reminders, and schedule opening. Use them when requested. '
        'If the user wants to study, focus, or enter deep work, use the startDeepWork tool. '
        'If the user says "modul de prezentare" or asks you to present yourself to the committee, '
        'you MUST start by warmly greeting the license committee (e.g., "Bună ziua, onorată comisie!"), '
        'introduce yourself as Rigby (the AI assistant for FMI Ovidius students), and enthusiastically '
        'explain your core features in 3-4 sentences: setting focus timers, activating Deep Work mode (Do Not Disturb), '
        'reading schedules, and answering complex academic questions. Make it a professional yet friendly pitch. '
        'Current time: $currentTime. '
        '$profileLine '
        '$langRule '
        '$completenessRule'
        '$personalityRule '
        '$scheduleRule';
  }

  Future<String> sendMessage(
    String userMessage, {
    Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> args)? onFunctionCall,
    void Function(String textChunk)? onChunk,
    Uint8List? imageBytes,
  }) async {
    // Build user parts: text + optional image
    final userParts = <Map<String, dynamic>>[{'text': userMessage}];
    if (imageBytes != null) {
      userParts.add({
        'inline_data': {
          'mime_type': 'image/jpeg',
          'data': base64Encode(imageBytes),
        }
      });
    }
    _history.add({
      'role': 'user',
      'parts': userParts,
    });

    await ScheduleService().ensureLoaded();
    final scheduleData = _formatWeeklyScheduleData();
    debugPrint('[Gemini] schedule data: '
        '${scheduleData.isEmpty ? "EMPTY (profile mismatch?)" : "${scheduleData.length} chars"}');

    final ragContext = await RagService().buildContextForQuery(userMessage);

    final sysBuf = StringBuffer(_systemPrompt);
    if (ragContext.isNotEmpty) {
      sysBuf.write('\n\n');
      sysBuf.write(ragContext);
    }
    final systemText = sysBuf.toString();

    final tools = [
      {
        'function_declarations': [
          {
            'name': 'startTimer',
            'description': 'Porneste un cronometru sau timer de focus.',
            'parameters': {
              'type': 'OBJECT',
              'properties': {
                'minutes': {'type': 'INTEGER', 'description': 'Numarul de minute pentru timer.'}
              },
              'required': ['minutes']
            }
          },
          {
            'name': 'cancelTimer',
            'description': 'Anuleaza sau opreste cronometrul activ.'
          },
          {
            'name': 'startDeepWork',
            'description': 'Activează modul Deep Work (Fără deranj / Do Not Disturb) și pornește un cronometru de focus.',
            'parameters': {
              'type': 'OBJECT',
              'properties': {
                'minutes': {'type': 'INTEGER', 'description': 'Numărul de minute pentru modul deep work.'}
              },
              'required': ['minutes']
            }
          },
          {
            'name': 'scheduleReminder',
            'description': 'Programeaza un memento/reminder.',
            'parameters': {
              'type': 'OBJECT',
              'properties': {
                'time': {'type': 'STRING', 'description': 'Timpul in format ISO8601, ex: 2026-05-28T10:00:00'},
                'body': {'type': 'STRING', 'description': 'Descrierea activitatii.'}
              },
              'required': ['time', 'body']
            }
          },
          {
            'name': 'openScheduleSheet',
            'description': 'Deschide pe ecran interfata vizuala a orarului pentru o zi sau o saptamana.',
            'parameters': {
              'type': 'OBJECT',
              'properties': {
                'scope': {
                  'type': 'STRING',
                  'description': 'Ziua sau perioada. Valori posibile: today, tomorrow, luni, marti, miercuri, joi, vineri, week, week_para, week_impara'
                }
              },
              'required': ['scope']
            }
          },
          {
            'name': 'analyzePhoto',
            'description': 'Deschide camera telefonului pentru a fotografia un exercitiu, o problema, un text sau orice altceva pe care utilizatorul vrea sa il analizezi vizual. Apeleaza acest tool cand utilizatorul spune lucruri precum: uita-te la asta, analizeaza asta, fa o poza, ce scrie aici, rezolva exercitiul, etc.'
          }
        ]
      }
    ];

    while (true) {
      final List<Map<String, dynamic>> contents = [];
      if (scheduleData.isNotEmpty) {
        contents.add({
          'role': 'user',
          'parts': [{'text': 'Care este orarul meu complet săptămânal?'}],
        });
        contents.add({
          'role': 'model',
          'parts': [{'text': scheduleData}],
        });
      }
      contents.addAll(_history);

      final body = jsonEncode({
        'system_instruction': {
          'parts': [{'text': systemText}],
        },
        'tools': tools,
        'contents': contents,
        'generationConfig': {
          'temperature': 0.8,
          'maxOutputTokens': 1024,
        },
      });

      final client = http.Client();
      try {
        // Automatic retry with backoff for rate limits / high demand
        http.StreamedResponse response;
        int retries = 0;
        const maxRetries = 3;
        final requestUri = Uri.parse('$_baseUrl?alt=sse&key=$_apiKey');
        while (true) {
          final request = http.Request('POST', requestUri);
          request.headers['Content-Type'] = 'application/json';
          request.body = body;

          response = await client.send(request).timeout(const Duration(seconds: 25));

          // 429 = rate limit, 503 = overloaded; retry with linear backoff
          if ((response.statusCode == 429 || response.statusCode == 503) && retries < maxRetries) {
            retries++;
            debugPrint('[Gemini] High demand (${response.statusCode}), retry $retries/$maxRetries...');
            await Future.delayed(Duration(seconds: 2 * retries)); // 2s, 4s, 6s
            continue;
          }
          break;
        }

        if (response.statusCode != 200) {
          final errBytes = await response.stream.toBytes();
          final errStr = utf8.decode(errBytes);
          try {
            final error = jsonDecode(errStr);
            throw Exception('Eroare API: ${error['error']?['message'] ?? response.statusCode}');
          } catch (_) {
            throw Exception('Eroare API: $errStr');
          }
        }

        final stream = response.stream.transform(utf8.decoder).transform(const LineSplitter());

        bool hasFunctionCall = false;
        List<Map<String, dynamic>> functionResponses = [];
        String textResponse = '';
        List<Map<String, dynamic>> allParts = [];

        await for (var line in stream) {
          if (line.startsWith('data: ')) {
            final dataStr = line.substring(6).trim();
            if (dataStr == '[DONE]') continue;
            if (dataStr.isEmpty) continue;

            try {
              final data = jsonDecode(dataStr);
              final candidates = data['candidates'] as List?;
              if (candidates != null && candidates.isNotEmpty) {
                final parts = candidates[0]['content']?['parts'] as List?;
                if (parts != null) {
                  for (var part in parts) {
                    allParts.add(part);
                    if (part['text'] != null) {
                      final chunk = part['text'] as String;
                      textResponse += chunk;
                      if (onChunk != null) {
                        onChunk(chunk);
                      }
                    }
                    if (part['functionCall'] != null) {
                      hasFunctionCall = true;
                      final call = part['functionCall'];
                      final name = call['name'] as String;
                      final args = call['args'] as Map<String, dynamic>? ?? {};

                      if (onFunctionCall != null) {
                        try {
                          final result = await onFunctionCall(name, args);
                          functionResponses.add({
                            'functionResponse': {
                              'name': name,
                              'response': {'name': name, 'content': result}
                            }
                          });
                        } catch (e) {
                          functionResponses.add({
                            'functionResponse': {
                              'name': name,
                              'response': {'name': name, 'error': e.toString()}
                            }
                          });
                        }
                      } else {
                        functionResponses.add({
                          'functionResponse': {
                            'name': name,
                            'response': {'name': name, 'error': 'No handler provided.'}
                          }
                        });
                      }
                    }
                  }
                }
              }
            } catch (e) {
              debugPrint('[Gemini] Stream parse error: $e. Line: $dataStr');
            }
          }
        }

        if (textResponse.isEmpty && !hasFunctionCall) {
          return 'Nu am putut genera un răspuns.';
        }

        _history.add({
          'role': 'model',
          'parts': hasFunctionCall ? allParts : [{'text': textResponse}],
        });

        if (hasFunctionCall) {
          _history.add({
            'role': 'user',
            'parts': functionResponses,
          });
          continue; // Repeat the loop with the function responses
        }

        while (_history.length > _maxHistoryEntries) {
          _history.removeRange(0, 2);
        }

        return textResponse;
      } catch (e) {
        if (_history.isNotEmpty && (_history.last['role'] as String?) == 'user') {
          _history.removeLast();
        }
        rethrow;
      } finally {
        client.close();
      }
    }
  }

  void resetChat() {
    _history.clear();
  }

  /// Normalizes classroom names for clear TTS pronunciation (e.g., "AulaB" -> "Aula B").
  String _normalizeRoomForSpeech(String room) {
    return room
        .replaceAllMapped(RegExp(r'\bAula([A-Z])'), (m) => 'Aula ${m.group(1)}')
        .replaceAllMapped(RegExp(r'\bSala(\d)'), (m) => 'Sala ${m.group(1)}');
  }

  /// Formats the user's weekly schedule as a pre-seeded model turn to anchor grounded schedule responses.
  String _formatWeeklyScheduleData() {
    final s = ScheduleService().currentUserSchedule();
    if (s == null) return '';
    final buf = StringBuffer()
      ..writeln('Iată orarul tău complet săptămânal pe care îl voi folosi în continuare:')
      ..writeln('${s.specialization}, anul ${s.year}, grupa ${s.group}'
          '${s.semester != null ? ", sem. ${s.semester}" : ""}'
          '${s.academicYear != null ? ", anul univ. ${s.academicYear}" : ""}.');
    for (final d in s.days) {
      if (d.slots.isEmpty) {
        buf.writeln('${d.day}: liber.');
        continue;
      }
      buf.writeln('${d.day}:');
      for (final slot in d.slots) {
        final type = (slot.type ?? '').toLowerCase();
        final parts = <String>[];
        if (type.isNotEmpty) parts.add(type);
        if (slot.professor != null && slot.professor!.isNotEmpty) {
          parts.add(slot.professor!);
        }
        if (slot.room != null && slot.room!.isNotEmpty) {
          parts.add('sala ${_normalizeRoomForSpeech(slot.room!)}');
        }
        if (slot.parity != null) {
          parts.add('săpt. ${slot.parity!.toLowerCase()}');
        }
        buf.writeln('  • ${slot.start}-${slot.end} ${slot.course}'
            '${parts.isEmpty ? "" : " (${parts.join(", ")})"}');
      }
    }
    return buf.toString();
  }
}
