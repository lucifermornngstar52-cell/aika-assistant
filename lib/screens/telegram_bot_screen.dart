import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/telegram_bot_service.dart';
import '../theme/app_theme.dart';

class TelegramBotScreen extends StatefulWidget {
  const TelegramBotScreen({Key? key}) : super(key: key);

  @override
  State<TelegramBotScreen> createState() => _TelegramBotScreenState();
}

class _TelegramBotScreenState extends State<TelegramBotScreen> {
  final _tokenController = TextEditingController();
  bool _enabled = false;
  bool _loading = false;
  String? _botName;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final savedToken = await TelegramBotService.getSavedToken();
    final enabled = await TelegramBotService.isEnabled();
    setState(() {
      if (savedToken != null) _tokenController.text = savedToken;
      _enabled = enabled;
    });
    if (savedToken != null && savedToken.isNotEmpty) {
      _validateSilently(savedToken);
    }
  }

  Future<void> _validateSilently(String token) async {
    final name = await TelegramBotService.validateToken(token);
    if (mounted) setState(() => _botName = name);
  }

  Future<void> _save() async {
    final tokenText = _tokenController.text.trim();
    if (tokenText.isEmpty) {
      setState(() => _error = 'Введи токен бота');
      return;
    }
    setState(() { _loading = true; _error = null; });

    final botName = await TelegramBotService.validateToken(tokenText);
    if (botName == null) {
      setState(() { _loading = false; _error = 'Токен недействителен. Проверь правильность.'; });
      return;
    }

    await TelegramBotService.saveToken(tokenText);
    final prefs = await SharedPreferences.getInstance();
    // Сохраняем chat_id при первом входящем сообщении автоматически
    
    setState(() {
      _loading = false;
      _botName = botName;
      _error = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Бот $botName подключён ✓'),
        backgroundColor: const Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _toggleEnabled(bool value) async {
    await TelegramBotService.setEnabled(value);
    setState(() => _enabled = value);
    if (value) {
      await TelegramBotService.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: AikaTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '🤖 Telegram Бот',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AikaTheme.neonBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Как это работает?',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 8),
                  Text(
                    '1. Создай бота через @BotFather в Telegram\n'
                    '2. Скопируй токен и вставь ниже\n'
                    '3. Напиши своему боту — Айка ответит!',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Bot status
            if (_botName != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20),
                    const SizedBox(width: 8),
                    Text('Бот подключён: $_botName',
                      style: const TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Token input
            const Text('Токен бота', style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 8),
            TextField(
              controller: _tokenController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              obscureText: true,
              decoration: InputDecoration(
                hintText: '1234567890:AAF...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: AikaTheme.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AikaTheme.neonBlue),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.visibility, color: Colors.white38, size: 18),
                  onPressed: () {},
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
            const SizedBox(height: 16),

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AikaTheme.neonBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _loading
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Подключить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),

            if (_botName != null) ...[
              const SizedBox(height: 24),
              const Divider(color: Colors.white12),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Бот активен', style: TextStyle(color: Colors.white, fontSize: 15)),
                      Text('Айка будет отвечать в Telegram', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                  Switch(
                    value: _enabled,
                    onChanged: _toggleEnabled,
                    activeColor: AikaTheme.neonBlue,
                  ),
                ],
              ),
            ],

            const SizedBox(height: 32),
            Center(
              child: TextButton(
                onPressed: () => _showHelp(context),
                child: const Text('Как создать бота?',
                  style: TextStyle(color: AikaTheme.neonBlue, decoration: TextDecoration.underline)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AikaTheme.card,
        title: const Text('Создание бота', style: TextStyle(color: Colors.white)),
        content: Text(
          '1. Открой Telegram и найди @BotFather\n'
          '2. Напиши /newbot\n'
          '3. Дай боту имя (например "Aika Assistant")\n'
          '4. Дай боту username (например "my_aika_bot")\n'
          '5. Скопируй токен который пришлёт BotFather\n'
          '6. Вставь его сюда и нажми "Подключить"',
          style: const TextStyle(color: Colors.white70, height: 1.7, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Понял!', style: TextStyle(color: AikaTheme.neonBlue)),
          ),
        ],
      ),
    );
  }
}
