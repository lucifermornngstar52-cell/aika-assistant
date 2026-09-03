import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import '../services/app_launcher_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/live2d_widget.dart';
import 'settings_screen.dart';
import 'personality_screen.dart';
import 'model_picker_screen.dart';
import 'currency_screen.dart';
import '../services/music_detector_service.dart';
import '../services/message_sender_service.dart';
import '../services/media_control_service.dart';
import '../services/url_launcher_service.dart';
import '../services/weather_service.dart';
import '../services/device_security_service.dart';
import 'weather_screen.dart';
import '../services/music_control_service.dart';
import '../services/screen_watcher_service.dart';
import '../services/aika_feelings_service.dart';
import '../services/aika_automation_service.dart';
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
import '../services/aika_self_learning_service.dart';
import '../services/aika_browser_service.dart';
import '../services/aika_game_helper_service.dart';
import '../services/edge_tts_service.dart';
import '../services/elevenlabs_tts_service.dart';
import '../widgets/jarvis_hud.dart';
import '../widgets/overlay_settings_widget.dart';
import '../services/theme_switcher_service.dart';
import '../services/phone_control_service.dart';
import '../services/screen_command_service.dart';
import '../services/conversation_history_service.dart';
import '../services/suggestion_chips_service.dart';
import '../services/ping_sound_service.dart';
import '../services/clipboard_service.dart';
import '../services/contacts_service.dart';
import '../services/calendar_service.dart';
import '../services/shoplist_service.dart';
import '../services/step_counter_service.dart';
import '../services/voice_command_processor.dart';

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
  final PhoneControlService _phoneControl = PhoneControlService();
  final AlarmService _alarmService = AlarmService();
  final ClipboardService _clipboardService = ClipboardService();
  final ContactsService _contactsService = ContactsService();
  final CalendarService _calendarService = CalendarService();
  final ShoplistService _shoplistService = ShoplistService();
  final StepCounterService _stepCounter = StepCounterService();
  final ConversationHistoryService _convHistory = ConversationHistoryService();
  final SuggestionChipsService _suggestionsService = SuggestionChipsService();
  final PingSoundService _pingSound = PingSoundService();
  List<SuggestionChip> _currentChips = [];
  final ScheduleService _scheduleService = ScheduleService();
  final WeatherService _weatherService = WeatherService();
  final BriefingService _briefingService = BriefingService();
  final VoiceCommandProcessor _voiceProcessor = VoiceCommandProcessor();
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
  Key _live2dKey = UniqueKey(); // ФИКС: пересоздаём виджет модели после смены в ModelPickerScreen
  bool _chatMode = false; // false = command mode, true = chat/conversation mode
  bool _hasOverlayPermission = false;
  bool _hasAccessibilityPermission = false;
  bool _screenCommentsEnabled = true;
  String? _pendingImagePath; // Фото ожидающее отправки
  String? _pendingImageBase64;
  String _bgPresetId = 'none';
  String? _bgCustomImage;
  bool _hasNotifPermission = false;
  bool _isDancing = false;
  bool _isStretching = false;
  Timer? _musicTimer;

  // ── Флаги показа диалогов разрешений (показываем ОДИН раз за сессию) ─────
  bool _overlayDialogShown      = false;
  bool _accessibilityDialogShown = false;
  bool _notifDialogShown        = false;
  Timer? _idleTimer;      // Таймер бездействия → stretch
  String _assistantName = 'Aivora';
  String _userName = '';

  AikaState get _avatarState {
    if (_isDancing)    return AikaState.dance;
    if (_isListening)  return AikaState.listening;
    if (_isThinking)   return AikaState.thinking;
    if (_isStretching) return AikaState.stretch;
    return AikaState.idle;
  }

  // Выбор фото из галереи для отправки в чат
  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        dialogTitle: 'Выбери фото',
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final bytes = await File(path).readAsBytes();
        final b64 = base64Encode(bytes);
        setState(() {
          _pendingImagePath = path;
          _pendingImageBase64 = b64;
        });
      }
    } catch (e) {
      debugPrint('FilePicker: $e');
    }
  }

  // Съёмка фото через камеру
  Future<void> _pickImageFromCamera() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        dialogTitle: 'Сделай фото',
        allowCompression: true,
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final bytes = await File(path).readAsBytes();
        final b64 = base64Encode(bytes);
        setState(() {
          _pendingImagePath = path;
          _pendingImageBase64 = b64;
        });
      }
    } catch (e) {
      // Фолбэк — открываем обычный выбор файла
      await _pickImage();
    }
  }

  // Отправка сообщения с прикреплённым изображением — через AiService vision
  Future<void> _sendMessageWithImage(String text, String b64) async {
    final userText = text.isNotEmpty ? text : 'Посмотри на это фото и опиши что видишь';
    _addMessage(ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.user,
      content: '📷 $userText',
      timestamp: DateTime.now(),
    ));
    setState(() {
      _pendingImagePath = null;
      _pendingImageBase64 = null;
      _textController.clear();
      _isThinking = true;
    });
    OverlayService().asyncState('thinking');
    try {
      final reply = await _aiService.sendMessage(
        userText,
        userName: _userName,
        assistantName: _assistantName,
        history: _messages.map((m) => '${m.role.name}: ${m.content}').toList(),
        memoryContext: await _memoryService.getLongMemory(),
        imageBase64: b64,
        imageMimeType: 'image/jpeg',
      );
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: reply,
        timestamp: DateTime.now(),
      ));
      _speak(reply);
      OverlayService().asyncState('talking');
    } catch (e) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: 'Не смогла обработать изображение 😔 Попробуй ещё раз',
        timestamp: DateTime.now(),
      ));
      OverlayService().asyncState('idle');
    }
    setState(() => _isThinking = false);
  }

  List<Color> _bgGradient(String id) {
    const map = {
      'night':  [Color(0xFF0D0D2B), Color(0xFF1A0533)],
      'aurora': [Color(0xFF001F3F), Color(0xFF00A86B)],
      'sunset': [Color(0xFF1A0533), Color(0xFFFF6B35)],
      'ocean':  [Color(0xFF001B4A), Color(0xFF00B4D8)],
      'cherry': [Color(0xFF1A0020), Color(0xFFFF69B4)],
      'cyber':  [Color(0xFF0A0014), Color(0xFF7B00FF)],
    };
    final colors = map[id];
    if (colors == null) return [const Color(0xFF0F0F0F), const Color(0xFF0F0F0F)];
    return colors;
  }

  String get _avatarStateString {
    if (_isDancing)    return 'dance';
    if (_isListening)  return 'listening';
    if (_isThinking)   return 'thinking';
    if (_isStretching) return 'idle';
    return 'idle';
  }

  @override
  void initState() {
    _themeSwitcher.load();
    _themeSwitcher.addListener(() { if (mounted) setState(() {}); });
    _phoneControl.init();
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
      // Перепроверяем accessibility — пользователь мог вернуться из настроек разрешений
      // Retry: сервис может стартовать с задержкой до 3 сек
      _recheckAccessibilityWithRetry();
    }
  }

  Future<void> _initServices() async {
    await _speechService.initialize();
    // WakeWordService имеет СОБСТВЕННЫЙ STT — независимый от SpeechService.
    // Wake word работает постоянно, чат-STT подключается только после срабатывания.
    await _wakeWordService.initialize();
    // Инициализируем мощный процессор голосовых команд
    _voiceProcessor.init();
    await _applyTtsSettings();
    await PersonalityService.load();
    await _loadPrefs();
    await HabitMemoryService.load();
    await RelationshipService.load();
    await AssistantMoodService.load();
    await _loadChatHistory();
    _sendGreeting();
    // Init Telegram Bot
    TelegramBotService.onSecurityCommand = (text, chatId) async {
      return await DeviceSecurityService.handleTelegramCommand(text, chatId);
    };
        TelegramBotService.onMessage = (text, from) async {
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
        );
        return reply.replaceAll(RegExp(r'\[ACTION:[^\]]+\]'), '').trim();
      } catch (e) {
        return 'Что-то пошло не так, попробуй ещё раз';
      }
    };
    bool botEnabled = false;
    try { botEnabled = await TelegramBotService.isEnabled(); } catch (e) { debugPrint('[Init] TelegramBot isEnabled failed: $e'); }
    if (botEnabled) {
      try { await TelegramBotService.start(); } catch (e) { debugPrint('[Init] TelegramBot start failed: $e'); }
    }

    FocusModeService.onMessage = (msg) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: msg,
        timestamp: DateTime.now(),
      ));
      _speak(msg);
    };
    try { await _recheckOverlayPermission(); } catch (e) { debugPrint('[Init] overlay permission failed: $e'); }
    try { await _recheckAccessibilityPermission(); } catch (e) { debugPrint('[Init] accessibility failed: $e'); }
    try { await _initNotifications(); } catch (e) { debugPrint('[Init] notifications failed: $e'); }
    try { _startMusicPolling(); } catch (e) { debugPrint('[Init] music polling failed: $e'); }
    try { _resetIdleTimer(); } catch (e) { debugPrint('[Init] idle timer failed: $e'); }
    // Инициализируем новые сервисы
    try { await _reminderService.initialize(); } catch (e) { debugPrint('[Init] ReminderService failed: $e'); }
    try { await _convHistory.initialize(); } catch (e) { debugPrint('[Init] ConversationHistory failed: $e'); }
    try { await _alarmService.initialize(); } catch (e) { debugPrint('[Init] AlarmService failed: $e'); }

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
    try { await SmartAlarmService.initialize(); } catch (e) { debugPrint('[Init] SmartAlarmService failed: $e'); }

    // Notification reader — озвучивать + предлагать ответить
    NotificationReaderService.onSpeak = (text) async {
      await _speak(text);
      return text;
    };
    NotificationReaderService.onOverlayState = (state) {
      OverlayService().asyncState(state);
    };
    NotificationReaderService.onSuggestReply = (appName, sender, text) async {
      if (!mounted) return null;
      // Предлагаем ответить — добавляем в чат
      final prompt = 'Пришло сообщение от $sender в $appName: "$text". Хочешь я предложу ответ?';
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: prompt,
        timestamp: DateTime.now(),
      ));
      await _speak(prompt);
      // Сохраняем ожидание ответа
      setState(() {
        _pendingReplyNotif = {'pkg': '', 'title': sender, 'text': text, 'app': appName};
        _awaitingReplyConfirm = true;
      });
      return null;
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
        content: '⏰ $text',
        timestamp: DateTime.now(),
      ));
      _speak(text);
    };
    _moodService.setIdle();

    // Подписываемся на изменения настроения → обновляем оверлей
    _moodService.moodStream.listen((mood) {
      final state = _moodToOverlayState(mood);
      OverlayService().asyncState(state);
    });
    // Автозапуск постоянного прослушивания wake word
    Future.delayed(const Duration(seconds: 1), _autoStartWakeWord);

    // Загружаем состояние эмоций Айки и запускаем таймеры обиды
    try { await AikaFeelingsService.load(); } catch (e) { debugPrint('[Init] AikaFeelingsService failed: $e'); }
    try { await AikaAutomationService.loadLearned(); } catch (e) { debugPrint('[Init] AikaAutomationService failed: $e'); }
    try { await AikaSelfLearningService.load(); } catch (e) { debugPrint('[Init] AikaSelfLearningService failed: $e'); }
    try { _startFeelingsTimers(); } catch (e) { debugPrint('[Init] feelings timers failed: $e'); }
  }

  Future<void> _autoStartWakeWord() async {
    if (_wakeWordEnabled) return;
    // Запускаем проактивные подсказки раз в 5 минут
    if (!_wakeWordService.isReady) {
      debugPrint('[MainScreen] wake word STT not ready — skipping autostart');
      return;
    }
    await _wakeWordService.startListening(() {
      if (!_isListening && !_isThinking) _onWakeWordDetected();
    });
    if (mounted) {
      setState(() => _wakeWordEnabled = true);
      _showSnack('🎤 Wake word активирован — скажи "$_assistantName"');
    }
  }

  Future<void> _recheckOverlayPermission() async {
    final has = await OverlayService().hasPermission();
    if (mounted && has != _hasOverlayPermission) {
      setState(() => _hasOverlayPermission = has);
    }
    // ФИКС: не показываем оверлей повторно, если пользователь явно его выключил
    // в настройках (overlay_enabled=false) — раньше это игнорировалось при
    // каждом resume/возврате из настроек, из-за чего оверлей "сам включался".
    final prefs = await SharedPreferences.getInstance();
    final overlayEnabled = prefs.getBool('overlay_enabled') ?? true;
    if (has && overlayEnabled && mounted) {
      await OverlayService().show(state: 'idle');
    } else if (!overlayEnabled && mounted) {
      // Оверлей выключен в настройках — убираем если он был активен
      await OverlayService().hide();
    }
    // Диалог показываем ОДИН раз за сессию, не при каждом resume
    if (!has && mounted && !_overlayDialogShown) {
      _overlayDialogShown = true;
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_hasOverlayPermission) _showOverlayPermissionDialog();
      });
    }
  }

  /// Пробует до 5 раз с интервалом 1 сек — сервис может стартовать с задержкой
  Future<void> _recheckAccessibilityWithRetry() async {
    for (int attempt = 0; attempt < 5; attempt++) {
      await Future.delayed(Duration(seconds: attempt == 0 ? 0 : 1));
      if (!mounted) return;
      final has = await ScreenWatcherService.isAccessibilityEnabled();
      if (has) {
        if (mounted) setState(() => _hasAccessibilityPermission = true);
        // Запускаем watcher если ещё не запущен
        ScreenWatcherService.startWatching(
          onReaction: (reaction, overlayState) {
            if (!_screenCommentsEnabled) return;
            if (!_isListening && !_isThinking && !_isDancing && mounted) {
              _addMessage(ChatMessage(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                role: MessageRole.aika,
                content: reaction,
                timestamp: DateTime.now(),
              ));
              _speak(reaction);
              OverlayService().asyncState(overlayState);
              Future.delayed(const Duration(seconds: 4), () {
                if (mounted) OverlayService().asyncState('idle');
              });
            }
          },
        );
        debugPrint('[Accessibility] ✅ подключён (попытка ${attempt + 1})');
        return;
      }
    }
    // После 5 попыток — статус остался false, не показываем диалог повторно
    if (mounted) setState(() => _hasAccessibilityPermission = false);
  }

  Future<void> _recheckAccessibilityPermission() async {
    final has = await ScreenWatcherService.isAccessibilityEnabled();
    if (mounted) setState(() => _hasAccessibilityPermission = has);
    if (has) {
      ScreenWatcherService.startWatching(
        onReaction: (reaction, overlayState) {
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
          // Не озвучиваем сухое название — используем только reaction ниже
          if (!_screenCommentsEnabled) return;
          if (!_isListening && !_isThinking && !_isDancing) {
            _addMessage(ChatMessage(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              role: MessageRole.aika,
              content: reaction,
              timestamp: DateTime.now(),
            ));
            _speak(reaction);
            OverlayService().asyncState(overlayState);
            Future.delayed(const Duration(seconds: 4), () {
              if (mounted) OverlayService().asyncState('idle');
            });
          }
        },
      );
    } else {
      // Диалог показываем ОДИН раз за сессию
      if (!_accessibilityDialogShown) {
        _accessibilityDialogShown = true;
        // Ждём дольше — сервис может инициализироваться после запуска
        Future.delayed(const Duration(seconds: 15), () async {
          if (!mounted) return;
          // Перепроверяем актуальный статус
          final stillOff = !(await ScreenWatcherService.isAccessibilityEnabled());
          if (mounted && stillOff) _showAccessibilityDialog();
        });
      }
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
      // Диалог ОДИН раз, через 12 сек (после overlay и accessibility диалогов)
      if (!_notifDialogShown) {
        _notifDialogShown = true;
        Future.delayed(const Duration(seconds: 12), () {
          if (mounted && !_hasNotifPermission) _showNotifPermissionDialog();
        });
      }
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
              OverlayService().requestPermission();
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
      // ФИКС: проверяем, что распознаватель речи реально готов (разрешение
      // на микрофон есть) — раньше кнопка включалась визуально, даже если
      // STT не смог инициализироваться, что выглядело как "сам выключается".
      if (!_wakeWordService.isReady) {
        _showSnack('⚠️ Нет доступа к микрофону — проверь разрешения');
        return;
      }
      await _wakeWordService.startListening(() {
        if (!_isListening && !_isThinking) _onWakeWordDetected();
      });
      setState(() => _wakeWordEnabled = true);
      _showSnack('Скажи "$_assistantName" чтобы активировать');
    }
  }

  Future<void> _onWakeWordDetected() async {
    _resetIdleTimer();
    // Wake word уже остановил свой STT при срабатывании (disarm).
    // Чат-STT подключается на своём экземпляре — без конфликтов.
    await OverlayService().show(state: 'listening');
    await _speak('Да?');
    setState(() => _isListening = true);
    await _pingSound.pingStart();
    await _speechService.startListening(
      (text) async {
        try {
        // Авто-сообщения отключены

        // Авто-реакции и авто-сообщения отключены
        setState(() => _isListening = false);
        OverlayService().asyncState('thinking');
        if (text.isNotEmpty) await _sendMessage(text);
        OverlayService().asyncState('idle');
        } catch (e) {
          debugPrint('[WakeWord] callback error: $e');
          setState(() => _isListening = false);
          OverlayService().asyncState('idle');
        } finally {
          // ВСЕГДА перезапускаем wake word — даже если _sendMessage упал
          if (_wakeWordEnabled) await _wakeWordService.rearm();
        }
      },

    );
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPersonality = prefs.getString('aika_personality') ?? 'kawaii';
    setState(() {
      String? savedName = prefs.getString('assistant_name');
      // Если имя не задано вручную — берём из персонажа
      if (savedName == null || savedName.isEmpty || savedName == 'Aivora' || savedName == 'Aika') {
        switch (savedPersonality) {
          case 'sage': savedName = 'Джарвис'; break;
          case 'gabimaru': savedName = 'Габимару'; break;
          case 'kitsune': savedName = 'Китсунэ'; break;
          default: savedName = 'Айка'; break;
        }
      }
      _assistantName = savedName;
      _userName = prefs.getString('user_name') ?? '';
      _bgPresetId = prefs.getString('bg_preset_id') ?? 'none';
      _bgCustomImage = prefs.getString('bg_custom_image');
    });
    // Синхронизируем имя ассистента с wake-word триггерами
    if (!prefs.containsKey('assistant_name') || (prefs.getString('assistant_name') ?? '').isEmpty) {
      // Сохраняем авто-имя чтобы wake word его подхватил
      await prefs.setString('assistant_name', _assistantName);
    }
    await _wakeWordService.updateTriggers();
    // Восстанавливаем историю чата из памяти
    final savedHistory = await _memoryService.getHistory();
    if (savedHistory.isNotEmpty && _messages.isEmpty) {
      final restored = <ChatMessage>[];
      for (final h in savedHistory) {
        if (h.startsWith('user: ')) {
          restored.add(ChatMessage(
            id: '\${DateTime.now().millisecondsSinceEpoch}\${h.hashCode}',
            content: h.substring(6),
            role: MessageRole.user,
            timestamp: DateTime.now(),
          ));
        } else if (h.startsWith('assistant: ')) {
          restored.add(ChatMessage(
            id: '\${DateTime.now().millisecondsSinceEpoch + 1}\${h.hashCode}',
            content: h.substring(11),
            role: MessageRole.aika,
            timestamp: DateTime.now(),
          ));
        }
      }
      if (restored.isNotEmpty && mounted) {
        setState(() => _messages = restored);
      }
    }
  }

  Future<void> _applyTtsSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await _tts.setSpeechRate(prefs.getDouble('tts_rate') ?? 0.5);

    // Initialize EdgeTTS (Microsoft Neural Voices)
    await _edgeTts.initialize();
    final savedVoice = prefs.getString('edge_voice');
    if (savedVoice != null) _edgeTts.setVoice(savedVoice);
    // ── Загружаем выбранный TTS движок ──
    final ttsEngine = prefs.getString('tts_engine') ?? 'edge';
    _edgeTts.setTtsEngine(ttsEngine);
    // Инициализируем ElevenLabs если выбран
    if (ttsEngine == 'elevenlabs') {
      await ElevenLabsTtsService().initialize();
      _useEdgeTts = true; // Маршрутизация через EdgeTtsService.speak()
    } else if (ttsEngine == 'edge') {
      _useEdgeTts = true;
    } else {
      // system — используем системный TTS напрямую
      _useEdgeTts = false;
    }
    await _tts.setPitch(prefs.getDouble('tts_pitch') ?? 1.0);
    await _tts.setVolume(prefs.getDouble('tts_volume') ?? 1.0);
    final voice = prefs.getString('tts_voice');
    if (voice != null) await _tts.setVoice({'name': voice, 'locale': 'ru-RU'});
  }


  /// Сбрасывает таймер бездействия. Вызывается после каждого действия.
  /// Парсит команду вида "напиши [контакту] в [приложение] [текст]"
  Map<String, String>? _parseSendMessageCommand(String text) {
    final t = text.toLowerCase().trim();

    // Ключевые слова отправки
    final sendWords = ['напиши', 'отправь', 'написать', 'отправить',
                       'send', 'напиши сообщение', 'отправь сообщение'];
    if (!sendWords.any((w) => t.contains(w))) return null;
    // Guard: нужно явное приложение ИЛИ имя с большой буквы
    final hasAppMention = t.contains('телеграм') || t.contains('telegram') || t.contains('тг') ||
        t.contains('ватсап') || t.contains('вацап') || t.contains('whatsapp') || t.contains('вотсап') ||
        t.contains('инстаграм') || t.contains('instagram') || t.contains('вконтакте') || t.contains('вк');
    final hasCapitalContact = RegExp(r'(?:напиши|отправь)\s+[А-ЯЁ][а-яё]+').hasMatch(text);
    if (!hasAppMention && !hasCapitalContact) return null;

    // Определяем приложение
    String app = 'whatsapp'; // дефолт
    if (t.contains('телеграм') || t.contains('telegram') || t.contains('тг')) {
      app = 'telegram';
    } else if (t.contains('инстаграм') || t.contains('instagram') || t.contains('инста')) {
      app = 'instagram';
    } else if (t.contains('вконтакте') || t.contains('вк') || t.contains('vk')) {
      app = 'vkontakte';
    } else if (t.contains('ватсап') || t.contains('вацап') || t.contains('whatsapp') || t.contains('вотсап')) {
      app = 'whatsapp';
    }

    // Паттерны для извлечения контакта и текста:
    // "напиши Диме в ватсап привет как дела"
    // "напиши в телеграм Маше привет"
    // "отправь сообщение Пете привет"

    final patterns = [
      // напиши [контакт] в [приложение] [текст]
      RegExp(r'(?:напиши|отправь|скажи|написать|отправить)\s+([а-яёА-ЯЁa-zA-Z]+(?:\s+[а-яёА-ЯЁa-zA-Z]+)?)\s+(?:в|через)\s+(?:ватсап|вацап|вотсап|whatsapp|телеграм|telegram|тг|инстаграм|instagram|вконтакте|вк)\s+(.+)', caseSensitive: false),
      // напиши в [приложение] [контакт] [текст]
      RegExp(r'(?:напиши|отправь|скажи)\s+(?:в|через)\s+(?:ватсап|вацап|вотсап|whatsapp|телеграм|telegram|тг)\s+([а-яёА-ЯЁa-zA-Z]+)\s+(.+)', caseSensitive: false),
      // напиши [ИМЯ с большой] [текст]
      RegExp(r'(?:напиши|отправь)\s+([А-ЯЁ][а-яё]{1,15})\s+(.{5,})'),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(text);
      if (m != null) {
        final contact = m.group(1)?.trim() ?? '';
        final message = m.group(2)?.trim() ?? '';
        if (contact.isNotEmpty && message.isNotEmpty && message.length > 2) {
          // Исключаем служебные слова как "контакт"
          final skipWords = ['сообщение', 'message', 'текст', 'мне', 'ему', 'ей', 'им', 'нам', 'пожалуйста', 'просто', 'тоже', 'сейчас', 'ещё'];
          if (skipWords.any((w) => contact.toLowerCase() == w)) continue;
          return {'app': app, 'contact': contact, 'message': message};
        }
      }
    }
    return null;
  }

  String _appDisplayName(String app) {
    switch (app) {
      case 'whatsapp':   return 'WhatsApp';
      case 'telegram':   return 'Telegram';
      case 'instagram':  return 'Instagram';
      case 'vkontakte':  return 'ВКонтакте';
      default:           return app;
    }
  }

  void _startFeelingsTimers() {
    final personality = PersonalityService.current.name;
    AikaFeelingsService.startIdleTimers(
      personality: personality,
      onMessage: (msg) {
        if (!mounted || _isListening || _isThinking) return;
        _addMessage(ChatMessage(
          id: 'feeling_\${DateTime.now().millisecondsSinceEpoch}',
          role: MessageRole.aika,
          content: msg,
          timestamp: DateTime.now(),
        ));
        _speak(msg);
        OverlayService().asyncState('greeting');
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) OverlayService().asyncState('idle');
        });
      },
    );
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (mounted && _isStretching) {
      setState(() => _isStretching = false);
      OverlayService().asyncState('idle');
    }
    _idleTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_isListening && !_isThinking && !_isDancing) {
        setState(() => _isStretching = true);
        OverlayService().asyncState('stretch');
        // Через 3 секунды возвращаемся в idle
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() => _isStretching = false);
            OverlayService().asyncState('idle');
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
          OverlayService().asyncState('dance');
        }
        // Музыка играет — wake word НЕ глушим (музыка не использует микрофон)
        _wakeWordService.setMusicPlaying(true);
      } else {
        if (_isDancing) {
          if (mounted) setState(() => _isDancing = false);
          OverlayService().asyncState('idle');
        }
        _wakeWordService.setMusicPlaying(false);
      }
    });
  }


  void _sendGreeting() {
    // Если уже есть история — не добавляем приветствие заново
    if (_messages.isNotEmpty) {
      OverlayService().show(state: 'idle');
      return;
    }
    final greeting = _userName.isNotEmpty
        ? "Привет, $_userName! Я $_assistantName. Чем могу помочь?"
        : "Привет! Я $_assistantName. Чем могу помочь?";
    _addMessage(ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.aika,
      content: greeting,
      timestamp: DateTime.now(),
    ));
    _speak(greeting);
    OverlayService().show(state: 'greeting');
  }


  Future<void> _loadChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('chat_history');
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        final loaded = list.map((m) => ChatMessage.fromJson(m)).toList();
        if (mounted) setState(() => _messages = loaded);
      }
    } catch (_) {}
  }

  void _addMessage(ChatMessage msg) {
    setState(() {
      _messages.add(msg);
      if (msg.role == MessageRole.aika) {
        _currentChips = _suggestionsService.getSuggestionsForResponse(msg.content);
        _convHistory.addAssistant(msg.content);
      } else {
        _convHistory.addUser(msg.content);
        _currentChips = [];
      }
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
    // Сохраняем историю в SharedPreferences под ключом 'chat_history'
    // чтобы ChatHistoryScreen мог её прочитать
    _persistHistory();
  }

  Future<void> _persistHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Храним последние 200 сообщений
      final toSave = _messages.length > 200
          ? _messages.sublist(_messages.length - 200)
          : _messages;
      final encoded = jsonEncode(toSave.map((m) => m.toJson()).toList());
      await prefs.setString('chat_history', encoded);
    } catch (_) {}
  }

  Future<void> _speak(String text) async {
    final clean = text.replaceAll(RegExp(r'\[ACTION:[^\]]+\]'), '').trim();
    if (clean.isEmpty) return;
    OverlayService().asyncState('talking');

    // Останавливаем предыдущий TTS
    await _tts.stop();
    await _edgeTts.stop();
    _ttsCompleter?.complete();
    _ttsCompleter = null;

    // Wake word НЕ останавливаем — suppress подавляет триггеры (TTS echo)
    _wakeWordService.suppress((clean.length ~/ 8) + 3);

    // ── Пробуем EdgeTTS (Microsoft Neural Voice) ──
    if (_useEdgeTts) {
      try {
        // speak() блокируется до конца воспроизведения — не нужен busy-loop
        await _edgeTts.speak(clean);
        OverlayService().asyncState('idle');
        // Wake word не останавливался — suppress уже активен
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
      OverlayService().asyncState('idle');
    }

    // Wake word не останавливался — ничего не делаем
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
    OverlayService().asyncState('greeting');

    final result = await MessageSenderService.sendMessage(
      app: cmd.app,
      contact: cmd.contact,
      message: cmd.message,
    );

    Future.delayed(const Duration(seconds: 2), () => OverlayService().asyncState('idle'));
    return reply;
  }

  /// Запускаем танец — вызывается из sendMessage если команда "танцуй"
  void _startDance() {
    if (_isListening || _isThinking) return;
    setState(() => _isDancing = true);
    OverlayService().asyncState('dance');
  }

  void _stopDance() {
    if (!_isDancing) return;
    setState(() => _isDancing = false);
    OverlayService().asyncState('idle');
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _textController.clear();
    _resetIdleTimer();
    // Показываем сообщение пользователя немедленно
    _addMessage(ChatMessage(
      id: 'u${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
    ));

    // ── Обработка IMAGE_GENERATED от browser service ─────────────────
    if (text.startsWith('[IMAGE_GENERATED]')) {
      final b64 = text.substring('[IMAGE_GENERATED]'.length);
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: '[image]$b64',
        timestamp: DateTime.now(),
      ));
      return;
    }

    // ── Мощный процессор голосовых команд (150+ команд, без AI) ───────────
    final voiceResult = await _voiceProcessor.process(text);
    if (voiceResult != null) {
      final reply = voiceResult.message;
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: reply,
        timestamp: DateTime.now(),
      ));
      await _speak(reply);
      // Специальные действия от процессора
      if (voiceResult.action == 'dance') {
        setState(() => _isDancing = true);
        OverlayService().asyncState('dance');
        await Future.delayed(const Duration(seconds: 4));
        if (mounted) { setState(() => _isDancing = false); OverlayService().asyncState('idle'); }
      }
      return;
    }

    // ── Управление телефоном по голосу (legacy PhoneControlService) ────────
    final phoneResult = await _phoneControl.parseCommand(text);
    if (phoneResult != null) {
      final reply = phoneResult.message;
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: reply,
        timestamp: DateTime.now(),
      ));
      await _speak(reply);
      return;
    }

    // ── Список покупок / дел (vasisualy-inspired) ──────────────────────────
    final shopResult = await _shoplistService.parseCommand(text);
    if (shopResult != null) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: shopResult,
        timestamp: DateTime.now(),
      ));
      await _speak(shopResult);
      return;
    }

    // ── Буфер обмена (openclaw-inspired) ───────────────────────────────────
    final clipResult = await _clipboardService.parseCommand(text);
    if (clipResult != null) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: clipResult,
        timestamp: DateTime.now(),
      ));
      await _speak(clipResult);
      return;
    }

    // ── Контакты (openclaw-inspired) ───────────────────────────────────────
    final contactResult = await _contactsService.parseCommand(text);
    if (contactResult != null) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: contactResult,
        timestamp: DateTime.now(),
      ));
      await _speak(contactResult);
      return;
    }

    // ── Календарь (openclaw-inspired) ──────────────────────────────────────
    final calResult = await _calendarService.parseCommand(text);
    if (calResult != null) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: calResult,
        timestamp: DateTime.now(),
      ));
      await _speak(calResult);
      return;
    }

    // ── Шагомер (openclaw MotionHandler) ───────────────────────────────────
    final stepResult = await _stepCounter.parseCommand(text);
    if (stepResult != null) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: stepResult,
        timestamp: DateTime.now(),
      ));
      await _speak(stepResult);
      return;
    }

        // ── Управление музыкой ───────────────────────────────────────────────
    final musicCmd = MusicControlService.parseCommand(text);
    if (musicCmd != null) {
      await MusicControlService.send(musicCmd);
      final overlayService = OverlayService();
      if (musicCmd == 'play') {
        await overlayService.setMusicPlaying(true);
      } else if (musicCmd == 'pause' || musicCmd == 'stop') {
        await overlayService.setMusicPlaying(false);
      } else if (musicCmd == 'next' || musicCmd == 'previous') {
        await overlayService.playAnimation('SambaDance');
      }
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

    // ── Команды безопасности (голос) ─────────────────────────────────────
    if (DeviceSecurityService.isSecurityVoiceCommand(text)) {
      
      setState(() { _isThinking = true; });
    OverlayService().asyncState('thinking');
      try {
        final secReply = await DeviceSecurityService.handleVoiceSecurityCommand(text);
        if (secReply.isNotEmpty) {
          _addMessage(ChatMessage(
            id: (DateTime.now().millisecondsSinceEpoch+1).toString(),
            role: MessageRole.aika,
            content: secReply,
            timestamp: DateTime.now(),
          ));
          await _speak(secReply.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('📍','').replaceAll('🔒',''));
          return;
        }
      } finally {
        setState(() { _isThinking = false; });
      }
    }

        // ── Погода — открываем свой экран ──────────────────────────────────
    if (WeatherService.isWeatherRequest(text)) {
      
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const WeatherScreen()));
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
          final aiReply = await _aiService.sendMessage(
          'Составь короткий вежливый ответ на сообщение: "${notif['title']}: ${notif['text']}"',
          userName: ctx['userName'] ?? '',
          assistantName: ctx['assistantName'] ?? _assistantName,
          history: history,
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
            _addMessage(ChatMessage(id: (DateTime.now().millisecondsSinceEpoch + 1).toString(), role: MessageRole.aika, content: prompt, timestamp: DateTime.now()));
      await _speak('Ответить в $appName на это сообщение?');
      return;
    }

    // ── Мини-игры голосом ──
    final gameResult = _gameService.tryHandleGame(text);
    if (gameResult != null) {
      
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
            _addMessage(ChatMessage(id: (DateTime.now().millisecondsSinceEpoch+1).toString(), role: MessageRole.aika, content: notifReaderResult, timestamp: DateTime.now()));
      await _speak(notifReaderResult);
      return;
    }

    // ── Умный будильник ──
    final smartAlarmResult = await SmartAlarmService.tryParseCommand(text);
    if (smartAlarmResult != null) {
            _addMessage(ChatMessage(id: (DateTime.now().millisecondsSinceEpoch+1).toString(), role: MessageRole.aika, content: smartAlarmResult, timestamp: DateTime.now()));
      await _speak(smartAlarmResult);
      return;
    }

    // ── Будильник ──
    final alarmResult = await _alarmService.tryParseAlarm(text);
    if (alarmResult != null) {
      
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

    // ── РЕЖИМ ОБЩЕНИЯ: в режиме чата пропускаем все команды → чистый AI ──
    if (_chatMode) {
      setState(() { _isThinking = true; });
      try {
        final resp = await _aiService.sendMessage(
          text,
          userName: _userName,
          assistantName: _assistantName,
          history: _messages.map((m) => '\${m.role.name}: \${m.content}').toList(),
        );
        _addMessage(ChatMessage(
          id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
          role: MessageRole.aika,
          content: resp,
          timestamp: DateTime.now(),
        ));
        await _speak(resp);
        _moodService.onUserSpoke();
      } finally {
        setState(() { _isThinking = false; });
      }
      return;
    }

    // ── Утренний брифинг ──
    if (_briefingService.isBriefingRequest(text)) {
      setState(() { _isThinking = true; });
      try {
        final briefing = await _briefingService.getMorningBriefing();
        
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
            _addMessage(ChatMessage(id: (DateTime.now().millisecondsSinceEpoch+1).toString(), role: MessageRole.aika, content: addEventResult, timestamp: DateTime.now()));
      await _speak(addEventResult);
      _moodService.onUserSpoke();
      return;
    }
    if (_scheduleService.isScheduleRequest(text)) {
      final tl = text.toLowerCase();
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
            _addMessage(ChatMessage(id: (DateTime.now().millisecondsSinceEpoch + 1).toString(), role: MessageRole.aika, content: gameMusicResult, timestamp: DateTime.now()));
      await _speak(gameMusicResult);
      return;
    }

    // ── Новости ──
    final newsResult = await _newsService.tryParseNews(text);
    if (newsResult != null) {
      
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

    // ── Реакция на возврат / комплимент (AikaFeelings) ─────────────────
    final feelingReaction = await AikaFeelingsService.onUserMessage(
        PersonalityService.current.name);
    if (feelingReaction != null && mounted) {
      _addMessage(ChatMessage(
        id: 'feel_\${DateTime.now().millisecondsSinceEpoch}',
        role: MessageRole.aika,
        content: feelingReaction,
        timestamp: DateTime.now(),
      ));
      await _speak(feelingReaction);
    }
    // Перезапускаем таймеры обиды после каждого сообщения
    _startFeelingsTimers();

    // Проверяем комплимент
    if (AikaFeelingsService.isCompliment(text)) {
      final cReaction = await AikaFeelingsService.onCompliment(
          PersonalityService.current.name);
      if (cReaction != null && mounted) {
        _addMessage(ChatMessage(
          id: 'compl_\${DateTime.now().millisecondsSinceEpoch}',
          role: MessageRole.aika,
          content: cReaction,
          timestamp: DateTime.now(),
        ));
        await _speak(cReaction);
        _moodService.onUserSpoke();
        return;
      }
    }

    // ── Браузер: поиск, сайты, генерация текста/изображений ──────────────
    if (AikaBrowserService.isBrowserCommand(text)) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.user, content: text, timestamp: DateTime.now(),
      ));
      setState(() => _isThinking = true);
      final browserResult = await AikaBrowserService.execute(text);
      setState(() => _isThinking = false);
      // Обработка сгенерированного изображения
      if (browserResult.startsWith('[IMAGE_GENERATED]')) {
        final msg = 'Изображение сгенерировано! 🎨';
        _addMessage(ChatMessage(
          id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
          role: MessageRole.aika, content: msg, timestamp: DateTime.now(),
        ));
        await _speak(msg);
      } else {
        _addMessage(ChatMessage(
          id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
          role: MessageRole.aika, content: browserResult, timestamp: DateTime.now(),
        ));
        await _speak(browserResult);
      }
      AikaSelfLearningService.recordAction(type: 'command', value: text);
      _moodService.onUserSpoke();
      return;
    }

    // ── Игровой помощник ────────────────────────────────────────────────
    if (AikaGameHelperService.isGameCommand(text)) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.user, content: text, timestamp: DateTime.now(),
      ));
      setState(() => _isThinking = true);
      final gameResult = await AikaGameHelperService.execute(
        text,
        onAlert: (alert) {
          if (!mounted) return;
          _addMessage(ChatMessage(
            id: 'game_\${DateTime.now().millisecondsSinceEpoch}',
            role: MessageRole.aika, content: alert, timestamp: DateTime.now(),
          ));
          _speak(alert);
        },
        currentApp: ScreenWatcherService.currentPackage,
      );
      setState(() => _isThinking = false);
      _addMessage(ChatMessage(
        id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
        role: MessageRole.aika, content: gameResult, timestamp: DateTime.now(),
      ));
      await _speak(gameResult);
      AikaSelfLearningService.recordAction(type: 'command', value: text);
      _moodService.onUserSpoke();
      return;
    }

    // ── Automation: скриншот, поиск в приложении, игра, самообучение ──────
    if (AikaAutomationService.isAutomationCommand(text)) {
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.user, content: text, timestamp: DateTime.now(),
      ));
      setState(() => _isThinking = true);
      final autoResult = await AikaAutomationService.execute(
        text,
        onGameAlert: (alert) {
          if (!mounted) return;
          _addMessage(ChatMessage(
            id: 'game_\${DateTime.now().millisecondsSinceEpoch}',
            role: MessageRole.aika, content: alert, timestamp: DateTime.now(),
          ));
          _speak(alert);
        },
      );
      setState(() => _isThinking = false);
      _addMessage(ChatMessage(
        id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
        role: MessageRole.aika, content: autoResult, timestamp: DateTime.now(),
      ));
      await _speak(autoResult);
      _moodService.onUserSpoke();
      return;
    }

    // ── Медиа-команды (Spotify, play/pause/next) ────────────────────────
    final mediaResult = await MediaControlService.tryHandleCommand(text);
    if (mediaResult != null) {
      
      _addMessage(ChatMessage(
        id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
        role: MessageRole.aika,
        content: mediaResult,
        timestamp: DateTime.now(),
      ));
      await _speak(mediaResult);
      return;
    }

    // ── Отправка сообщений ("напиши Диме в ватсап ...") ─────────────────
    final msgResult = _parseSendMessageCommand(text);
    if (msgResult != null) {
      
      final r = await MessageSenderService.sendMessage(
        app: msgResult['app']!,
        contact: msgResult['contact']!,
        message: msgResult['message']!,
      );
      final reply = 'Отправляю "${msgResult['message']}" → ${msgResult['contact']} в ${_appDisplayName(msgResult['app']!)} 📨';
      _addMessage(ChatMessage(
        id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
        role: MessageRole.aika,
        content: reply,
        timestamp: DateTime.now(),
      ));
      await _speak(reply);
      return;
    }

    // ── Сначала проверяем локальные команды запуска приложений ──
    final appLaunchResult = await AppLauncherService.tryLaunch(text);
    if (appLaunchResult != null) {
      AikaSelfLearningService.recordAction(type: 'command', value: text);
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

    
    setState(() { _isThinking = true; _isDancing = false; });
    OverlayService().asyncState('thinking');

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


    // ── Умное управление экраном через ScreenCommandService ──────────────
    if (ScreenCommandService.isScreenCommand(text)) {
      final cmdResult = await ScreenCommandService.execute(text);
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: cmdResult,
        timestamp: DateTime.now(),
      ));
      setState(() => _isThinking = false);
      await _speak(cmdResult);
      return;
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
      final longMemory  = context['longMemory'] ?? '';
      final screenCtx   = ScreenWatcherService.currentLabel.isNotEmpty
          ? 'Сейчас на экране: \${ScreenWatcherService.currentLabel} (\${ScreenWatcherService.currentPackage})'
          : '';
      final _prefs = await SharedPreferences.getInstance();
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
        content: 'Что-то пошло не так 😔 Попробуй ещё раз',
        timestamp: DateTime.now(),
      ));
    } finally {
      setState(() => _isThinking = false);
      OverlayService().asyncState('idle');
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speechService.stopListening();
      setState(() => _isListening = false);
      OverlayService().asyncState('idle');
      if (_wakeWordEnabled) await _wakeWordService.rearm();
    } else {
      await _wakeWordService.disarm();
      setState(() { _isListening = true; _isDancing = false; });
      OverlayService().asyncState('listening');
      await _speechService.startListening(
        (text) async {
          try {
            setState(() => _isListening = false);
            OverlayService().asyncState('idle');
            if (text.isNotEmpty) await _sendMessage(text);
          } catch (e) {
            debugPrint('[VoiceBtn] callback error: $e');
            setState(() => _isListening = false);
            OverlayService().asyncState('idle');
          } finally {
            if (_wakeWordEnabled) await _wakeWordService.rearm();
          }
        },
      );
    }
  }

  Future<void> _openCurrency() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CurrencyScreen()));
  }

  Future<void> _openSettings() async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    // ФИКС: если история чата была очищена на экране "История чата" (внутри
    // Настроек), очищаем и наш локальный список сообщений, иначе следующее
    // сообщение пересохранит старую историю обратно в SharedPreferences.
    if (result == true && mounted) {
      setState(() { _messages = []; _convHistory.clear(); });
    }
    await _loadPrefs();
    await _applyTtsSettings();
    _wakeWordService.updateTriggers();
    await _recheckOverlayPermission();
  }

  Future<void> _checkProactiveSuggestions() async {
    // Авто-сообщения отключены — Айка ничего не отправляет сама
  }

  Future<void> _openModelPicker() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => const ModelPickerScreen(),
    ));
    // ФИКС: модель менялась только в оверлее, в чате не обновлялась без
    // перезапуска — пересоздаём виджет новым Key, чтобы он перечитал prefs.
    if (mounted) setState(() => _live2dKey = UniqueKey());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _textController.dispose();
    _tts.stop();
    _musicTimer?.cancel();
    _idleTimer?.cancel();
    AikaFeelingsService.stopIdleTimers();
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
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // ── Фон + Live2D аватар на весь экран ──────────────────────
          Positioned.fill(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Фон
                if (_bgPresetId == 'custom' && _bgCustomImage != null)
                  Image.file(File(_bgCustomImage!), fit: BoxFit.cover)
                else if (_bgPresetId != 'none')
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _bgGradient(_bgPresetId),
                      ),
                    ),
                  ),
                // Аватар — Live2D
                    Live2DWidget(
                      key: _live2dKey,
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.height,
                      state: _avatarStateString,
                    ),
              ],
            ),
          ),

          // ── Тёмный градиент снизу для читаемости чата ──────────────────
          Positioned(
            left: 0, right: 0, bottom: 0,
            height: MediaQuery.of(context).size.height * 0.55,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                    Colors.black.withOpacity(0.92),
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),

          // ── Верхняя панель ──────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    // Имя ассистента
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _assistantName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          if (_userName.isNotEmpty)
                            Text(
                              "Привет, $_userName",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.55),
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Wake word
                    _TopIconBtn(
                      icon: _wakeWordEnabled ? Icons.hearing : Icons.hearing_disabled,
                      active: _wakeWordEnabled,
                      onTap: _toggleWakeWord,
                    ),
                    _TopIconBtn(
                      icon: _chatMode ? Icons.chat_bubble_rounded : Icons.smart_toy_rounded,
                      active: _chatMode,
                      onTap: () {
                        setState(() => _chatMode = !_chatMode);
                        _showSnack(_chatMode ? '💬 Режим общения — просто разговариваем!' : '⚡ Режим команд — выполняю задачи!');
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Кнопки справа ───────────────────────────────────────────────
          Positioned(
            right: 10,
            top: 0,
            bottom: 130,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SideBtn(icon: Icons.info_outline,         onTap: () => _showAbout()),
                  _SideBtn(icon: Icons.view_in_ar,             onTap: _openModelPicker),
                  _SideBtn(icon: Icons.settings_outlined,     onTap: _openSettings),
                  _SideBtn(icon: Icons.tune,                  onTap: _openCurrency),
                ],
              ),
            ),
          ),

          // ── Чат поверх аватара (нижняя часть экрана) ───────────────────
          Positioned(
            left: 0, right: 50, bottom: 70,
            height: MediaQuery.of(context).size.height * 0.42,
            child: _messages.isEmpty
                ? const SizedBox()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) {
                      final m = _messages[i];
                      return ChatBubble(message: m);
                    },
                  ),
          ),

          // ── Suggestion chips (GA Desktop Client inspired) ───────────────
          if (_currentChips.isNotEmpty)
            Positioned(
              left: 0, right: 0, bottom: 68,
              child: SuggestionChipsWidget(
                chips: _currentChips,
                onChipTap: (query) {
                  setState(() => _currentChips = []);
                  _sendMessage(query);
                },
              ),
            ),

          // ── Индикатор "думает" ───────────────────────────────────────────
          if (_isThinking)
            Positioned(
              left: 16, bottom: 80,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AikaTheme.neonBlue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text("\$_assistantName думает...",
                        style: TextStyle(color: AikaTheme.neonBlue, fontSize: 12)),
                  ],
                ),
              ),
            ),

          // ── Поле ввода снизу ────────────────────────────────────────────
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  border: Border(
                    top: BorderSide(color: Colors.white.withOpacity(0.08)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: _isListening
                                ? AikaTheme.neonBlue.withOpacity(0.8)
                                : Colors.white.withOpacity(0.12),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Превью прикреплённого фото
                            if (_pendingImagePath != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                                child: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.file(
                                        File(_pendingImagePath!),
                                        height: 80,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      top: 2, right: 2,
                                      child: GestureDetector(
                                        onTap: () => setState(() {
                                          _pendingImagePath = null;
                                          _pendingImageBase64 = null;
                                        }),
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.close, color: Colors.white, size: 14),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            // Input row: photo btn + textfield
                            Row(
                              children: [
                                IconButton(
                                  icon: Icon(Icons.image_outlined,
                                    color: _pendingImagePath != null
                                        ? AikaTheme.neonBlue
                                        : Colors.white38,
                                    size: 22),
                                  onPressed: _pickImage,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 36),
                                ),
                                // Кнопка камеры
                                IconButton(
                                  icon: Icon(Icons.camera_alt_outlined,
                                    color: _pendingImageBase64 != null
                                        ? AikaTheme.neonBlue
                                        : Colors.white38,
                                    size: 22),
                                  onPressed: _pickImageFromCamera,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 36),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _textController,
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                    decoration: InputDecoration(
                                      hintText: _isListening ? 'Слушаю...' : 'Спроси что-нибудь',
                                      hintStyle: TextStyle(
                                          color: Colors.white.withOpacity(0.35), fontSize: 13),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 10),
                                    ),
                                    onSubmitted: (t) {
                                      if (_pendingImageBase64 != null) {
                                        _sendMessageWithImage(t.trim(), _pendingImageBase64!);
                                      } else if (t.trim().isNotEmpty) {
                                        _sendMessage(t.trim());
                                      }
                                    },
                                    onChanged: (_) => setState(() {}),
                                    maxLines: 1,
                                    textInputAction: TextInputAction.send,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                                        const SizedBox(width: 8),
                    // Mic button
                    GestureDetector(
                      onTap: _toggleListening,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isListening
                              ? AikaTheme.neonPink.withOpacity(0.9)
                              : Colors.white.withOpacity(0.12),
                          border: Border.all(
                            color: _isListening
                                ? AikaTheme.neonPink
                                : Colors.white.withOpacity(0.2),
                          ),
                        ),
                        child: Icon(
                          _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Send button
                    GestureDetector(
                      onTap: () {
                        final t = _textController.text.trim();
                        if (_pendingImageBase64 != null) {
                          _sendMessageWithImage(t, _pendingImageBase64!);
                        } else if (t.isNotEmpty) {
                          _sendMessage(t);
                        }
                      },
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _textController.text.trim().isNotEmpty
                              ? AikaTheme.neonBlue
                              : Colors.white.withOpacity(0.08),
                        ),
                        child: Icon(
                          Icons.send_rounded,
                          color: _textController.text.trim().isNotEmpty
                              ? Colors.white
                              : Colors.white30,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AikaTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_assistantName,
            style: TextStyle(color: AikaTheme.neonBlue, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AI-ассистент на базе Groq gpt-oss-120b',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            if (_userName.isNotEmpty)
              Text("Пользователь: $_userName",
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 4),
            Text("История: ${_messages.length} сообщений",
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(color: AikaTheme.neonBlue)),
          ),
        ],
      ),
    );
  }




  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: AikaTheme.neonBlue),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AikaTheme.neonBlue.withOpacity(0.3), AikaTheme.neonPurple.withOpacity(0.3)],
              ),
            ),
            child: Icon(Icons.auto_awesome, color: AikaTheme.neonBlue, size: 36),
          ),
          const SizedBox(height: 16),
          Text(
            _userName.isNotEmpty ? "Привет, $_userName!" : "Привет!",
            style: TextStyle(color: AikaTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "Я \$_assistantName. Чем могу помочь?",
            style: TextStyle(color: AikaTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8, runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _quickChip('Какая погода?', Icons.wb_sunny_outlined),
              _quickChip('Напомни в 18:00', Icons.alarm_outlined),
              _quickChip('Открой YouTube', Icons.play_circle_outline),
              _quickChip('Курс доллара', Icons.currency_exchange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickChip(String label, IconData icon) {
    return GestureDetector(
      onTap: () => _sendMessage(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AikaTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AikaTheme.neonBlue),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
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

// ── Вспомогательные виджеты ────────────────────────────────────────────────

class _TopIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  const _TopIconBtn({required this.icon, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? AikaTheme.neonBlue.withOpacity(0.25)
              : Colors.black.withOpacity(0.45),
          border: Border.all(
            color: active
                ? AikaTheme.neonBlue.withOpacity(0.7)
                : Colors.white.withOpacity(0.18),
          ),
        ),
        child: Icon(icon,
          color: active ? AikaTheme.neonBlue : Colors.white70,
          size: 18),
      ),
    );
  }
}

class _SideBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  const _SideBtn({required this.icon, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38, height: 38,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? AikaTheme.neonBlue.withOpacity(0.25)
              : Colors.black.withOpacity(0.5),
          border: Border.all(
            color: active
                ? AikaTheme.neonBlue.withOpacity(0.6)
                : Colors.white.withOpacity(0.15),
          ),
        ),
        child: Icon(icon,
          color: active ? AikaTheme.neonBlue : Colors.white60,
          size: 17),
      ),
    );
  }
}
