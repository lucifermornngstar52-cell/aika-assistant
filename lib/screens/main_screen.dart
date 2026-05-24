import 'dart:async';
import '../services/app_launcher_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/device_service.dart';
import '../services/memory_service.dart';
import '../services/speech_service.dart';
import '../services/wake_word_service.dart';
import '../services/smart_notifications_service.dart';
import '../services/habit_memory_service.dart';
import '../services/relationship_service.dart';
import '../services/personality_service.dart';
import '../services/assistant_mood_service.dart';
import '../services/overlay_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/voice_button.dart';
import '../widgets/aika_avatar.dart';
import 'settings_screen.dart';
import 'currency_screen.dart';
import '../services/music_detector_service.dart';
import '../services/message_sender_service.dart';
import '../services/url_launcher_service.dart';
import '../services/music_control_service.dart';
import '../services/screen_watcher_service.dart';
import '../services/notification_service.dart';
import '../services/people_memory_service.dart';
import '../services/reminder_service.dart';
import '../services/mood_service.dart';
import '../services/game_service.dart';
import '../services/alarm_service.dart';
import '../services/briefing_service.dart';
import '../services/news_service.dart';
import '../services/mood_diary_service.dart';
import '../services/focus_mode_service.dart';
import '../services/custom_shortcuts_service.dart';
import '../services/notification_reply_service.dart';
import '../services/telegram_bot_service.dart';
import 'mood_diary_screen.dart';
import 'telegram_bot_screen.dart';
import 'app_commands_screen.dart';
import '../services/game_music_service.dart';
import '../services/notification_reader_service.dart';
import '../services/smart_alarm_service.dart';
import '../services/schedule_service.dart';
import 'schedule_screen.dart';
import 'package:lottie/lottie.dart';
import '../services/emotion_service.dart';
import '../services/screen_reader_service.dart';
import '../services/screen_reader_service.dart';
import '../services/edge_tts_service.dart';
import '../widgets/jarvis_hud.dart';
import '../services/theme_switcher_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final AiService _aiService = AiService();
  final DeviceService _deviceService = DeviceService();
  final MemoryService _memoryService = MemoryService();
  final SpeechService _speechService = SpeechService();
  final WakeWordService _wakeWordService = WakeWordService();
  final PeopleMemoryService _peopleMemory = PeopleMemoryService();
  final ReminderService _reminderService = ReminderService();
  final MoodService _moodService = MoodService();
  final GameService _gameService = GameService();
  final NewsService _newsService = NewsService();
  final MoodDiaryService _moodDiaryService = MoodDiaryService();
  final CustomShortcutsService _shortcutsService = CustomShortcutsService();

  // Notification reply state
  Map<String, String>? _pendingReplyNotif;
  bool _awaitingReplyConfirm = false;
  final ThemeSwitcherService _themeSwitcher = ThemeSwitcherService();
  final AlarmService _alarmService = AlarmService();
  final ScheduleService _scheduleService = ScheduleService();
  final BriefingService _briefingService = BriefingService();
  final FlutterTts _tts = FlutterTts();
  final EdgeTtsService _edgeTts = EdgeTtsService();
  bool _useEdgeTts = true; // Microsoft Neural Voice by default
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();

  List<ChatMessage> _messages = [];
  bool _isListening = false;
  bool _isThinking = false;
  Completer<void>? _ttsCompleter;
  bool _wakeWordEnabled = false;
  bool _hasOverlayPermission = false;
  bool _hasAccessibilityPermission = false;
  bool _screenCommentsEnabled = true;
  bool _hasNotifPermission = false;
  bool _isDancing = false;
  bool _isStretching = false;
  Timer? _musicTimer;
  Timer? _idleTimer;      // Таймер бездействия → stretch
  String _assistantName = 'Aika';
  String _userName = '';

  AikaState get _avatarState {
    if (_isDancing)    return AikaState.dance;
    if (_isListening)  return AikaState.listening;
    if (_isThinking)   return AikaState.thinking;
    if (_isStretching) return AikaState.stretch;
    return AikaState.idle;
  }

  @override
  void initState() {
    _themeSwitcher.load();
    _themeSwitcher.addListener(() { if (mounted) setState(() {}); });
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServices();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recheckOverlayPermission();
      // Перечитываем настройки голоса при возврате из Settings
      _applyTtsSettings();
      _loadPrefs();
    }
  }

  Future<void> _initServices() async {
    await _speechService.initialize();
    await _wakeWordService.initialize();
    // initWithSharedStt больше не нужен — WakeWordService имеет свой STT
    await _applyTtsSettings();
    await _loadPrefs();
    await HabitMemoryService.load();
    await RelationshipService.load();
    await AssistantMoodService.load();
    _sendGreeting();
    // Init Telegram Bot
    TelegramBotService.onMessage = (text, from) async {
      const openAiKey = String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
      final ctx = await _memoryService.getUserContext();
      final history = await _memoryService.getHistory();
      final memCtx = await _peopleMemory.buildMemoryContext();
      try {
        final reply = await _aiService.sendMessage(
          text,
          userName: from.isNotEmpty ? from : (ctx['userName'] ?? ''),
          assistantName: ctx['assistantName'] ?? _assistantName,
          history: history,
          memoryContext: memCtx,
          openAiKey: openAiKey,
        );
        return reply.replaceAll(RegExp(r'\[ACTION:[^\]]+\]'), '').trim();
      } catch (e) {
        return 'Ошибка: $e';
      }
    };
    final botEnabled = await TelegramBotService.isEnabled();
    if (botEnabled) await TelegramBotService.start();

    FocusModeService.onMessage = (msg) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: msg,
        timestamp: DateTime.now(),
      ));
      _speak(msg);
    };
    await _recheckOverlayPermission();
    await _recheckAccessibilityPermission();
    await _initNotifications();
    _startMusicPolling();
    _resetIdleTimer();
    // Инициализируем новые сервисы
    await _reminderService.initialize();
    await _alarmService.initialize();

    // Smart alarm init
    SmartAlarmService.onAlarmFired = (text) async {
      if (!mounted) return;
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: text,
        timestamp: DateTime.now(),
      ));
      await _speak(text);
    };
    await SmartAlarmService.initialize();

    // Notification reader - озвучивать уведомления вслух
    NotificationReaderService.onSpeak = (text) async {
      await _speak(text);
      return text;
    };
    _alarmService.onAlarmFired = (text) {
      _moodService.onAlarmFired();
      if (!mounted) return;
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: text,
        timestamp: DateTime.now(),
      ));
      _speak(text);
    };
    _reminderService.onReminderFired = (text) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: '⏰ ',
        timestamp: DateTime.now(),
      ));
      _speak(text);
    };
    _moodService.setIdle();

    // Подписываемся на изменения настроения → обновляем оверлей
    _moodService.moodStream.listen((mood) {
      final state = _moodToOverlayState(mood);
      OverlayService.updateState(state);
    });
    // Автозапуск постоянного прослушивания wake word
    Future.delayed(const Duration(seconds: 1), _autoStartWakeWord);
  }

  Future<void> _autoStartWakeWord() async {
    if (_wakeWordEnabled) return;
    // Запускаем проактивные подсказки раз в 5 минут
    Future.delayed(const Duration(minutes: 5), _checkProactiveSuggestions);
    await _wakeWordService.startListening(() {
      if (!_isListening && !_isThinking) _onWakeWordDetected();
    });
    if (mounted) setState(() => _wakeWordEnabled = true);
  }

  Future<void> _recheckOverlayPermission() async {
    final has = await OverlayService.hasPermission();
    if (mounted && has != _hasOverlayPermission) {
      setState(() => _hasOverlayPermission = has);
    }
    if (has && mounted) {
      await OverlayService.showOverlay(state: 'idle');
    }
    if (!has && mounted) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !_hasOverlayPermission) _showOverlayPermissionDialog();
      });
    }
  }

  Future<void> _recheckAccessibilityPermission() async {
    final has = await ScreenWatcherService.isAccessibilityEnabled();
    if (mounted) setState(() => _hasAccessibilityPermission = has);
    if (has) {
      ScreenWatcherService.startWatching(
        onReaction: (reaction) {
          // Game music auto-trigger
          GameMusicService.onAppChanged(ScreenWatcherService.currentPackage).then((msg) {
            if (msg != null && mounted) {
              _addMessage(ChatMessage(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                role: MessageRole.aika,
                content: msg,
                timestamp: DateTime.now(),
              ));
              _speak(msg);
            }
          });
          if (!_screenCommentsEnabled) return;
          if (!_isListening && !_isThinking && !_isDancing) {
            // Добавляем сообщение в чат и говорим
            _addMessage(ChatMessage(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              role: MessageRole.aika,
              content: reaction,
              timestamp: DateTime.now(),
            ));
            _speak(reaction);
            OverlayService.updateState('greeting');
            Future.delayed(const Duration(seconds: 3), () {
              OverlayService.updateState('idle');
            });
          }
        },
      );
    } else {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && !_hasAccessibilityPermission) _showAccessibilityDialog();
      });
    }
  }

  /// Конвертирует AikaMood → строку для оверлея
  String _moodToOverlayState(AikaMood mood) {
    switch (mood) {
      case AikaMood.idle:      return 'idle';
      case AikaMood.happy:     return 'greeting';
      case AikaMood.listening: return 'listening';
      case AikaMood.thinking:  return 'thinking';
      case AikaMood.dancing:
      case AikaMood.music:     return 'dance';
      case AikaMood.sleepy:    return 'idle';
      case AikaMood.surprised: return 'greeting';
    }
  }

  Future<void> _initNotifications() async {
    final has = await NotificationService.hasPermission();
    if (mounted) setState(() => _hasNotifPermission = has);
    if (has) {
      NotificationService.startListening(
        onNew: (notif) {
          // Read notification aloud if enabled
          NotificationReaderService.onNotification(notif);
          // Можно добавить реакцию на важные уведомления
          final title = notif['title'] ?? '';
          final text  = notif['text']  ?? '';
          if (title.isNotEmpty) {
            // Пока просто кэшируем — брифинг по запросу
          }
        },
      );
    } else {
      // Попросим через 6 секунд если нет разрешения
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted && !_hasNotifPermission) _showNotifPermissionDialog();
      });
    }
  }

  void _showNotifPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AikaTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.3)),
        ),
        title: Text('Чтение уведомлений',
            style: TextStyle(color: AikaTheme.neonBlue, fontWeight: FontWeight.bold)),
        content: const Text(
          'Разреши Айке читать уведомления — она сможет рассказать что пришло пока тебя не было.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Не сейчас', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AikaTheme.neonBlue.withOpacity(0.2),
              side: BorderSide(color: AikaTheme.neonBlue),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              NotificationService.openPermissionSettings();
            },
            child: const Text('Разрешить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAccessibilityDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AikaTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AikaTheme.neonPurple.withOpacity(0.4)),
        ),
        title: Text('Отслеживание экрана',
            style: TextStyle(color: AikaTheme.neonPurple, fontWeight: FontWeight.bold)),
        content: const Text(
          'Разреши Айке видеть какое приложение открыто — она сможет помогать в контексте.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Не сейчас', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AikaTheme.neonPurple.withOpacity(0.2),
              side: BorderSide(color: AikaTheme.neonPurple),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ScreenWatcherService.openAccessibilitySettings();
            },
            child: const Text('Включить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showOverlayPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AikaTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.3)),
        ),
        title: Text('Разрешение на оверлей',
            style: TextStyle(color: AikaTheme.neonBlue, fontWeight: FontWeight.bold)),
        content: const Text(
          'Разреши Айке появляться поверх других приложений — она будет видна всегда!',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Не сейчас', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AikaTheme.neonBlue.withOpacity(0.2),
              side: BorderSide(color: AikaTheme.neonBlue),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              OverlayService.requestPermission();
            },
            child: const Text('Разрешить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleWakeWord() async {
    if (_wakeWordEnabled) {
      await _wakeWordService.stop();
      setState(() => _wakeWordEnabled = false);
      _showSnack('Wake word выключен');
    } else {
      await _wakeWordService.startListening(() {
        if (!_isListening && !_isThinking) _onWakeWordDetected();
      });
      setState(() => _wakeWordEnabled = true);
      _showSnack('Скажи "$_assistantName" чтобы активировать');
    }
  }

  Future<void> _onWakeWordDetected() async {
    _resetIdleTimer();
    // Приостанавливаем wake word пока обрабатываем команду
    await _wakeWordService.pause();
    await OverlayService.showOverlay(state: 'listening');
    await _speak('Да?');
    setState(() => _isListening = true);
    await _speechService.startListening(
      onResult: (text) async {
        // Если Айка задремала — радостное приветствие
        if (_moodService.isSleepy) {
          final wakeMsg = _moodService.getWakeUpMessage();
          _addMessage(ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            role: MessageRole.aika,
            content: wakeMsg,
            timestamp: DateTime.now(),
          ));
          await _speak(wakeMsg);
          _moodService.onUserSpoke();

    // ── Emotion Detection ────────────────────────────────────────────────
    final detectedEmotion = EmotionService.detect(text);
    if (EmotionService.shouldReact(detectedEmotion)) {
      final reaction = EmotionService.getEmotionReaction(detectedEmotion);
      if (reaction != null) {
        _addMessage(ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: MessageRole.aika,
          content: reaction,
          timestamp: DateTime.now(),
        ));
        await _speak(reaction);
      }
    }
    // Меняем настроение Айки по эмоции
    if (detectedEmotion != UserEmotion.neutral) {
      final moodName = EmotionService.getAikaMoodForEmotion(detectedEmotion);
      if (moodName == 'happy') _moodService.onUserSpoke();
      else if (moodName == 'thinking') _moodService.onThinking();
    }
        }
        setState(() => _isListening = false);
        await OverlayService.updateState('thinking');
        if (text.isNotEmpty) await _sendMessage(text);
        await OverlayService.updateState('idle');
        // Возобновляем wake word после команды
        if (_wakeWordEnabled) await _wakeWordService.resume();
      },
      onDone: () {
        setState(() => _isListening = false);
        OverlayService.updateState('idle');
        if (_wakeWordEnabled) _wakeWordService.resume();
      },
    );
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _assistantName = prefs.getString('assistant_name') ?? 'Aika';
      _userName = prefs.getString('user_name') ?? '';
    });
  }

  Future<void> _applyTtsSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await _tts.setSpeechRate(prefs.getDouble('tts_rate') ?? 0.5);

    // Initialize EdgeTTS (Microsoft Neural Voices)
    await _edgeTts.initialize();
    final savedVoice = prefs.getString('edge_voice');
    if (savedVoice != null) _edgeTts.setVoice(savedVoice);
    // Читаем флаг use_edge_tts из настроек
    _useEdgeTts = prefs.getBool('use_edge_tts') ?? true;
    await _tts.setPitch(prefs.getDouble('tts_pitch') ?? 1.0);
    await _tts.setVolume(prefs.getDouble('tts_volume') ?? 1.0);
    final voice = prefs.getString('tts_voice');
    if (voice != null) await _tts.setVoice({'name': voice, 'locale': 'ru-RU'});
  }


  /// Сбрасывает таймер бездействия. Вызывается после каждого действия.
  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (mounted && _isStretching) {
      setState(() => _isStretching = false);
      OverlayService.updateState('idle');
    }
    _idleTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_isListening && !_isThinking && !_isDancing) {
        setState(() => _isStretching = true);
        OverlayService.updateState('stretch');
        // Через 3 секунды возвращаемся в idle
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() => _isStretching = false);
            OverlayService.updateState('idle');
          }
        });
      }
    });
  }

  void _startMusicPolling() {
    _musicTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_isListening || _isThinking) return;
      final playing = await MusicDetectorService.isMusicPlaying();
      if (playing) {
        if (!_isDancing) {
          if (mounted) setState(() => _isDancing = true);
          OverlayService.updateState('dance');
        }
        // Медиа играет — полностью выключаем микрофон (не реагируем на музыку/видео)
        _wakeWordService.setMusicPlaying(true);
      } else {
        if (_isDancing) {
          if (mounted) setState(() => _isDancing = false);
          OverlayService.updateState('idle');
        }
        // Медиа остановилась — включаем микрофон обратно
        _wakeWordService.setMusicPlaying(false);
      }
    });
  }


  void _sendGreeting() {
    final greeting = _userName.isNotEmpty
        ? 'Привет, $_userName! Я $_assistantName. Чем могу помочь?'
        : 'Привет! Я $_assistantName. Чем могу помочь?';
    _addMessage(ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.aika,
      content: greeting,
      timestamp: DateTime.now(),
    ));
    _speak(greeting);
    OverlayService.showOverlay(state: 'greeting');
  }

  void _addMessage(ChatMessage msg) {
    setState(() => _messages.add(msg));
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _speak(String text) async {
    final clean = text.replaceAll(RegExp(r'\[ACTION:[^\]]+\]'), '').trim();
    if (clean.isEmpty) return;

    // Останавливаем предыдущий TTS
    await _tts.stop();
    await _edgeTts.stop();
    _ttsCompleter?.complete();
    _ttsCompleter = null;

    // Пауза wake word на время речи
    final wasEnabled = _wakeWordEnabled;
    if (wasEnabled) await _wakeWordService.pause();

    // ── Пробуем EdgeTTS (Microsoft Neural Voice) ──
    if (_useEdgeTts) {
      try {
        // speak() блокируется до конца воспроизведения — не нужен busy-loop
        await _edgeTts.speak(clean);
        if (wasEnabled && !_isListening) {
          await Future.delayed(const Duration(milliseconds: 200));
          await _wakeWordService.resume();
        }
        return;
      } catch (e) {
        debugPrint('[_speak] EdgeTTS failed: \$e — fallback system TTS');
      }
    }

    // ── Fallback: системный TTS ──
    final completer = Completer<void>();
    _ttsCompleter = completer;

    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    _tts.setErrorHandler((e) {
      debugPrint('[TTS] error: \$e');
      if (!completer.isCompleted) completer.complete();
    });

    try {
      await _tts.speak(clean);
      // Ждём завершения — таймаут: ~8 символов/сек + 3 сек запас
      await completer.future.timeout(
        Duration(seconds: (clean.length / 8).ceil() + 3),
        onTimeout: () {},
      );
    } catch (e) {
      debugPrint('[_speak] error: \$e');
    } finally {
      _ttsCompleter = null;
    }

    // Возобновляем wake word после речи
    if (wasEnabled && _wakeWordEnabled && !_isListening) {
      await Future.delayed(const Duration(milliseconds: 300));
      await _wakeWordService.resume();
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AikaTheme.neonBlue.withOpacity(0.8),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }


  // ── Парсер команды отправки сообщения ─────────────────────────────────────
  // Форматы: "отправь/напиши [в ватсап/телеграм] контакту [имя] [текст]"
  //          "айка отправь богдану привет как дела"
  _SendCommand? _parseSendCommand(String text) {
    final lower = text.toLowerCase().trim();

    // Триггерные слова
    final triggers = ['отправь', 'напиши', 'скинь', 'пошли'];
    bool hasTrigger = triggers.any((t) => lower.contains(t));
    if (!hasTrigger) return null;

    // Определяем приложение
    String app = 'whatsapp'; // по умолчанию
    if (lower.contains('телеграм') || lower.contains('telegram') || lower.contains('тг')) {
      app = 'telegram';
    } else if (lower.contains('ватсап') || lower.contains('вацап') || lower.contains('whatsapp')) {
      app = 'whatsapp';
    }

    // Убираем триггер и название приложения
    String cleaned = lower;
    for (final t in triggers) { cleaned = cleaned.replaceFirst(t, ''); }
    cleaned = cleaned
        .replaceAll(RegExp(r'в ватсап|в вацап|в whatsapp|в телеграм|в telegram|в тг'), '')
        .replaceAll(RegExp(r'ватсап|вацап|whatsapp|телеграм|telegram'), '')
        .trim();

    // Ищем имя контакта: "контакту [имя]" или "[имя]у/у [имя]"
    String contact = '';
    String message = '';

    final contactPattern = RegExp(r'контакту?\s+(\S+)(.*)');
    final m = contactPattern.firstMatch(cleaned);
    if (m != null) {
      contact = m.group(1)!.trim();
      message = m.group(2)!.trim();
    } else {
      // Без слова "контакт" — первое слово это имя
      final parts = cleaned.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        contact = parts[0];
        message = parts.sublist(1).join(' ');
      } else {
        return null; // Не хватает данных
      }
    }

    // Убираем падежные окончания из имени (богдану → богдан)
    contact = _normalizeName(contact);

    if (contact.isEmpty || message.isEmpty) return null;
    return _SendCommand(app: app, contact: contact, message: message);
  }

  String _normalizeName(String name) {
    // Убираем распространённые падежные окончания
    final suffixes = ['у', 'ю', 'а', 'е', 'ом', 'ем', 'ой', 'ей', 'ам', 'ям'];
    for (final s in suffixes) {
      if (name.length > 3 && name.endsWith(s)) {
        return name.substring(0, name.length - s.length);
      }
    }
    return name;
  }

  Future<String?> _trySendMessage(String text) async {
    final cmd = _parseSendCommand(text);
    if (cmd == null) return null;

    final appName = cmd.app == 'whatsapp' ? 'WhatsApp' : 'Telegram';
    final reply = 'Отправляю "${cmd.message}" контакту ${cmd.contact} в $appName...';
    OverlayService.updateState('greeting');

    final result = await MessageSenderService.sendMessage(
      app: cmd.app,
      contact: cmd.contact,
      message: cmd.message,
    );

    Future.delayed(const Duration(seconds: 2), () => OverlayService.updateState('idle'));
    return reply;
  }

  /// Запускаем танец — вызывается из sendMessage если команда "танцуй"
  void _startDance() {
    if (_isListening || _isThinking) return;
    setState(() => _isDancing = true);
    OverlayService.updateState('dance');
  }

  void _stopDance() {
    if (!_isDancing) return;
    setState(() => _isDancing = false);
    OverlayService.updateState('idle');
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _textController.clear();
    _resetIdleTimer();

    // ── Управление музыкой ───────────────────────────────────────────────
    final musicCmd = MusicControlService.parseCommand(text);
    if (musicCmd != null) {
      await MusicControlService.send(musicCmd);
      final replies = {
        'play': 'Включаю музыку 🎵',
        'pause': 'Поставила на паузу ⏸',
        'stop': 'Останавливаю музыку ⏹',
        'next': 'Следующий трек ⏭',
        'previous': 'Предыдущий трек ⏮',
      };
      final reply = replies[musicCmd] ?? 'Готово';
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: reply,
        timestamp: DateTime.now(),
      ));
      await _speak(reply);
      return;
    }

    // ── Открытие сайтов ──────────────────────────────────────────────────
    final url = UrlLauncherService.parseUrlCommand(text);
    if (url != null) {
      final reply = 'Открываю $url 🌐';
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: reply,
        timestamp: DateTime.now(),
      ));
      await _speak('Открываю');
      await UrlLauncherService.openUrl(url);
      return;
    }

    // ── Попытка команды отправки сообщения ──────────────────────────────
    final sendResult = await _trySendMessage(text);
    if (sendResult != null) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: sendResult,
        timestamp: DateTime.now(),
      ));
      await _speak(sendResult);
      return;
    }
    _resetIdleTimer(); // Активность — сбрасываем stretch таймер

    // Проверяем команду танца
    final lower = text.trim().toLowerCase();
    final isDanceCommand = lower.contains('танцуй') ||
        lower.contains('танцевать') ||
        lower.contains('потанцуй') ||
        lower.contains('dance');

    if (isDanceCommand) {
      _startDance();
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.user,
        content: text,
        timestamp: DateTime.now(),
      ));
      _addMessage(ChatMessage(
        id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
        role: MessageRole.aika,
        content: '🎵 Хорошо, танцую!',
        timestamp: DateTime.now(),
      ));
      await _speak('Хорошо, танцую!');
      return;
    }

    // Стоп-команда
    final isStopDance = lower.contains('стоп') || lower.contains('хватит') ||
        lower.contains('остановись') || lower.contains('stop');
    if (isStopDance && _isDancing) {
      _stopDance();
    }

    // ── Ответ на уведомления ──
    if (_awaitingReplyConfirm && _pendingReplyNotif != null) {
      if (NotificationReplyService.isConfirm(lower)) {
        final notif = _pendingReplyNotif!;
        _awaitingReplyConfirm = false;
        _pendingReplyNotif = null;
        // Генерируем ответ через AI
        final ctx = await _memoryService.getUserContext();
        final history = await _memoryService.getHistory();
        const openAiKey = String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
        final aiReply = await _aiService.sendMessage(
          'Составь короткий вежливый ответ на сообщение: "${notif['title']}: ${notif['text']}"',
          userName: ctx['userName'] ?? '',
          assistantName: ctx['assistantName'] ?? _assistantName,
          history: history,
          openAiKey: openAiKey,
        );
        final cleanReply = aiReply.replaceAll(RegExp(r'\[ACTION:[^\]]+\]'), '').trim();
        final sent = await NotificationReplyService.replyToNotification(
          packageName: notif['pkg'] ?? '',
          text: cleanReply,
        );
        final result = sent ? 'Отправила ответ: "$cleanReply" ✓' : 'Не удалось отправить автоматически. Скопируй: "$cleanReply"';
        _addMessage(ChatMessage(id: DateTime.now().millisecondsSinceEpoch.toString(), role: MessageRole.aika, content: result, timestamp: DateTime.now()));
        await _speak(sent ? 'Отправила!' : 'Не смогла отправить автоматически');
        return;
      } else if (NotificationReplyService.isCancel(lower)) {
        _awaitingReplyConfirm = false;
        _pendingReplyNotif = null;
        const msg = 'Хорошо, не отправляю.';
        _addMessage(ChatMessage(id: DateTime.now().millisecondsSinceEpoch.toString(), role: MessageRole.aika, content: msg, timestamp: DateTime.now()));
        await _speak(msg);
        return;
      }
    }

    // Проверка запроса ответить на уведомление
    if (NotificationReplyService.isReplyRequest(lower)) {
      final recent = NotificationService.recent;
      final replyable = recent.where((n) => NotificationReplyService.canReply(n)).toList();
      if (replyable.isEmpty) {
        const msg = 'Нет недавних сообщений которые можно ответить.';
        _addMessage(ChatMessage(id: DateTime.now().millisecondsSinceEpoch.toString(), role: MessageRole.aika, content: msg, timestamp: DateTime.now()));
        await _speak(msg);
        return;
      }
      final last = replyable.last;
      final appName = NotificationReplyService.appNameFor(last);
      _pendingReplyNotif = last;
      _awaitingReplyConfirm = true;
      final prompt = 'Ответить в $appName на сообщение от ${last['title']}: "${last['text']}"?\n\nСкажи "да" чтобы я придумала ответ, или "нет" чтобы отменить.';
      _addMessage(ChatMessage(id: DateTime.now().millisecondsSinceEpoch.toString(), role: MessageRole.user, content: text, timestamp: DateTime.now()));
      _addMessage(ChatMessage(id: (DateTime.now().millisecondsSinceEpoch + 1).toString(), role: MessageRole.aika, content: prompt, timestamp: DateTime.now()));
      await _speak('Ответить в $appName на это сообщение?');
      return;
    }

    // ── Мини-игры голосом ──
    final gameResult = _gameService.tryHandleGame(text);
    if (gameResult != null) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.user,
        content: text,
        timestamp: DateTime.now(),
      ));
      _addMessage(ChatMessage(
        id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
        role: MessageRole.aika,
        content: gameResult,
        timestamp: DateTime.now(),
      ));
      await _speak(gameResult);
      _moodService.onSurprised();
      return;
    }

    // ── Чтение уведомлений (вкл/выкл голосом) ──
    final notifReaderResult = await NotificationReaderService.tryParseCommand(text);
    if (notifReaderResult != null) {
      _addMessage(ChatMessage(id: DateTime.now().millisecondsSinceEpoch.toString(), role: MessageRole.user, content: text, timestamp: DateTime.now()));
      _addMessage(ChatMessage(id: (DateTime.now().millisecondsSinceEpoch+1).toString(), role: MessageRole.aika, content: notifReaderResult, timestamp: DateTime.now()));
      await _speak(notifReaderResult);
      return;
    }

    // ── Умный будильник ──
    final smartAlarmResult = await SmartAlarmService.tryParseCommand(text);
    if (smartAlarmResult != null) {
      _addMessage(ChatMessage(id: DateTime.now().millisecondsSinceEpoch.toString(), role: MessageRole.user, content: text, timestamp: DateTime.now()));
      _addMessage(ChatMessage(id: (DateTime.now().millisecondsSinceEpoch+1).toString(), role: MessageRole.aika, content: smartAlarmResult, timestamp: DateTime.now()));
      await _speak(smartAlarmResult);
      return;
    }

    // ── Будильник ──
    final alarmResult = await _alarmService.tryParseAlarm(text);
    if (alarmResult != null) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.user,
        content: text,
        timestamp: DateTime.now(),
      ));
      _addMessage(ChatMessage(
        id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
        role: MessageRole.aika,
        content: alarmResult,
        timestamp: DateTime.now(),
      ));
      await _speak(alarmResult);
      _moodService.onUserSpoke();
      return;
    }

    // ── Утренний брифинг ──
    if (_briefingService.isBriefingRequest(text)) {
      setState(() { _isThinking = true; });
      try {
        final briefing = await _briefingService.getMorningBriefing();
        _addMessage(ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: MessageRole.user,
          content: text,
          timestamp: DateTime.now(),
        ));
        _addMessage(ChatMessage(
          id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
          role: MessageRole.aika,
          content: briefing,
          timestamp: DateTime.now(),
        ));
        await _speak(briefing);
        _moodService.onUserSpoke();
      } finally {
        setState(() { _isThinking = false; });
      }
      return;
    }

    
    // ── Расписание дня ────────────────────────────────────────────
    final addEventResult = await _scheduleService.tryParseAddEvent(text);
    if (addEventResult != null) {
      _addMessage(ChatMessage(id: DateTime.now().millisecondsSinceEpoch.toString(), role: MessageRole.user, content: text, timestamp: DateTime.now()));
      _addMessage(ChatMessage(id: (DateTime.now().millisecondsSinceEpoch+1).toString(), role: MessageRole.aika, content: addEventResult, timestamp: DateTime.now()));
      await _speak(addEventResult);
      _moodService.onUserSpoke();
      return;
    }
    if (_scheduleService.isScheduleRequest(text)) {
      final tl = text.toLowerCase();
      _addMessage(ChatMessage(id: DateTime.now().millisecondsSinceEpoch.toString(), role: MessageRole.user, content: text, timestamp: DateTime.now()));
      final schedule = tl.contains('завтра')
          ? await _scheduleService.getTomorrowSchedule()
          : await _scheduleService.getTodaySchedule();
      _addMessage(ChatMessage(id: (DateTime.now().millisecondsSinceEpoch+1).toString(), role: MessageRole.aika, content: schedule, timestamp: DateTime.now()));
      await _speak(schedule);
      _moodService.onUserSpoke();
      return;
    }

    // ── Проверяем напоминания/таймеры ──
    final reminderResult = await _reminderService.tryParseReminder(text);
    if (reminderResult != null) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.user,
        content: text,
        timestamp: DateTime.now(),
      ));
      _addMessage(ChatMessage(
        id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
        role: MessageRole.aika,
        content: reminderResult,
        timestamp: DateTime.now(),
      ));
      await _speak(reminderResult);
      _moodService.onUserSpoke();
      return;
    }

    // ── Проверяем команды памяти (запомни что Богдан — друг) ──
    // Брифинг уведомлений
    if (text.contains('уведомлен') || text.contains('что пришло') ||
        text.contains('что пропустил') || text.contains('пока я спал') ||
        text.contains('пока меня не было')) {
      final briefing = NotificationService.buildBriefingText();
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: briefing,
        timestamp: DateTime.now(),
      ));
      await _speak(briefing);
      _moodService.onUserSpoke();
      return;
    }

    final isMemoryCmd = await _peopleMemory.tryParseMemoryCommand(text);
    if (isMemoryCmd) {
      const reply = 'Запомнила!';
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.user,
        content: text,
        timestamp: DateTime.now(),
      ));
      _addMessage(ChatMessage(
        id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
        role: MessageRole.aika,
        content: reply,
        timestamp: DateTime.now(),
      ));
      await _speak(reply);
      _moodService.onUserSpoke();
      return;
    }

    // ── Кастомные команды (shortcuts) ──
    final shortcutResult = await _shortcutsService.tryHandle(text);
    if (shortcutResult != null) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.user,
        content: text,
        timestamp: DateTime.now(),
      ));
      _addMessage(ChatMessage(
        id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
        role: MessageRole.aika,
        content: shortcutResult,
        timestamp: DateTime.now(),
      ));
      await _speak(shortcutResult);
      _moodService.onUserSpoke();
      return;
    }

    // ── Режим фокуса ──
    final focusResult = await FocusModeService.tryHandle(text);
    if (focusResult != null) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.user,
        content: text,
        timestamp: DateTime.now(),
      ));
      _addMessage(ChatMessage(
        id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
        role: MessageRole.aika,
        content: focusResult,
        timestamp: DateTime.now(),
      ));
      await _speak(focusResult);
      _moodService.onUserSpoke();
      return;
    }

    // ── Дневник настроения ──
    final moodResult = await _moodDiaryService.tryHandle(text);
    if (moodResult != null) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.user,
        content: text,
        timestamp: DateTime.now(),
      ));
      _addMessage(ChatMessage(
        id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
        role: MessageRole.aika,
        content: moodResult,
        timestamp: DateTime.now(),
      ));
      await _speak(moodResult);
      _moodService.onUserSpoke();
      return;
    }

    // ── Автомузыка команды голосом ──
    final gameMusicResult = await GameMusicService.tryParseCommand(text);
    if (gameMusicResult != null) {
      _addMessage(ChatMessage(id: DateTime.now().millisecondsSinceEpoch.toString(), role: MessageRole.user, content: text, timestamp: DateTime.now()));
      _addMessage(ChatMessage(id: (DateTime.now().millisecondsSinceEpoch + 1).toString(), role: MessageRole.aika, content: gameMusicResult, timestamp: DateTime.now()));
      await _speak(gameMusicResult);
      return;
    }

    // ── Новости ──
    final newsResult = await _newsService.tryParseNews(text);
    if (newsResult != null) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.user,
        content: text,
        timestamp: DateTime.now(),
      ));
      _addMessage(ChatMessage(
        id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
        role: MessageRole.aika,
        content: newsResult,
        timestamp: DateTime.now(),
      ));
      await _speak(newsResult);
      _moodService.onUserSpoke();
      return;
    }

    // ── Сначала проверяем локальные команды запуска приложений ──
    final appLaunchResult = await AppLauncherService.tryLaunch(text);
    if (appLaunchResult != null) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.user,
        content: text,
        timestamp: DateTime.now(),
      ));
      _addMessage(ChatMessage(
        id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
        role: MessageRole.aika,
        content: appLaunchResult,
        timestamp: DateTime.now(),
      ));
      await _speak(appLaunchResult);
      _moodService.onUserSpoke();
      return;
    }

    _addMessage(ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
    ));
    setState(() { _isThinking = true; _isDancing = false; });
    await OverlayService.updateState('thinking');

    // ── Управление телефоном голосом ─────────────────────────────────────
    if (ScreenReaderService.isPhoneControlRequest(text)) {
      final ctrlResult = await ScreenReaderService.tryHandlePhoneControl(text);
      if (ctrlResult != null) {
        _addMessage(ChatMessage(id: DateTime.now().millisecondsSinceEpoch.toString(), role: MessageRole.aika, content: ctrlResult, timestamp: DateTime.now()));
        setState(() => _isThinking = false);
        await _speak(ctrlResult);
        return;
      }
    }

    // ── Действия на экране (нажми, листай) ───────────────────────────────
    if (ScreenReaderService.isScreenActionRequest(text)) {
      final actionResult = await ScreenReaderService.tryHandleAction(text);
      if (actionResult != null) {
        _addMessage(ChatMessage(id: DateTime.now().millisecondsSinceEpoch.toString(), role: MessageRole.aika, content: actionResult, timestamp: DateTime.now()));
        setState(() => _isThinking = false);
        await _speak(actionResult);
        return;
      }
    }

    // ── Чтение контента экрана ───────────────────────────────────────────
    if (ScreenReaderService.isScreenReadRequest(text)) {
      final screenText = await ScreenReaderService.getScreenText();
      if (screenText != null && screenText.isNotEmpty) {
        final appLabel = ScreenWatcherService.currentLabel;
        final formatted = ScreenReaderService.formatForAI(screenText, appLabel);
        final aiReply = await _aiService.sendMessage(
          text,
          userName: _userName,
          assistantName: _assistantName,
          history: await _memoryService.getHistory(),
          screenContext: formatted,
        );
        final clean = aiReply.replaceAll(RegExp(r'\[ACTION:[^\]]+\]'), '').trim();
        _addMessage(ChatMessage(id: DateTime.now().millisecondsSinceEpoch.toString(), role: MessageRole.aika, content: clean, timestamp: DateTime.now()));
        await _speak(clean);
        return;
      } else {
        const noScreen = 'Не могу прочитать экран. Дай разрешение Accessibility для Айки в настройках.';
        _addMessage(ChatMessage(id: DateTime.now().millisecondsSinceEpoch.toString(), role: MessageRole.aika, content: noScreen, timestamp: DateTime.now()));
        await _speak(noScreen);
        return;
      }
    }

    await _memoryService.addMessage('user', text);

    try {
      _moodService.onThinking();
      final context = await _memoryService.getUserContext();
      final history = await _memoryService.getHistory();
      final memoryCtx   = await _peopleMemory.buildMemoryContext();
      final screenCtx   = ScreenWatcherService.currentLabel.isNotEmpty
          ? 'Сейчас на экране: \${ScreenWatcherService.currentLabel} (\${ScreenWatcherService.currentPackage})'
          : '';
      final _prefs = await SharedPreferences.getInstance();
      final _openAiKey = _prefs.getString('openai_api_key') ?? '';
      // Проверяем настроение ассистента — может не хотеть отвечать
      final moodRefusal = await AssistantMoodService.checkWillRespond(
          PersonalityService.current.name);
      if (moodRefusal != null && mounted) {
        _addMessage(ChatMessage(
          id: 'mood_\${DateTime.now().millisecondsSinceEpoch}',
          role: MessageRole.aika,
          content: moodRefusal,
          timestamp: DateTime.now(),
        ));
        await _speak(moodRefusal);
        _moodService.setIdle();
        setState(() => _isThinking = false);
        return;
      }

      // Анализируем отношение пользователя — получаем возможную реакцию
      final relationReaction = await RelationshipService.analyzeMessage(
          text, PersonalityService.current.name);
      if (relationReaction != null && mounted) {
        _addMessage(ChatMessage(
          id: 'rel_\${DateTime.now().millisecondsSinceEpoch}',
          role: MessageRole.aika,
          content: relationReaction,
          timestamp: DateTime.now(),
        ));
        await _speak(relationReaction);
      }

      // Записываем привычки
      await HabitMemoryService.recordRequest(text);

      final response = await _aiService.sendMessage(
        text,
        userName: context['userName'] ?? '',
        assistantName: context['assistantName'] ?? _assistantName,
        history: history,
        memoryContext: memoryCtx,
        screenContext: screenCtx,
        openAiKey: _openAiKey,
      );
      final actionResult = await _deviceService.parseAndExecute(response);
      final display = response.replaceAll(RegExp(r'\[ACTION:[^\]]+\]'), '').trim();
      final finalMsg = actionResult != null ? '$display\n$actionResult' : display;
      await _memoryService.addMessage('assistant', display);
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: finalMsg,
        timestamp: DateTime.now(),
      ));
      await _speak(finalMsg);
      _moodService.onUserSpoke();
    } catch (e) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: 'Ошибка: $e',
        timestamp: DateTime.now(),
      ));
    } finally {
      setState(() => _isThinking = false);
      await OverlayService.updateState('idle');
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speechService.stopListening();
      setState(() => _isListening = false);
      await OverlayService.updateState('idle');
    } else {
      setState(() { _isListening = true; _isDancing = false; });
      await OverlayService.updateState('listening');
      await _speechService.startListening(
        onResult: (text) {
          if (text.isNotEmpty) _sendMessage(text);
        },
        onDone: () {
          setState(() => _isListening = false);
          OverlayService.updateState('idle');
        },
      );
    }
  }

  Future<void> _openCurrency() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CurrencyScreen()));
  }

  Future<void> _openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    await _loadPrefs();
    await _applyTtsSettings();
    await _wakeWordService.updateTriggers();
    await _recheckOverlayPermission();
  }

  Future<void> _checkProactiveSuggestions() async {
    if (!mounted) return;
    final suggestion = await HabitMemoryService.getProactiveSuggestion();
    if (suggestion != null && mounted && !_isListening && !_isThinking) {
      _addMessage(ChatMessage(
        id: 'habit_${DateTime.now().millisecondsSinceEpoch}',
        role: MessageRole.aika,
        content: suggestion,
        timestamp: DateTime.now(),
      ));
      await _speak(suggestion);
    }
    // Перезапускаем через 5 минут
    if (mounted) {
      Future.delayed(const Duration(minutes: 5), _checkProactiveSuggestions);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _textController.dispose();
    _tts.stop();
    _musicTimer?.cancel();
    _idleTimer?.cancel();
    _deviceService.dispose();
    _wakeWordService.stop();
    SmartAlarmService.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    if (_themeSwitcher.isJarvis) {
      return JarvisHud(
        isListening: _isListening,
        isThinking: _isThinking,
        lastResponse: _messages.isNotEmpty ? _messages.last.content : '',
        messages: _messages.map((m) => JarvisMessage(
          content: m.content,
          isUser: m.role == MessageRole.user,
          timestamp: m.timestamp,
        )).toList(),
        textController: _textController,
        scrollController: _scrollController,
        onSendMessage: _sendMessage,
        onMicTap: _toggleListening,
        onThemeSwitch: () => _themeSwitcher.toggle(),
        wakeWordEnabled: _wakeWordEnabled,
        onToggleWakeWord: _toggleWakeWord,
        hasOverlayPermission: _hasOverlayPermission,
        onOverlayPermission: _showOverlayPermissionDialog,
        onOpenSettings: _openSettings,
        onOpenCurrency: _openCurrency,
        onOpenMoodDiary: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MoodDiaryScreen())),
        onOpenSchedule: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScheduleScreen())),
        onOpenTelegram: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TelegramBotScreen())),
        onOpenAppCommands: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppCommandsScreen())),
        assistantName: _assistantName,
        userName: _userName,
      );
    }
    return Scaffold(
      backgroundColor: AikaTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_assistantName.toUpperCase(),
                          style: TextStyle(
                            color: AikaTheme.neonBlue,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                          )),
                      Text(
                        _userName.isNotEmpty ? 'Привет, $_userName' : 'AI Assistant',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _toggleWakeWord,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _wakeWordEnabled
                                ? AikaTheme.neonBlue.withOpacity(0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _wakeWordEnabled
                                  ? AikaTheme.neonBlue.withOpacity(0.6)
                                  : Colors.white24,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.hearing, size: 14,
                                  color: _wakeWordEnabled ? AikaTheme.neonBlue : Colors.white38),
                              const SizedBox(width: 4),
                              Text(_wakeWordEnabled ? 'ON' : 'OFF',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _wakeWordEnabled ? AikaTheme.neonBlue : Colors.white38,
                                  )),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!_hasOverlayPermission)
                        GestureDetector(
                          onTap: _showOverlayPermissionDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.orange.withOpacity(0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.face_outlined, size: 14, color: Colors.orange),
                                SizedBox(width: 4),
                                Text('Показать Айку',
                                    style: TextStyle(fontSize: 10, color: Colors.orange)),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.currency_exchange, color: Colors.white54),
                        onPressed: _openCurrency,
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.settings_outlined, color: Colors.white54),
                        color: const Color(0xFF1A1A2E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onSelected: (value) {
                          if (value == 'settings') _openSettings();
                          if (value == 'switchtheme') _themeSwitcher.toggle();
                          if (value == 'mood') Navigator.push(context, MaterialPageRoute(builder: (_) => const MoodDiaryScreen()));
                          if (value == 'schedule') Navigator.push(context, MaterialPageRoute(builder: (_) => const ScheduleScreen()));
                          if (value == 'telegram') Navigator.push(context, MaterialPageRoute(builder: (_) => const TelegramBotScreen()));
                          if (value == 'appcommands') Navigator.push(context, MaterialPageRoute(builder: (_) => const AppCommandsScreen()));
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'switchtheme', child: Row(children: [Text('🤖', style: TextStyle(fontSize: 16)), SizedBox(width: 10), Text('Переключить тему', style: TextStyle(color: Colors.white70))])),
                          const PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings_outlined, color: Colors.white70, size: 18), SizedBox(width: 10), Text('Настройки', style: TextStyle(color: Colors.white70))])),
                          const PopupMenuItem(value: 'mood', child: Row(children: [Text('📖', style: TextStyle(fontSize: 16)), SizedBox(width: 10), Text('Дневник настроения', style: TextStyle(color: Colors.white70))])),
                          const PopupMenuItem(value: 'schedule', child: Row(children: [Icon(Icons.calendar_today, color: Colors.white70, size: 18), SizedBox(width: 10), Text('Расписание', style: TextStyle(color: Colors.white70))])),
                          const PopupMenuItem(value: 'telegram', child: Row(children: [Text('🤖', style: TextStyle(fontSize: 16)), SizedBox(width: 10), Text('Telegram Бот', style: TextStyle(color: Colors.white70))])),
                          const PopupMenuItem(value: 'appcommands', child: Row(children: [Text('⚡', style: TextStyle(fontSize: 16)), SizedBox(width: 10), Text('Команды приложений', style: TextStyle(color: Colors.white70))])),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Wake word banner ────────────────────────────────────
            if (_wakeWordEnabled)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AikaTheme.neonBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.hearing, size: 12, color: AikaTheme.neonBlue.withOpacity(0.7)),
                    const SizedBox(width: 6),
                    Text('Жду: "$_assistantName"',
                        style: TextStyle(
                          color: AikaTheme.neonBlue.withOpacity(0.7),
                          fontSize: 11,
                          letterSpacing: 1,
                        )),
                  ],
                ),
              ),

            // ── Chat ───────────────────────────────────────────────
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/images/chat_wallpaper.jpg'),
                    fit: BoxFit.cover,
                    opacity: 0.18,
                  ),
                ),
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (ctx, i) => ChatBubble(message: _messages[i]),
                ),
              ),
            ),

            // ── Input bar ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AikaTheme.surface,
                border: Border(top: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.15))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Напишите или говорите...',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: _sendMessage,
                    ),
                  ),
                  const SizedBox(width: 8),
                  VoiceButton(
                    isListening: _isListening,
                    isSpeaking: false,
                    onTap: _toggleListening,
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _sendMessage(_textController.text),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AikaTheme.neonBlue.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.5)),
                      ),
                      child: Icon(Icons.send, color: AikaTheme.neonBlue, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Команда отправки сообщения — парсится из голосовой команды
class _SendCommand {
  final String app;
  final String contact;
  final String message;
  const _SendCommand({required this.app, required this.contact, required this.message});
}












