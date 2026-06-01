import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/avatar_animation_controller.dart';
import '../services/device_service.dart';
import '../services/memory_service.dart';
import '../services/music_control_service.dart';
import '../services/speech_service.dart';
import '../services/wake_word_service.dart';
import '../services/overlay_service.dart';
import '../theme/app_theme.dart';
import '../widgets/aika_3d_overlay.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/voice_button.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  final AiService _aiService = AiService();
  final DeviceService _deviceService = DeviceService();
  final MemoryService _memoryService = MemoryService();
  final SpeechService _speechService = SpeechService();
  final WakeWordService _wakeWordService = WakeWordService();
  final MusicControlService _musicService = MusicControlService();
  final FlutterTts _tts = FlutterTts();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final AvatarAnimationController _avatarCtrl = AvatarAnimationController.instance;

  List<ChatMessage> _messages = [];
  bool _isListening = false;
  bool _isThinking = false;
  bool _show3DAvatar = true;
  bool _wakeWordEnabled = false;
  bool _musicPlaying = false;
  String _assistantName = 'Aika';
  String _userName = '';

  // Таймер неактивности → sitting
  DateTime _lastInteraction = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initServices();
    _startIdleWatcher();
  }

  Future<void> _initServices() async {
    await _speechService.initialize();
    await _wakeWordService.initialize();
    await _applyTtsSettings();
    await _loadPrefs();
    _sendGreeting();
  }

  /// Следим за неактивностью — через 3 мин переходим в Sitting
  void _startIdleWatcher() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 30));
      if (!mounted) return false;
      final diff = DateTime.now().difference(_lastInteraction);
      if (diff.inMinutes >= 3) {
        _avatarCtrl.setFromEvent(AvatarAnimation.sitting);
      } else if (diff.inSeconds > 30) {
        _avatarCtrl.setFromEvent(AvatarAnimation.idle);
      }
      return true;
    });
  }

  void _touchInteraction() {
    _lastInteraction = DateTime.now();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _assistantName = prefs.getString('assistant_name') ?? 'Aika';
      _userName = prefs.getString('user_name') ?? '';
      _show3DAvatar = prefs.getBool('show_3d_avatar') ?? true;
    });
  }

  Future<void> _applyTtsSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await _tts.setSpeechRate(prefs.getDouble('tts_rate') ?? 0.5);
    await _tts.setPitch(prefs.getDouble('tts_pitch') ?? 1.0);
    await _tts.setVolume(prefs.getDouble('tts_volume') ?? 1.0);
    final voice = prefs.getString('tts_voice');
    if (voice != null) {
      await _tts.setVoice({'name': voice, 'locale': 'ru-RU'});
    }
  }

  Future<void> _toggleWakeWord() async {
    _touchInteraction();
    if (_wakeWordEnabled) {
      await _wakeWordService.stop();
      setState(() => _wakeWordEnabled = false);
    } else {
      await _wakeWordService.startListening(() {
        if (!_isListening && !_isThinking) _onWakeWordDetected();
      });
      setState(() => _wakeWordEnabled = true);
      _showSnack('Скажи "Айка" чтобы активировать');
    }
  }

  Future<void> _onWakeWordDetected() async {
    _touchInteraction();
    _avatarCtrl.setFromEvent(AvatarAnimation.wave); // 👋 Wake word → Wave
    await OverlayService.showOverlay(message: 'Слушаю...');
    await _speak('Да?');
    setState(() => _isListening = true);
    await _speechService.startListening(
      onResult: (text) async {
        setState(() => _isListening = false);
        _avatarCtrl.setFromEvent(AvatarAnimation.idle);
        await OverlayService.updateOverlay(message: 'Думаю...');
        if (text.isNotEmpty) await _sendMessage(text);
        await OverlayService.hideOverlay();
      },
      onDone: () {
        setState(() => _isListening = false);
        _avatarCtrl.setFromEvent(AvatarAnimation.idle);
        OverlayService.hideOverlay();
      },
    );
  }

  void _sendGreeting() {
    _avatarCtrl.setFromEvent(AvatarAnimation.wave); // 👋 Приветствие → Wave
    final greeting = _userName.isNotEmpty
        ? 'Привет, $_userName! Я $_assistantName. Чем могу помочь?'
        : 'Привет! Я $_assistantName. Чем могу помочь?';
    _addMessage(ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.aika,
      content: greeting,
      timestamp: DateTime.now(),
    ));
    _speak(greeting).then((_) {
      Future.delayed(const Duration(seconds: 3), () {
        _avatarCtrl.setFromEvent(AvatarAnimation.idle);
      });
    });
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AikaTheme.neonBlue.withOpacity(0.8),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _touchInteraction();
    _textController.clear();
    _addMessage(ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
    ));

    setState(() => _isThinking = true);
    _avatarCtrl.setFromEvent(AvatarAnimation.idle); // думает → idle покачивается

    await _memoryService.addMessage('user', text);
    try {
      final ctx = await _memoryService.getUserContext();
      final history = await _memoryService.getHistory();
      final response = await _aiService.sendMessage(
        text,
        userName: ctx['userName'] ?? '',
        assistantName: ctx['assistantName'] ?? _assistantName,
        history: history,
      );

      // Анализируем команды для анимации
      _handleActionAnimation(response, text);

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

      // Ответ получен → ThumbsUp на 2 сек, потом idle
      _avatarCtrl.playTemporary(AvatarAnimation.thumbsUp,
          duration: const Duration(seconds: 2));

      await _speak(finalMsg);
    } catch (e) {
      _avatarCtrl.playTemporary(AvatarAnimation.no,
          duration: const Duration(seconds: 2)); // ошибка → No
      _addMessage(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.aika,
        content: 'Ошибка: $e',
        timestamp: DateTime.now(),
      ));
    } finally {
      setState(() => _isThinking = false);
    }
  }

  /// Анализируем ответ и запрос — выбираем правильную анимацию
  void _handleActionAnimation(String response, String userText) {
    final lower = userText.toLowerCase();
    final respLower = response.toLowerCase();

    // 🎵 Музыка
    if (lower.contains('музык') || lower.contains('music') ||
        lower.contains('включи') && lower.contains('пес') ||
        respLower.contains('включаю музыку') || respLower.contains('playing music')) {
      setState(() => _musicPlaying = true);
      _avatarCtrl.setFromEvent(AvatarAnimation.dance);
      return;
    }
    if (lower.contains('стоп') || lower.contains('выключи музык') ||
        lower.contains('пауза') || lower.contains('stop music')) {
      setState(() => _musicPlaying = false);
      _avatarCtrl.setFromEvent(AvatarAnimation.idle);
      return;
    }

    // ⏰ Будильник / таймер
    if (lower.contains('будильник') || lower.contains('alarm') ||
        lower.contains('таймер') || lower.contains('напомни')) {
      _avatarCtrl.playTemporary(AvatarAnimation.jump, duration: const Duration(seconds: 3));
      return;
    }

    // ✅ Да / подтверждение
    if (respLower.contains('готово') || respLower.contains('выполнено') ||
        respLower.contains('сделано') || respLower.contains('конечно')) {
      _avatarCtrl.playTemporary(AvatarAnimation.yes, duration: const Duration(seconds: 2));
      return;
    }

    // 🚶 Навигация / переход
    if (lower.contains('открой') || lower.contains('запусти') ||
        lower.contains('перейди') || lower.contains('open')) {
      _avatarCtrl.playTemporary(AvatarAnimation.walking, duration: const Duration(seconds: 2));
      return;
    }
  }

  Future<void> _toggleListening() async {
    _touchInteraction();
    if (_isListening) {
      await _speechService.stopListening();
      setState(() => _isListening = false);
      _avatarCtrl.setFromEvent(AvatarAnimation.idle);
    } else {
      setState(() => _isListening = true);
      _avatarCtrl.setFromEvent(AvatarAnimation.wave); // слушает → Wave
      await _speechService.startListening(
        onResult: (text) {
          _avatarCtrl.setFromEvent(AvatarAnimation.idle);
          if (text.isNotEmpty) _sendMessage(text);
        },
        onDone: () {
          setState(() => _isListening = false);
          _avatarCtrl.setFromEvent(AvatarAnimation.idle);
        },
      );
    }
  }

  Future<void> _openSettings() async {
    _touchInteraction();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    await _loadPrefs();
    await _applyTtsSettings();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    _tts.stop();
    _deviceService.dispose();
    _wakeWordService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_assistantName.toUpperCase(),
                            style: TextStyle(
                                color: AikaTheme.neonBlue, fontSize: 20,
                                fontWeight: FontWeight.bold, letterSpacing: 4)),
                        Text(
                            _userName.isNotEmpty ? 'Привет, $_userName' : 'AI Assistant',
                            style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ]),
                      Row(children: [
                        // Wake word
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
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.hearing, size: 14,
                                  color: _wakeWordEnabled ? AikaTheme.neonBlue : Colors.white38),
                              const SizedBox(width: 4),
                              Text(_wakeWordEnabled ? 'ON' : 'OFF',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                                      color: _wakeWordEnabled ? AikaTheme.neonBlue : Colors.white38)),
                            ]),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Avatar toggle
                        IconButton(
                          icon: Icon(_show3DAvatar ? Icons.face : Icons.face_outlined,
                              color: _show3DAvatar ? AikaTheme.neonBlue : Colors.white38),
                          onPressed: () async {
                            final prefs = await SharedPreferences.getInstance();
                            setState(() => _show3DAvatar = !_show3DAvatar);
                            await prefs.setBool('show_3d_avatar', _show3DAvatar);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings_outlined, color: Colors.white54),
                          onPressed: _openSettings,
                        ),
                      ]),
                    ],
                  ),
                ),

                // Status bar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AikaTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isListening
                          ? AikaTheme.neonBlue.withOpacity(0.5)
                          : _isThinking
                              ? AikaTheme.neonPurple.withOpacity(0.5)
                              : Colors.white10,
                    ),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(
                      _isListening ? Icons.mic : _isThinking ? Icons.psychology : Icons.check_circle_outline,
                      size: 14,
                      color: _isListening ? AikaTheme.neonBlue : _isThinking ? AikaTheme.neonPurple : Colors.white38,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isListening ? 'Слушаю...' : _isThinking ? 'Думаю...' : 'Готова',
                      style: TextStyle(
                        color: _isListening ? AikaTheme.neonBlue : _isThinking ? AikaTheme.neonPurple : Colors.white38,
                        fontSize: 12, letterSpacing: 1,
                      ),
                    ),
                    if (_musicPlaying) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.music_note, size: 12, color: Colors.pinkAccent.withOpacity(0.8)),
                      const SizedBox(width: 4),
                      Text('музыка', style: TextStyle(color: Colors.pinkAccent.withOpacity(0.8), fontSize: 10)),
                    ],
                  ]),
                ),

                // Chat
                Expanded(
                  child: _messages.isEmpty
                      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.auto_awesome, size: 48, color: AikaTheme.neonBlue.withOpacity(0.3)),
                          const SizedBox(height: 12),
                          Text('Спроси меня о чём угодно',
                              style: TextStyle(color: Colors.white24, fontSize: 14)),
                        ]))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 8),
                          itemCount: _messages.length,
                          itemBuilder: (ctx, i) => ChatBubble(message: _messages[i]),
                        ),
                ),

                // Input
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AikaTheme.surface,
                    border: Border(top: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.15))),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        style: const TextStyle(color: Colors.white),
                        onTap: _touchInteraction,
                        decoration: InputDecoration(
                          hintText: 'Напишите или говорите...',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onSubmitted: _sendMessage,
                      ),
                    ),
                    const SizedBox(width: 8),
                    VoiceButton(isListening: _isListening, isSpeaking: false, onTap: _toggleListening),
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
                  ]),
                ),
              ],
            ),

            // 3D Avatar overlay — поверх всего
            if (_show3DAvatar) const Aika3DOverlay(),
          ],
        ),
      ),
    );
  }
}
