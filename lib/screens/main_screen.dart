import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../widgets/aika_avatar.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/voice_button.dart';
import '../services/ai_service.dart';
import '../services/speech_service.dart';
import '../services/device_service.dart';
import '../services/memory_service.dart';
import '../models/chat_message.dart';
import 'settings_screen.dart';
import 'dart:math';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final AIService _aiService = AIService();
  final DeviceService _deviceService = DeviceService();
  final MemoryService _memoryService = MemoryService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late SpeechService _speechService;

  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  AikaEmotion _emotion = AikaEmotion.idle;
  int _batteryLevel = 100;
  bool _showChat = true;

  @override
  void initState() {
    super.initState();
    _speechService = SpeechService();
    _init();
  }

  Future<void> _init() async {
    await _speechService.initialize();
    _loadHistory();
    _loadBattery();

    // Welcome message
    await Future.delayed(const Duration(milliseconds: 500));
    _addMessage(
      'Привет! Я — Айка ✨ Твой личный AI-ассистент. Скажи "Айка" или нажми на микрофон, чтобы начать!',
      MessageRole.aika,
    );
  }

  Future<void> _loadHistory() async {
    final history = await _memoryService.loadHistory();
    if (mounted && history.isNotEmpty) {
      final recent = history.length > 20 ? history.sublist(history.length - 20) : history;
      setState(() => _messages.insertAll(0, recent));
    }
  }

  Future<void> _loadBattery() async {
    try {
      final level = await _deviceService.getBatteryLevel();
      if (mounted) setState(() => _batteryLevel = level);
    } catch (_) {}
  }

  void _addMessage(String content, MessageRole role, {bool isVoice = false}) {
    final msg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      role: role,
      timestamp: DateTime.now(),
      isVoice: isVoice,
    );
    setState(() => _messages.add(msg));
    if (role != MessageRole.system) {
      _memoryService.saveMessage(msg);
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
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

  Future<void> _sendMessage(String text, {bool isVoice = false}) async {
    if (text.trim().isEmpty) return;
    _textController.clear();

    _addMessage(text, MessageRole.user, isVoice: isVoice);
    setState(() {
      _isTyping = true;
      _emotion = AikaEmotion.thinking;
    });

    try {
      final response = await _aiService.sendMessage(text);

      // Check for device action
      final actionResult = await _deviceService.parseAndExecute(response);

      setState(() {
        _isTyping = false;
        _emotion = AikaEmotion.talking;
      });

      _addMessage(response, MessageRole.aika);

      // Speak the response
      await _speechService.speak(response);

      setState(() => _emotion = AikaEmotion.idle);

      // If action was executed, optionally show result
      if (actionResult != null && actionResult.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 500));
        _addMessage('✅ $actionResult', MessageRole.aika);
      }
    } catch (e) {
      setState(() {
        _isTyping = false;
        _emotion = AikaEmotion.idle;
      });
      _addMessage('Упс, что-то пошло не так... Попробуй ещё раз?', MessageRole.aika);
    }
  }

  void _toggleListening() {
    if (_speechService.isListening) {
      _speechService.stopListening();
      setState(() => _emotion = AikaEmotion.idle);
    } else {
      setState(() => _emotion = AikaEmotion.listening);
      _speechService.startListening(
        onResult: (text) {
          if (text.isNotEmpty) {
            _sendMessage(text, isVoice: true);
          }
        },
        onDone: () => setState(() => _emotion = AikaEmotion.idle),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _speechService,
      child: Scaffold(
        backgroundColor: AikaTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              _buildAvatarSection(),
              if (_speechService.isListening) _buildListeningText(),
              _buildToggleBar(),
              Expanded(child: _buildChatSection()),
              _buildInputSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: AikaTheme.glassCard(opacity: 0.05),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AikaTheme.neonBlue,
                    boxShadow: [
                      BoxShadow(
                        color: AikaTheme.neonBlue.withOpacity(0.8),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Онлайн',
                  style: TextStyle(
                    color: AikaTheme.neonBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Time & Battery
          Text(
            '${TimeOfDay.now().format(context)} · $_batteryLevel%',
            style: const TextStyle(
              color: AikaTheme.textSecondary,
              fontSize: 12,
            ),
          ),

          const SizedBox(width: 12),

          // Settings
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SettingsScreen(aiService: _aiService)),
            ),
            child: Container(
              width: 36,
              height: 36,
              decoration: AikaTheme.glassCard(opacity: 0.05),
              child: const Icon(
                Icons.tune,
                color: AikaTheme.textSecondary,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarSection() {
    return Consumer<SpeechService>(
      builder: (_, speech, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            AikaAvatar(
              emotion: _emotion,
              isListening: speech.isListening,
              isSpeaking: speech.isSpeaking,
              soundLevel: speech.soundLevel,
            ),
            const SizedBox(height: 8),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AikaTheme.neonBlue, AikaTheme.neonPurple],
              ).createShader(bounds),
              child: const Text(
                'А И К А',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 8,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _getStatusText(),
              style: const TextStyle(
                color: AikaTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusText() {
    if (_speechService.isListening) return 'Слушаю...';
    if (_speechService.isSpeaking) return 'Говорю...';
    if (_isTyping) return 'Думаю...';
    switch (_emotion) {
      case AikaEmotion.thinking:
        return 'Обдумываю...';
      case AikaEmotion.happy:
        return 'Рада тебя видеть!';
      default:
        return 'Готова помочь';
    }
  }

  Widget _buildListeningText() {
    return Consumer<SpeechService>(
      builder: (_, speech, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: AikaTheme.glassCard(borderColor: AikaTheme.neonPink),
          child: Text(
            speech.lastWords.isEmpty ? 'Говори...' : speech.lastWords,
            style: TextStyle(
              color: speech.lastWords.isEmpty
                  ? AikaTheme.textSecondary
                  : AikaTheme.textPrimary,
              fontSize: 14,
              fontStyle: speech.lastWords.isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildToggleBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _buildToggleChip('Чат', Icons.chat_bubble_outline, true),
          const SizedBox(width: 8),
          _buildQuickActionChip('🔦', () => _deviceService.executeAction('flashlight_toggle')),
          _buildQuickActionChip('📱', () => _sendMessage('Что умеешь делать?')),
          _buildQuickActionChip('🎵', () => _deviceService.executeAction('open_spotify')),
          _buildQuickActionChip('🔍', () => _sendMessage('Открой поиск в интернете')),
        ],
      ),
    );
  }

  Widget _buildToggleChip(String label, IconData icon, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: AikaTheme.glassCard(
        borderColor: active ? AikaTheme.neonBlue : Colors.white24,
        opacity: active ? 0.1 : 0.04,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: active ? AikaTheme.neonBlue : AikaTheme.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: active ? AikaTheme.neonBlue : AikaTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionChip(String emoji, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.only(left: 8),
        decoration: AikaTheme.glassCard(opacity: 0.04),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 16))),
      ),
    );
  }

  Widget _buildChatSection() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _messages.length) {
          return const TypingIndicator();
        }
        return ChatBubble(message: _messages[i]);
      },
    );
  }

  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: AikaTheme.surface,
        border: Border(
          top: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.2), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Text field
          Expanded(
            child: Container(
              decoration: AikaTheme.glassCard(opacity: 0.05),
              child: TextField(
                controller: _textController,
                style: const TextStyle(color: AikaTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Напиши Айке...',
                  hintStyle: const TextStyle(color: AikaTheme.textSecondary, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send_rounded, color: AikaTheme.neonBlue, size: 20),
                    onPressed: () => _sendMessage(_textController.text),
                  ),
                ),
                onSubmitted: _sendMessage,
                maxLines: null,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Voice button
          Consumer<SpeechService>(
            builder: (_, speech, __) => VoiceButton(
              isListening: speech.isListening,
              isSpeaking: speech.isSpeaking,
              soundLevel: speech.soundLevel,
              onTap: _toggleListening,
            ),
          ),
        ],
      ),
    );
  }
}

extension IterableExtension<T> on List<T> {
  List<T> takeLast(int n) {
    if (n >= length) return this;
    return sublist(length - n);
  }
}
