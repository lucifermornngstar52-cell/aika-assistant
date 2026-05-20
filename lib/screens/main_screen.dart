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
  final AlarmService _alarmService = AlarmService();
  final BriefingService _briefingService = BriefingService();
  final FlutterTts _tts = FlutterTts();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();

  List<ChatMessage> _messages = [];
  bool _isListening = false;
  bool _isThinking = false;
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
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServices();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recheckOverlayPermission();
    }
  }

  Future<void> _initServices() async {
    await _speechService.initialize();
    await _wakeWordService.initialize();
    // initWithSharedStt больше не нужен — WakeWordService имеет свой STT
    await _applyTtsSettings();
    await _loadPrefs();
    _sendGreeting();
    await _recheckOverlayPermission();
    await _recheckAccessibilityPermission();
    await _initNotifications();
    _startMusicPolling();
    _resetIdleTimer();
    // Инициализируем новые сервисы
    await _reminderService.initialize();
    await _alarmService.initialize();
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
      _showSnack('Скажи "Айка" чтобы активировать');
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
    _musicTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_isListening || _isThinking) return;
      final playing = await MusicDetectorService.isMusicPlaying();
      if (playing) {
        if (!_isDancing) {
          if (mounted) setState(() => _isDancing = true);
          OverlayService.updateState('dance');
        }
        // Не останавливаем wake word полностью — просто сообщаем что играет музыка
        _wakeWordService.setMusicPlaying(true);
      } else {
        if (_isDancing) {
          if (mounted) setState(() => _isDancing = false);
          OverlayService.updateState('idle');
        }
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
    final clean = text.replaceAll(RegExp(r'\[ACTION:[^\]]+\]'), '');
    await _tts.speak(clean);
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
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
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
                      IconButton(
                        icon: const Icon(Icons.settings_outlined, color: Colors.white54),
                        onPressed: _openSettings,
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
                    Text('Жду: "Айка"',
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
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _messages.length,
                itemBuilder: (ctx, i) => ChatBubble(message: _messages[i]),
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



