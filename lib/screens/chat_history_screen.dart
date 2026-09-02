import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ChatHistoryScreen extends StatefulWidget {
  const ChatHistoryScreen({Key? key}) : super(key: key);
  @override
  State<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _wasCleared = false; // ФИКС: сигнализируем родительским экранам об очистке

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('chat_history');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _messages = list.map((m) => ChatMessage.fromJson(m)).toList();
      } catch (_) {}
    }
    setState(() => _loading = false);
  }

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Очистить историю?', style: TextStyle(color: Colors.white)),
        content: const Text('Все сообщения будут удалены', style: TextStyle(color: Colors.white60)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: Text('Очистить', style: TextStyle(color: AikaTheme.neonBlue))),
        ],
      ),
    );
    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('chat_history');
      setState(() { _messages = []; _wasCleared = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _wasCleared);
        return false;
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context, _wasCleared),
        ),
        title: const Text('История чата',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white54),
              onPressed: _clearHistory,
              tooltip: 'Очистить',
            ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AikaTheme.neonBlue))
          : _messages.isEmpty
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.chat_bubble_outline, color: Colors.white12, size: 64),
                    const SizedBox(height: 16),
                    const Text('История пуста', style: TextStyle(color: Colors.white38, fontSize: 16)),
                  ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  reverse: true,
                  itemCount: _messages.length,
                  itemBuilder: (ctx, i) {
                    final msg = _messages[_messages.length - 1 - i];
                    final isUser = msg.role == MessageRole.user;
                    return GestureDetector(
                      onLongPress: () {
                        Clipboard.setData(ClipboardData(text: msg.content));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Скопировано'),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ));
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isUser
                              ? AikaTheme.neonBlue.withOpacity(0.12)
                              : const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isUser
                                ? AikaTheme.neonBlue.withOpacity(0.3)
                                : Colors.white12,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(
                                isUser ? 'Вы' : 'Айка',
                                style: TextStyle(
                                  color: isUser ? AikaTheme.neonBlue : AikaTheme.neonPurple,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${msg.timestamp.hour.toString().padLeft(2,'0')}:${msg.timestamp.minute.toString().padLeft(2,'0')}',
                                style: const TextStyle(color: Colors.white24, fontSize: 10),
                              ),
                            ]),
                            const SizedBox(height: 5),
                            Text(msg.content,
                                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      ),
    );
  }
}
