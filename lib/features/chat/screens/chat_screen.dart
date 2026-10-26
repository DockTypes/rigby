import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../../core/models/app_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/services/rigby_foreground_service.dart';
import '../../../core/services/audio_beep_suppressor.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/services/quick_commands.dart';
import '../../../core/services/schedule_service.dart';
import '../../../core/services/tool_executor.dart';
import '../../../core/services/response_parser.dart';
import '../widgets/rigby_schedule_sheet.dart';
import '../widgets/rigby_capabilities_sheet.dart';
import '../../../core/services/tts_service.dart';
import '../../island/rigby_island.dart';
import '../widgets/voice_visualizer.dart';
import '../widgets/rigby_mascot.dart';
import '../widgets/rigby_mic_button.dart';
import '../widgets/rigby_chat_sheet.dart';
import '../../settings/widgets/rigby_settings_sheet.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

// Logical dialogue phases. Single source of truth for _isListening and _isProcessing.
enum _SttPhase { idle, wakeWord, command, processing, speaking }

class _ChatScreenState extends State<ChatScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  VisualizerState _vizState = VisualizerState.idle;
  late AnimationController _headerFadeCtrl;

  final GeminiService _gemini = GeminiService();
  final TtsService _tts = TtsService();
  final SpeechToText _speech = SpeechToText();

  bool _speechAvailable = false;
  _SttPhase _phase = _SttPhase.idle;

  // Prevents reopening the schedule sheet if locally triggered prior to Gemini's [SCHEDULE] tag.
  bool _scheduleSheetOpened = false;

  // Generation counter incremented on each listen()/cancel() to invalidate delayed native callbacks.
  int _sttGen = 0;
  // Guard between cancel() and listen() in _listenForWakeWord to prevent recursive restarts.
  bool _wakeWordStarting = false;

  // Matches "rigby" as a whole token rather than a substring in background noise.
  static final RegExp _wakeWordRegex =
      RegExp(r'\b(rigby|rigbi|rigbii|rugby)\b');

  bool get _isListening => _phase == _SttPhase.command;
  bool get _isProcessing => _phase == _SttPhase.processing;

  Timer? _sttWatchdog;

  String _transcribedText = '';
  String _responseText = '';

  final List<ChatMessage> _messages = [];
  final ValueNotifier<double> _amplitude = ValueNotifier(0.0);
  final ValueNotifier<double> _formant = ValueNotifier(0.5);
  void Function()? _activeSheetStateSetter;

  void _setPhase(_SttPhase next) {
    if (_phase == next) return;
    debugPrint('[Rigby] phase: ${_phase.name} → ${next.name}');
    _phase = next;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _headerFadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    WidgetsBinding.instance.addObserver(this);
    // Make sure any leftover service from a previous session is stopped
    RigbyForegroundService.stop();

    _initTts();
    _initSpeech();
    _sendInitialGreeting();
    _requestOverlayPermission();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mq = MediaQuery.of(context);
      RigbyIslandController.instance.devicePixelRatio = mq.devicePixelRatio;
      RigbyIslandController.instance.statusBarHeightDp = mq.padding.top;
    });
  }

  Future<void> _requestOverlayPermission() async {
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      await FlutterOverlayWindow.requestPermission();
    }
  }

  // Flutter STT is NOT stopped when going to background — it keeps running inside
  // the FlutterEngine (which has the Activity context + window token) and can
  // still deliver callbacks. The native service only shows the foreground
  // notification so Android doesn't kill the process.

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[Rigby] lifecycle → $state');

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (!RigbyIslandController.instance.isAppInBackground) {
        // Start foreground service before Android restricts background execution.
        RigbyForegroundService.start();
        RigbyIslandController.instance.isAppInBackground = true;
        // Pre-create the overlay window once in hidden state for instant wake word activation.
        RigbyIslandController.instance.openOverlay();

        // Invalidate prior STT callbacks and restart wake word on background transition.
        Future.delayed(const Duration(milliseconds: 800), () async {
          if (!mounted) return;
          if (!RigbyIslandController.instance.isAppInBackground) return;
          if (_phase != _SttPhase.wakeWord && _phase != _SttPhase.idle) {
            debugPrint('[STT] Skip background restart — phase=${_phase.name}');
            return;
          }
          _sttGen++;
          try { await _speech.cancel(); } catch (_) {}
          _setPhase(_SttPhase.idle);
          if (mounted && RigbyIslandController.instance.isAppInBackground) {
            _startWakeWordMode();
          }
        });

        // Watchdog timer restarts wake word listening if STT silently stops in background.
        _sttWatchdog?.cancel();
        _sttWatchdog = Timer.periodic(const Duration(seconds: 8), (_) {
          if (!mounted) return;
          if (_phase != _SttPhase.wakeWord) return;
          if (_speech.isListening) return;
          debugPrint('[STT Watchdog] ⚠️ STT oprit silențios — repornesc wake word');
          _sttGen++;
          _setPhase(_SttPhase.idle);
          _startWakeWordMode();
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      RigbyIslandController.instance.isAppInBackground = false;
      RigbyForegroundService.stop();
      RigbyIslandController.instance.forceCloseOverlay();

      _sttWatchdog?.cancel();
      _sttWatchdog = null;

      _checkOverlayPermissionAndNotify();
    }
  }

  Future<void> _checkOverlayPermissionAndNotify() async {
    if (!await FlutterOverlayWindow.isPermissionGranted() && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Activează "Afișare peste alte aplicații" pentru Rigby în Setări '
            'ca island-ul să apară când ești în altă aplicație.',
          ),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Setări',
            onPressed: FlutterOverlayWindow.requestPermission,
          ),
        ),
      );
    }
  }


  Future<void> _initTts() async {
    await _tts.initialize();

    _tts.onSpeakPrepare = () async {
      if (mounted) setState(() => _vizState = VisualizerState.idle);
      await Future.delayed(const Duration(milliseconds: 400));
    };

    _tts.onSpeakStart = () {
      if (mounted) setState(() => _vizState = VisualizerState.speaking);
      _setPhase(_SttPhase.speaking);
      RigbyIslandController.instance.showSpeaking(_responseText);
    };

    _tts.onSpeakDone = () {
      if (mounted) setState(() => _vizState = VisualizerState.idle);
      _setPhase(_SttPhase.idle);
      RigbyIslandController.instance.hide();
      Future.delayed(const Duration(milliseconds: 350), _startWakeWordMode);
    };

    _tts.onAudioData = (amp, formant) {
      _amplitude.value = amp;
      _formant.value = formant;
      RigbyIslandController.instance.updateAmplitude(amp);
    };
  }


  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (e) {
        debugPrint('[STT] Error: $e (gen=$_sttGen, phase=${_phase.name})');
        if (!mounted) return;

        final errStr = e.toString();

        // error_no_match is a recognition timeout rather than an error; handled by onStatus(done).
        if (errStr.contains('error_no_match')) return;

        // Ignore late STT errors arriving after transitioning to processing or speaking.
        final wasListening =
            _phase == _SttPhase.wakeWord || _phase == _SttPhase.command;

        final needsReinit = errStr.contains('permanent: true') &&
            (errStr.contains('error_server_disconnected') ||
                errStr.contains('error_audio'));

        if (!wasListening && !needsReinit) {
          return;
        }

        _sttGen++;
        if (_vizState == VisualizerState.listening) {
          setState(() => _vizState = VisualizerState.idle);
        }
        _setPhase(_SttPhase.idle);
        if (!RigbyIslandController.instance.isAppInBackground) {
          RigbyIslandController.instance.hide();
        }

        if (needsReinit) {
          Future.delayed(const Duration(milliseconds: 800), () async {
            if (!mounted) return;
            debugPrint('[STT] Fatal — reinit engine ($errStr)');
            _speechAvailable = await _speech.initialize(
              onError: (e2) => debugPrint('[STT] Re-init error: $e2'),
              onStatus: (s) => debugPrint('[STT] Re-init status: $s'),
            );
            if (mounted && _speechAvailable) _startWakeWordMode();
          });
        } else {
          Future.delayed(const Duration(milliseconds: 400), _startWakeWordMode);
        }
      },
      onStatus: (status) {
        debugPrint('[STT] status=$status gen=$_sttGen phase=${_phase.name}');
        if (status != SpeechToText.doneStatus || !mounted) return;
        // Handle session completion based on active dialogue phase
        if (_phase == _SttPhase.wakeWord) {
          if (_wakeWordStarting) return;
          Future.delayed(const Duration(milliseconds: 600), _listenForWakeWord);
        } else if (_phase == _SttPhase.command) {
          // Command timed out without recognized speech; return to wake word
          if (!RigbyIslandController.instance.isAppInBackground &&
              _vizState == VisualizerState.listening) {
            setState(() => _vizState = VisualizerState.idle);
          }
          _setPhase(_SttPhase.idle);
          RigbyIslandController.instance.hide();
          Future.delayed(const Duration(milliseconds: 350), _startWakeWordMode);
        }
      },
    );
    if (mounted) setState(() {});
  }




  Future<void> _sendInitialGreeting() async {
    setState(() => _vizState = VisualizerState.thinking);

    final greetingPrompt = switch (AppSettings.sttLocale) {
      'en_US' => 'Say a short, natural greeting. One sentence only. No paragraphs, no lists.',
      'fr_FR' => 'Dis une courte salutation naturelle. Une seule phrase. Pas de paragraphes.',
      _       => 'Spune un salut scurt și natural. O singură propoziție, fără paragrafe sau liste.',
    };

    try {
      final response = await _gemini.sendMessage(
        greetingPrompt,
        onChunk: (chunk) {
          if (mounted) {
            setState(() {
              _responseText += chunk;
              final display = ResponseParser.parse(_responseText).cleanText;
              if (_messages.isNotEmpty && _messages.last.role == 'Rigby') {
                _messages[_messages.length - 1] = ChatMessage(role: 'Rigby', text: display);
              } else {
                _messages.add(ChatMessage(role: 'Rigby', text: display));
              }
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _responseText = ResponseParser.parse(response).cleanText;
          if (_messages.isNotEmpty && _messages.last.role == 'Rigby') {
             _messages[_messages.length - 1] = ChatMessage(role: 'Rigby', text: _responseText);
          } else {
             _messages.add(ChatMessage(role: 'Rigby', text: _responseText));
          }
        });
        _tts.speak(_responseText);
        // Wake word mode starts via onSpeakDone after greeting finishes
      }
    } catch (e) {
      debugPrint('[Rigby] Initial greeting failed: $e');
      if (mounted) {
        _handleApiError(e);
      }
    }
  }

  void _handleApiError([Object? error]) {
    final defaultMsg = AppSettings.sttLocale == 'en_US'
        ? "I don't have an internet connection right now."
        : "Eroare de conexiune sau API.";
        
    final msg = error != null ? "$defaultMsg Detalii: $error" : defaultMsg;

    setState(() => _responseText = msg);
    _setPhase(_SttPhase.idle);
    
    // We only speak the default message to not overwhelm TTS
    _tts.speak(defaultMsg);
  }


  void _startWakeWordMode() {
    if (!_speechAvailable) return;
    if (_phase != _SttPhase.idle) return;
    _setPhase(_SttPhase.wakeWord);
    _listenForWakeWord();
  }

  Future<void> _listenForWakeWord() async {
    if (!mounted || !_speechAvailable) return;
    if (_phase != _SttPhase.wakeWord) return;
    if (_wakeWordStarting) return;

    _wakeWordStarting = true;
    try {
      final myGen = ++_sttGen;
      // Suppress Google STT prompt beeps by temporarily muting audio streams
      await AudioBeepSuppressor.mute();
      try { await _speech.cancel(); } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted || myGen != _sttGen || _phase != _SttPhase.wakeWord) {
        AudioBeepSuppressor.unmute();
        return;
      }

      await _speech.listen(
        onResult: (result) {
          if (myGen != _sttGen || _phase != _SttPhase.wakeWord) return;
          final words = result.recognizedWords.toLowerCase();
          // Whole-word match prevents ambient noise substring triggers
          if (_wakeWordRegex.hasMatch(words)) {
            _onWakeWordDetected();
          }
        },
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 10),
        localeId: AppSettings.sttLocale,
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          cancelOnError: true,
          partialResults: true,
          // Cloud recognizer provides higher accuracy for Romanian wake words
          onDevice: false,
        ),
      );
      // Restore audio stream volumes after the prompt beep window
      Future.delayed(const Duration(milliseconds: 400), AudioBeepSuppressor.unmute);
      debugPrint('[STT] wake word listen started gen=$myGen bg=${RigbyIslandController.instance.isAppInBackground}');
    } finally {
      _wakeWordStarting = false;
    }
  }

  void _onWakeWordDetected() {
    if (!mounted) return;
    if (_phase != _SttPhase.wakeWord) return;
    debugPrint('[Rigby] 🎤 Wake word! bg=${RigbyIslandController.instance.isAppInBackground}');
    HapticFeedback.heavyImpact();

    if (RigbyIslandController.instance.isAppInBackground) {
      RigbyIslandController.instance.showListening();
      _startBackgroundCommandListening();
    } else {
      _startListening();
    }
  }

  // Fast local schedule intent detection to present the sheet immediately without waiting for Gemini.
  ScheduleScope? _detectScheduleIntent(String text) {
    final t = text
        .toLowerCase()
        .replaceAll('ă', 'a')
        .replaceAll('â', 'a')
        .replaceAll('î', 'i')
        .replaceAll('ș', 's')
        .replaceAll('ț', 't');

    final isScheduleQuery = t.contains('orar') ||
        t.contains('curs') ||
        t.contains('ora') ||
        t.contains('program') ||
        RegExp(r'\b(ce am|ce ai|ce avem)\b').hasMatch(t);
    if (!isScheduleQuery) return null;

    final hasSaptamana = t.contains('saptaman');
    final hasPara = RegExp(r'\bpar(a|ă)\b').hasMatch(t) || t.contains('para');
    final hasImpara =
        RegExp(r'\bimpar(a|ă)\b').hasMatch(t) || t.contains('impara');

    if (hasSaptamana && hasImpara) return ScheduleScope.weekImpara;
    if (hasSaptamana && hasPara) return ScheduleScope.weekPara;
    if (hasSaptamana) return ScheduleScope.week;
    if (hasImpara) return ScheduleScope.weekImpara;
    if (hasPara) return ScheduleScope.weekPara;

    if (RegExp(r'\bmaine\b').hasMatch(t)) return ScheduleScope.tomorrow;
    if (RegExp(r'\b(astazi|azi)\b').hasMatch(t)) return ScheduleScope.today;

    if (RegExp(r'\bluni\b').hasMatch(t)) return ScheduleScope.luni;
    if (RegExp(r'\bmarti\b').hasMatch(t)) return ScheduleScope.marti;
    if (RegExp(r'\bmiercuri\b').hasMatch(t)) return ScheduleScope.miercuri;
    if (RegExp(r'\bjoi\b').hasMatch(t)) return ScheduleScope.joi;
    if (RegExp(r'\bvineri\b').hasMatch(t)) return ScheduleScope.vineri;

    return null;
  }

  Future<void> _openScheduleSheet(ScheduleScope scope) async {
    await ScheduleService().ensureLoaded();
    if (!mounted) return;
    final sched = ScheduleService().currentUserSchedule();
    if (sched == null) return;
    showRigbyScheduleSheet(context, scope: scope, schedule: sched);
  }

  String _parseActions(String text) {
    final parsed = ResponseParser.parse(text);

    ResponseParser.executeActions(
      parsed,
      context: context,
      scheduleSheetOpened: _scheduleSheetOpened,
      onScheduleSheetOpened: () => _scheduleSheetOpened = true,
    );

    // Present capabilities sheet here to avoid circular dependency with ResponseParser.
    if (parsed.showCapabilities &&
        mounted &&
        !RigbyIslandController.instance.isAppInBackground) {
      Future.microtask(() {
        if (mounted) showRigbyCapabilitiesSheet(context);
      });
    }

    return parsed.cleanText;
  }


  Future<void> _startBackgroundCommandListening() async {
    final myGen = ++_sttGen;
    
    await AudioBeepSuppressor.mute();
    
    try { await _speech.cancel(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted || myGen != _sttGen) {
      AudioBeepSuppressor.unmute();
      return;
    }

    _setPhase(_SttPhase.command);

    await _speech.listen(
      onResult: (result) {
        if (myGen != _sttGen) return;
        if (!result.finalResult) return;
        if (result.recognizedWords.isNotEmpty) {
          _processBackgroundCommand(result.recognizedWords);
        } else {
          _setPhase(_SttPhase.idle);
          RigbyIslandController.instance.hide();
          _startWakeWordMode();
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 4),
      localeId: AppSettings.sttLocale,
    );
    
    Future.delayed(const Duration(milliseconds: 400), AudioBeepSuppressor.unmute);
  }

  void _processBackgroundCommand(String command) async {
    if (!mounted) return;
    // Invalidate in-flight STT callbacks.
    _sttGen++;
    try { await _speech.stop(); } catch (_) {}

    _setPhase(_SttPhase.processing);
    setState(() {
      _transcribedText = command;
      _messages.add(ChatMessage(role: 'user', text: command));
    });

    // Fast local command short-circuit
    final quick = QuickCommands.tryHandle(command);
    if (quick != null) {
      final cleanResponse = _parseActions(quick);
      setState(() {
        _responseText = cleanResponse;
        _messages.add(ChatMessage(role: 'Rigby', text: cleanResponse));
      });
      _tts.speak(cleanResponse);
      return;
    }

    RigbyIslandController.instance.showSpeaking('Mă gândesc...');

    try {
      final response = await _gemini.sendMessage(
        command,
        onFunctionCall: (name, args) async {
          debugPrint('[Agentic BG] Gemini called tool: $name with $args');
          return ToolExecutor.execute(name, args);
        },
        onChunk: (chunk) {
          if (mounted) {
            setState(() {
              _responseText += chunk;
              final display = ResponseParser.parse(_responseText).cleanText;
              if (_messages.isNotEmpty && _messages.last.role == 'Rigby') {
                _messages[_messages.length - 1] = ChatMessage(role: 'Rigby', text: display);
              } else {
                _messages.add(ChatMessage(role: 'Rigby', text: display));
              }
            });
          }
        },
      );
      if (!mounted) return;
      final cleanResponse = _parseActions(response);

      setState(() {
        _responseText = cleanResponse;
        if (_messages.isNotEmpty && _messages.last.role == 'Rigby') {
           _messages[_messages.length - 1] = ChatMessage(role: 'Rigby', text: cleanResponse);
        } else {
           _messages.add(ChatMessage(role: 'Rigby', text: cleanResponse));
        }
      });

      _tts.speak(cleanResponse);
    } catch (e) {
      if (!mounted) return;
      _handleApiError(e);
    }
  }


  Future<void> _stopSpeaking() async {
    if (_vizState != VisualizerState.speaking) return;
    HapticFeedback.lightImpact();
    await _tts.stop();
    if (mounted) setState(() => _vizState = VisualizerState.idle);
    _setPhase(_SttPhase.idle);
    RigbyIslandController.instance.hide();
    Future.delayed(const Duration(milliseconds: 350), _startWakeWordMode);
  }

  Future<void> _toggleListening() async {
    if (_phase == _SttPhase.processing || _vizState == VisualizerState.speaking) return;
    _isListening ? await _stopListening() : await _startListening();
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) return;
    await _tts.stop();

    final myGen = ++_sttGen;
    
    // Suppress prompt beeps for manual mic activation.
    await AudioBeepSuppressor.mute();
    
    try { await _speech.cancel(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted || myGen != _sttGen) {
      AudioBeepSuppressor.unmute();
      return;
    }

    _setPhase(_SttPhase.command);
    setState(() {
      _transcribedText = '';
      _vizState = VisualizerState.listening;
    });

    RigbyIslandController.instance.showListening();

    await _speech.listen(
      onResult: (result) {
        if (myGen != _sttGen) return;
        setState(() => _transcribedText = result.recognizedWords);
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          _processUserInput(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 4),
      localeId: AppSettings.sttLocale,
      onSoundLevelChange: (level) {
        _amplitude.value = ((level + 2) / 10).clamp(0.0, 1.0);
      },
    );
    
    // Restore stream volumes after prompt beep
    Future.delayed(const Duration(milliseconds: 400), AudioBeepSuppressor.unmute);
  }

  Future<void> _stopListening() async {
    _sttGen++;
    try { await _speech.stop(); } catch (_) {}
    _setPhase(_SttPhase.idle);
    if (_vizState == VisualizerState.listening) {
      setState(() => _vizState = VisualizerState.idle);
    }
    RigbyIslandController.instance.hide();
  }

  Future<void> _processUserInput(String text) async {
    _sttGen++;
    try { await _speech.stop(); } catch (_) {}
    if (_vizState == VisualizerState.listening) {
      setState(() => _vizState = VisualizerState.idle);
    }

    if (text.isEmpty) {
      _setPhase(_SttPhase.idle);
      RigbyIslandController.instance.hide();
      _startWakeWordMode();
      return;
    }

    _setPhase(_SttPhase.processing);
    setState(() {
      _responseText = '';
      _vizState = VisualizerState.thinking;
      _messages.add(ChatMessage(role: 'user', text: text));
    });

    _scheduleSheetOpened = false;

    // Fast local command execution.
    final quick = QuickCommands.tryHandle(text);
    if (quick != null) {
      final cleanResponse = _parseActions(quick);
      if (mounted) {
        setState(() {
          _responseText = cleanResponse;
          _messages.add(ChatMessage(role: 'Rigby', text: cleanResponse));
        });
        _tts.speak(cleanResponse);
      }
      return;
    }

    // Eagerly present schedule sheet in parallel with Gemini request.
    final localScope = _detectScheduleIntent(text);
    if (localScope != null &&
        !RigbyIslandController.instance.isAppInBackground) {
      _scheduleSheetOpened = true;
      _openScheduleSheet(localScope);
    }

    try {
      final response = await _gemini.sendMessage(
        text,
        onFunctionCall: (name, args) async {
          debugPrint('[Agentic] Gemini called tool: $name with $args');
          if (name == 'analyzePhoto') {
            // Schedule camera open after AI responds
            Future.microtask(() => _pickAndAnalyzeImage());
            return {'result': 'Camera deschisă. Utilizatorul va trimite o fotografie.'};
          }
          return ToolExecutor.execute(
            name,
            args,
            context: mounted ? context : null,
            scheduleSheetOpened: _scheduleSheetOpened,
            onScheduleSheetOpened: () => _scheduleSheetOpened = true,
          );
        },
        onChunk: (chunk) {
          if (mounted) {
            setState(() {
              _responseText += chunk;
              final display = ResponseParser.parse(_responseText).cleanText;
              if (_messages.isNotEmpty && _messages.last.role == 'Rigby') {
                _messages[_messages.length - 1] = ChatMessage(role: 'Rigby', text: display);
              } else {
                _messages.add(ChatMessage(role: 'Rigby', text: display));
              }
            });
          }
        },
      );
      final cleanResponse = _parseActions(response);

      if (mounted) {
        setState(() {
          _responseText = cleanResponse;
          if (_messages.isNotEmpty && _messages.last.role == 'Rigby') {
             _messages[_messages.length - 1] = ChatMessage(role: 'Rigby', text: cleanResponse);
          } else {
             _messages.add(ChatMessage(role: 'Rigby', text: cleanResponse));
          }
        });
        _tts.speak(cleanResponse);
      }
    } catch (e) {
      debugPrint('[Rigby] processUserInput failed: $e');
      if (mounted) {
        _handleApiError(e);
      }
    }
  }


  Future<void> _sendTextMessage(String text) async {
    if (text.isEmpty || _phase == _SttPhase.processing) return;

    _sttGen++;
    try { await _speech.cancel(); } catch (_) {}

    _setPhase(_SttPhase.processing);
    setState(() {
      _responseText = '';
      _vizState = VisualizerState.thinking;
      _messages.add(ChatMessage(role: 'user', text: text));
    });
    _activeSheetStateSetter?.call();

    try {
      final response = await _gemini.sendMessage(
        text,
        onFunctionCall: (name, args) async {
          debugPrint('[Agentic Text] Gemini called tool: $name with $args');
          if (name == 'analyzePhoto') {
            Future.microtask(() => _pickAndAnalyzeImage());
            return {'result': 'Camera deschisă. Utilizatorul va trimite o fotografie.'};
          }
          return ToolExecutor.execute(
            name,
            args,
            context: mounted ? context : null,
            scheduleSheetOpened: _scheduleSheetOpened,
            onScheduleSheetOpened: () => _scheduleSheetOpened = true,
          );
        },
        onChunk: (chunk) {
          if (mounted) {
            setState(() {
              _responseText += chunk;
              final display = ResponseParser.parse(_responseText).cleanText;
              if (_messages.isNotEmpty && _messages.last.role == 'Rigby') {
                _messages[_messages.length - 1] = ChatMessage(role: 'Rigby', text: display);
              } else {
                _messages.add(ChatMessage(role: 'Rigby', text: display));
              }
            });
            _activeSheetStateSetter?.call();
          }
        },
      );
      final cleanResponse = _parseActions(response);

      if (mounted) {
        setState(() {
          _responseText = cleanResponse;
          _vizState = VisualizerState.idle;
          if (_messages.isNotEmpty && _messages.last.role == 'Rigby') {
             _messages[_messages.length - 1] = ChatMessage(role: 'Rigby', text: cleanResponse);
          } else {
             _messages.add(ChatMessage(role: 'Rigby', text: cleanResponse));
          }
        });
        _activeSheetStateSetter?.call();
        _setPhase(_SttPhase.idle);
        Future.delayed(const Duration(milliseconds: 400), _startWakeWordMode);
      }
    } catch (e) {
      debugPrint('[Rigby] sendTextMessage failed: $e');
      if (mounted) {
        _handleApiError(e);
      }
    }
  }


  Future<void> _pickAndAnalyzeImage({ImageSource source = ImageSource.camera}) async {
    if (_phase == _SttPhase.processing) return;

    _sttGen++;
    try { await _speech.cancel(); } catch (_) {}
    await _tts.stop();

    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (photo == null || !mounted) {
      _setPhase(_SttPhase.idle);
      _startWakeWordMode();
      return;
    }

    final imageBytes = await photo.readAsBytes();

    _setPhase(_SttPhase.processing);
    setState(() {
      _responseText = '';
      _vizState = VisualizerState.thinking;
      _messages.add(ChatMessage(
        role: 'user',
        text: '📸 Analizează această imagine',
        imageBytes: imageBytes,
      ));
    });

    final prompt = AppSettings.sttLocale == 'en_US'
        ? 'The user sent you a photo. Analyze the image carefully. '
          'If it contains a math problem, equation, or exercise, solve it step by step. '
          'If it contains text, read and summarize it. '
          'If it contains code, explain what it does. '
          'Otherwise, describe what you see. Be concise and conversational.'
        : 'Utilizatorul ți-a trimis o fotografie. Analizează imaginea cu atenție. '
          'Dacă conține o problemă de matematică, ecuație sau exercițiu, rezolv-o pas cu pas. '
          'Dacă conține text, citește-l și rezumă-l. '
          'Dacă conține cod, explică ce face. '
          'Altfel, descrie ce vezi. Fii concis și conversațional.';

    _scheduleSheetOpened = false;

    try {
      final response = await _gemini.sendMessage(
        prompt,
        imageBytes: imageBytes,
        onFunctionCall: (name, args) async {
          debugPrint('[Agentic Vision] Gemini called tool: $name with $args');
          return ToolExecutor.execute(
            name,
            args,
            context: mounted ? context : null,
            scheduleSheetOpened: _scheduleSheetOpened,
            onScheduleSheetOpened: () => _scheduleSheetOpened = true,
          );
        },
        onChunk: (chunk) {
          if (mounted) {
            setState(() {
              _responseText += chunk;
              final display = ResponseParser.parse(_responseText).cleanText;
              if (_messages.isNotEmpty && _messages.last.role == 'Rigby') {
                _messages[_messages.length - 1] = ChatMessage(role: 'Rigby', text: display);
              } else {
                _messages.add(ChatMessage(role: 'Rigby', text: display));
              }
            });
            _activeSheetStateSetter?.call();
          }
        },
      );
      final cleanResponse = _parseActions(response);

      if (mounted) {
        setState(() {
          _responseText = cleanResponse;
          if (_messages.isNotEmpty && _messages.last.role == 'Rigby') {
            _messages[_messages.length - 1] = ChatMessage(role: 'Rigby', text: cleanResponse);
          } else {
            _messages.add(ChatMessage(role: 'Rigby', text: cleanResponse));
          }
        });
        _activeSheetStateSetter?.call();
        _tts.speak(cleanResponse);
      }
    } catch (e) {
      debugPrint('[Rigby] Vision analysis failed: $e');
      if (mounted) {
        _handleApiError(e);
      }
    }
  }


  void _openChatSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          _activeSheetStateSetter = () {
            if (ctx.mounted) setSheetState(() {});
          };
          return RigbyChatSheet(
            messages: _messages,
            mascotState: _vizState,
            amplitude: _amplitude,
            onSendMessage: (text) async {
              await _sendTextMessage(text);
              if (ctx.mounted) setSheetState(() {});
            },
            onPickImage: () => _pickAndAnalyzeImage(),
          );
        },
      ),
    ).whenComplete(() {
      _activeSheetStateSetter = null;
    });
  }

  void _openSettings() {
    final localeBefore = AppSettings.sttLocale;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => RigbySettingsSheet(
        onSettingsChanged: () {
          setState(() {});
          // If the STT locale changed, restart the active wake word session
          // so the new locale takes effect immediately.
          if (AppSettings.sttLocale != localeBefore && _phase == _SttPhase.wakeWord) {
            _sttGen++;
            _setPhase(_SttPhase.idle);
            _speech.cancel();
            Future.delayed(
              const Duration(milliseconds: 400),
              _startWakeWordMode,
            );
          }
        },
      ),
    );
  }


  void _resetConversation() {
    _gemini.resetChat();
    setState(() {
      _messages.clear();
      _responseText = '';
      _transcribedText = '';
    });
    _sendInitialGreeting();
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activeSheetStateSetter = null;
    _tts.onAudioData = null;
    _tts.onSpeakPrepare = null;
    _tts.onSpeakStart = null;
    _tts.onSpeakDone = null;
    _sttGen++;
    _phase = _SttPhase.idle;
    _sttWatchdog?.cancel();
    _headerFadeCtrl.dispose();
    _amplitude.dispose();
    _formant.dispose();
    _speech.stop();
    unawaited(_tts.stop());
    unawaited(RigbyForegroundService.stop());
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.neonWhite : const Color(0xFF0D0D0D);
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.3),
                radius: 0.75,
                colors: [
                  fg.withValues(
                    alpha: _vizState == VisualizerState.listening
                        ? 0.07
                        : _vizState == VisualizerState.speaking
                            ? 0.04
                            : 0.02,
                  ),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 36),
                      FadeTransition(
                        opacity: CurvedAnimation(
                          parent: _headerFadeCtrl,
                          curve: Curves.easeOutCubic,
                        ),
                        child: _FloatingHeader(isDark: isDark, fg: fg),
                      ),
                      GestureDetector(
                        onTap: _openSettings,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: fg.withValues(alpha: 0.05),
                            border: Border.all(
                              color: fg.withValues(alpha: 0.12),
                              width: 0.5,
                            ),
                          ),
                          child: Icon(
                            Icons.settings_outlined,
                            size: 16,
                            color: fg.withValues(alpha: 0.40),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                RigbyMascot(
                  state: _vizState,
                  amplitude: _amplitude,
                  formantRatio: _formant,
                  size: size.width * 0.60,
                  onTap: _stopSpeaking,
                ),

                const SizedBox(height: 28),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.08),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: _responseText.isEmpty
                      ? const SizedBox(key: ValueKey('empty'), height: 56)
                      : Padding(
                          key: ValueKey(_responseText),
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            _responseText,
                            textAlign: TextAlign.center,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: fg.withValues(alpha: 0.72),
                              fontSize: 15,
                              height: 1.65,
                              fontWeight: FontWeight.w300,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                ),

                ValueListenableBuilder<int>(
                  valueListenable: RigbyIslandController.instance.timerSecondsNotifier,
                  builder: (context, remaining, _) {
                    if (remaining <= 0) return const SizedBox.shrink();
                    final m = remaining ~/ 60;
                    final s = remaining % 60;
                    final timeStr = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: GestureDetector(
                        onTap: () => RigbyIslandController.instance.dismissTimer(),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeInOutCubic,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.orangeAccent.withValues(alpha: 0.25),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer_outlined,
                                  color: Colors.orangeAccent.withValues(alpha: 0.9),
                                  size: 18),
                              const SizedBox(width: 10),
                              Text(
                                timeStr,
                                style: const TextStyle(
                                  color: Colors.orangeAccent,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(Icons.close_rounded,
                                  color: Colors.orangeAccent.withValues(alpha: 0.5),
                                  size: 16),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const Spacer(),

                AnimatedOpacity(
                  opacity: _transcribedText.isNotEmpty ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      '"$_transcribedText"',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.30),
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                AnimatedOpacity(
                  opacity: _isListening || _isProcessing ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _isListening ? 'Listening...' : 'Thinking...',
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.25),
                      fontSize: 11,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CircleIconButton(
                        icon: Icons.chat_bubble_outline_rounded,
                        fg: fg,
                        onTap: _openChatSheet,
                      ),
                      const SizedBox(width: 20),
                      _CircleIconButton(
                        icon: Icons.camera_alt_outlined,
                        fg: fg,
                        onTap: () => _pickAndAnalyzeImage(),
                      ),
                      const SizedBox(width: 20),
                      RigbyMicButton(
                        isListening: _isListening,
                        isEnabled: _speechAvailable && !_isProcessing
                            && _vizState != VisualizerState.speaking,
                        onTap: _toggleListening,
                        amplitude: _amplitude,
                      ),
                      const SizedBox(width: 20),
                      _CircleIconButton(
                        icon: Icons.refresh_rounded,
                        fg: fg,
                        onTap: _resetConversation,
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingHeader extends StatelessWidget {
  final bool isDark;
  final Color fg;
  const _FloatingHeader({required this.isDark, required this.fg});

  @override
  Widget build(BuildContext context) {
    final surfaceBg = isDark ? AppColors.surface : Colors.white;
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: surfaceBg.withValues(alpha: isDark ? 0.6 : 0.85),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: fg.withValues(alpha: 0.12), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(shape: BoxShape.circle, color: fg),
                child: Center(
                  child: Text(
                    'R',
                    style: AppTextStyles.statusLabel.copyWith(
                      color: isDark ? Colors.black : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'Rigby',
                style: AppTextStyles.titleLarge.copyWith(
                  fontSize: 12, letterSpacing: 2, color: fg,
                ),
              ),
              const SizedBox(width: 16),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fg,
                  boxShadow: [BoxShadow(color: fg.withValues(alpha: 0.8), blurRadius: 6)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color fg;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.fg, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fg.withValues(alpha: 0.06),
          border: Border.all(color: fg.withValues(alpha: 0.14), width: 0.5),
        ),
        child: Icon(icon, size: 18, color: fg.withValues(alpha: 0.50)),
      ),
    );
  }
}
