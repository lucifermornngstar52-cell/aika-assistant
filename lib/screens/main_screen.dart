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
import '../widgets/aika_avatar.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/voice_button.dart';
import 'settings_screen.dart';
import '../widgets/aika_mascot.dart';

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
  final FlutterTts _tts = FlutterTts();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();

  List<ChatMessage> _messages = [];
  bool _isListening = false;
  bool _isThinking = false;
  bool _showAvatar = true;
  bool _wakeWordEnabled = false;
  String _assistantName = 'Aika';
  String _userName = '';

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initServices();
  }

  Future<void> _initServices() async {
    await _speechService.initialize();
    await _wakeWordService.initialize();
    _wakeWordService.initWithSharedStt(_speechService.sharedStt);
    await _applyTtsSettings();
    await _loadPrefs();
    _sendGreeting();
    _checkOverlayPermission();
  }

  Future<void> _checkOverlayPermission() async {
    final hasPermission = await OverlayService.hasPermission();
    if (!hasPermission && mounted) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _showOverlayPermissionDialog();
      });
    }
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
        title: Text(
          'Разрешение на оверлей',
          style: TextStyle(color: AikaTheme.neonBlue, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Разрешить Айке показывать окно поверх других приложений? Это нужно для работы в фоне и wake-word.',
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
        if (!_isListening && !_isThinking) {
          _onWakeWordDetected();
        }
      });
      setState(() => _wakeWordEnabled = true);
      _showSnack('Скажи "Айка" чтобы активировать');
    }
  }

  Future<void> _onWakeWordDetected() async {
    await OverlayService.showOverlay(message: 'Слушаю...');
    await _speak('Да?');
    setState(() => _isListening = true);
    await _speechService.startListening(
      onResult: (text) async {
        setState(() => _isListening = false);
        await OverlayService.updateOverlay(message: 'Думаю...');
        if (text.isNotEmpty) await _sendMessage(text);
        await OverlayService.hideOverlay();
      },
      onDone: () {
        setState(() => _isListening = false);
        OverlayService.hideOverlay();
      },
    );
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _assistantName = prefs.getString('assistant_name') ?? 'Aika';
      _userName = prefs.getString('user_name') ?? '';
      _showAvatar = prefs.getBool('show_avatar') ?? true;
    });
  }

  Future<void> _applyTtsSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final rate = prefs.getDouble('tts_rate') ?? 0.5;
    final pitch = prefs.getDouble('tts_pitch') ?? 1.0;
    final volume = prefs.getDouble('tts_volume') ?? 1.0;
    final voice = prefs.getString('tts_voice');
    await _tts.setSpeechRate(rate);
    await _tts.setPitch(pitch);
    await _tts.setVolume(volume);
    if (voice != null) {
      await _tts.setVoice({'name': voice, 'locale': 'ru-RU'});
    }
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

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _textController.clear();
    _addMessage(ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
    ));
    setState(() => _isThinking = true);
    await _memoryService.addMessage('user', text);

    try {
      final context = await _memoryService.getUserContext();
      final history = await _memoryService.getHistory();
      final response = await _aiService.sendMessage(
        text,
        userName: context['userName'] ?? '',
        assistantName: context['assistantName'] ?? _assistantName,
        history: history,
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
    } catch (e) {
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

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speechService.stopListening();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      await _speechService.startListening(
        onResult: (text) {
          if (text.isNotEmpty) _sendMessage(text);
        },
        onDone: () {
          setState(() => _isListening = false);
        },
      );
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    await _loadPrefs();
    await _applyTtsSettings();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scrollController.dispose();
    _textController.dispose();
    _tts.stop();
    _deviceService.dispose();
    _wakeWordService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
      backgroundColor: AikaTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _assistantName.toUpperCase(),
                        style: TextStyle(
                          color: AikaTheme.neonBlue,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                      Text(
                        _userName.isNotEmpty ? 'Привет, $_userName' : 'AI Assistant',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Wake word toggle
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
                              Icon(
                                Icons.hearing,
                                size: 14,
                                color: _wakeWordEnabled ? AikaTheme.neonBlue : Colors.white38,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _wakeWordEnabled ? 'ON' : 'OFF',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _wakeWordEnabled ? AikaTheme.neonBlue : Colors.white38,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          _showAvatar ? Icons.face : Icons.face_outlined,
                          color: _showAvatar ? AikaTheme.neonBlue : Colors.white38,
                        ),
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          setState(() => _showAvatar = !_showAvatar);
                          await prefs.setBool('show_avatar', _showAvatar);
                        },
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

            // Avatar
            if (_showAvatar)
              ScaleTransition(
                scale: _pulseAnimation,
                child: AikaAvatar(isThinking: _isThinking, isListening: _isListening),
              ),

            // Wake word status banner
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
                    Text(
                      'Жду: "Айка"',
                      style: TextStyle(
                        color: AikaTheme.neonBlue.withOpacity(0.7),
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),

            // Chat
            Expanded(
              child: _messages.isEmpty && _isThinking
                  ? Center(child: CircularProgressIndicator(color: AikaTheme.neonBlue))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (ctx, i) => ChatBubble(message: _messages[i]),
                    ),
            ),

            // Input bar
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AikaTheme.surface,
                border: Border(
                  top: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.15)),
                ),
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
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
    ),
        AikaMascot(
          onTap: () {
            // tap mascot — could trigger greeting or idle reaction
          },
        ),
      ],
    );
  }
}
