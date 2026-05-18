import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/app_launcher_service.dart';
import '../theme/app_theme.dart';

class CommandsScreen extends StatefulWidget {
  const CommandsScreen({Key? key}) : super(key: key);

  @override
  State<CommandsScreen> createState() => _CommandsScreenState();
}

class _CommandsScreenState extends State<CommandsScreen> {
  Map<String, String> _commands = {};
  bool _isListening = false;
  String _listenedPhrase = '';
  final stt.SpeechToText _speech = stt.SpeechToText();

  // Популярные приложения для быстрого выбора
  static const List<Map<String, String>> _popularApps = [
    {'name': 'Spotify',        'package': 'com.spotify.music',               'emoji': '🎵'},
    {'name': 'YouTube',        'package': 'com.google.android.youtube',       'emoji': '▶️'},
    {'name': 'YouTube Music',  'package': 'com.google.android.apps.youtube.music', 'emoji': '🎶'},
    {'name': 'Telegram',       'package': 'org.telegram.messenger',           'emoji': '✈️'},
    {'name': 'WhatsApp',       'package': 'com.whatsapp',                     'emoji': '💬'},
    {'name': 'Instagram',      'package': 'com.instagram.android',            'emoji': '📸'},
    {'name': 'TikTok',         'package': 'com.zhiliaoapp.musically',         'emoji': '🎵'},
    {'name': 'VK',             'package': 'com.vkontakte.android',            'emoji': '💙'},
    {'name': 'Chrome',         'package': 'com.android.chrome',               'emoji': '🌐'},
    {'name': 'Gmail',          'package': 'com.google.android.gm',            'emoji': '📧'},
    {'name': 'Google Карты',   'package': 'com.google.android.apps.maps',     'emoji': '🗺️'},
    {'name': 'Камера',         'package': 'com.android.camera2',              'emoji': '📷'},
    {'name': 'Калькулятор',    'package': 'com.google.android.calculator',    'emoji': '🔢'},
    {'name': 'Настройки',      'package': 'com.android.settings',             'emoji': '⚙️'},
    {'name': 'Netflix',        'package': 'com.netflix.mediaclient',          'emoji': '🎬'},
    {'name': 'Twitch',         'package': 'tv.twitch.android.app',            'emoji': '🟣'},
    {'name': 'Discord',        'package': 'com.discord',                      'emoji': '🎮'},
    {'name': 'Яндекс Музыка',  'package': 'ru.yandex.music',                  'emoji': '🎧'},
    {'name': 'Яндекс',         'package': 'ru.yandex.searchplugin',           'emoji': '🔍'},
    {'name': 'Другое...',      'package': '__custom__',                       'emoji': '📱'},
  ];

  @override
  void initState() {
    super.initState();
    _loadCommands();
  }

  Future<void> _loadCommands() async {
    final all = await AppLauncherService.getAllCommands();
    setState(() => _commands = all);
  }

  Future<void> _startListening() async {
    final available = await _speech.initialize(
      onStatus: (s) { if (s == 'done') setState(() => _isListening = false); },
      onError:  (_) => setState(() => _isListening = false),
    );
    if (!available) return;
    setState(() { _isListening = true; _listenedPhrase = ''; });
    _speech.listen(
      onResult: (r) {
        if (r.finalResult) {
          setState(() {
            _listenedPhrase = r.recognizedWords;
            _isListening = false;
          });
          _speech.stop();
        }
      },
      localeId: 'ru_RU',
      listenMode: stt.ListenMode.dictation,
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  void _showAddCommandDialog({String prefillPhrase = ''}) {
    final phraseCtrl = TextEditingController(text: prefillPhrase);
    final packageCtrl = TextEditingController();
    String? selectedPackage;
    String? selectedName;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) {
        return Container(
          decoration: BoxDecoration(
            color: AikaTheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.3)),
          ),
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Заголовок
                Row(
                  children: [
                    Icon(Icons.link_rounded, color: AikaTheme.neonBlue),
                    const SizedBox(width: 10),
                    Text('Новая команда',
                      style: TextStyle(color: AikaTheme.neonBlue, fontSize: 17, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 20),

                // Фраза
                Text('ФРАЗА', style: TextStyle(color: AikaTheme.neonBlue.withOpacity(0.7), fontSize: 11, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: phraseCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'напр. "открой музыку"',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: AikaTheme.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.3)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.3)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AikaTheme.neonBlue),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Кнопка записи голоса
                    GestureDetector(
                      onTapDown: (_) async {
                        final avail = await _speech.initialize();
                        if (!avail) return;
                        setModal(() {});
                        _speech.listen(
                          onResult: (r) {
                            if (r.finalResult) {
                              phraseCtrl.text = r.recognizedWords;
                              _speech.stop();
                            }
                          },
                          localeId: 'ru_RU',
                        );
                      },
                      onTapUp: (_) => _speech.stop(),
                      child: Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(
                          color: AikaTheme.neonBlue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.4)),
                        ),
                        child: Icon(Icons.mic_rounded, color: AikaTheme.neonBlue),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Выбор приложения
                Text('ПРИЛОЖЕНИЕ', style: TextStyle(color: AikaTheme.neonBlue.withOpacity(0.7), fontSize: 11, letterSpacing: 1.5)),
                const SizedBox(height: 10),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: _popularApps.length,
                  itemBuilder: (_, i) {
                    final app = _popularApps[i];
                    final isSelected = selectedPackage == app['package'];
                    return GestureDetector(
                      onTap: () {
                        if (app['package'] == '__custom__') {
                          setModal(() { selectedPackage = null; selectedName = null; });
                          // Показать поле для ввода package вручную
                          return;
                        }
                        setModal(() {
                          selectedPackage = app['package'];
                          selectedName = app['name'];
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AikaTheme.neonBlue.withOpacity(0.2)
                              : AikaTheme.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AikaTheme.neonBlue
                                : AikaTheme.neonBlue.withOpacity(0.15),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(app['emoji']!, style: const TextStyle(fontSize: 22)),
                            const SizedBox(height: 4),
                            Text(
                              app['name']!,
                              style: TextStyle(
                                color: isSelected ? AikaTheme.neonBlue : Colors.white70,
                                fontSize: 10,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // Поле для своего package name
                const SizedBox(height: 12),
                Text('ИЛИ ВВЕДИ PACKAGE NAME ВРУЧНУЮ',
                    style: TextStyle(color: AikaTheme.neonBlue.withOpacity(0.5), fontSize: 10, letterSpacing: 1)),
                const SizedBox(height: 6),
                TextField(
                  controller: packageCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  onChanged: (v) {
                    if (v.isNotEmpty) setModal(() { selectedPackage = v; selectedName = v; });
                  },
                  decoration: InputDecoration(
                    hintText: 'com.example.app',
                    hintStyle: const TextStyle(color: Colors.white.withOpacity(0.12), fontSize: 12),
                    filled: true,
                    fillColor: AikaTheme.background,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.2)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AikaTheme.neonBlue),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                // Кнопка Сохранить
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AikaTheme.neonBlue,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      final phrase = phraseCtrl.text.trim();
                      final pkg = packageCtrl.text.trim().isNotEmpty
                          ? packageCtrl.text.trim()
                          : selectedPackage;
                      if (phrase.isEmpty || pkg == null || pkg == '__custom__') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Введи фразу и выбери приложение')),
                        );
                        return;
                      }
                      await AppLauncherService.addCommand(phrase, pkg);
                      Navigator.pop(ctx);
                      await _loadCommands();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✅ Команда "$phrase" сохранена'),
                            backgroundColor: AikaTheme.neonBlue.withOpacity(0.8),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    child: const Text('СОХРАНИТЬ', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  String _appNameFromPackage(String pkg) {
    for (final app in _popularApps) {
      if (app['package'] == pkg) return '${app['emoji']} ${app['name']}';
    }
    return '📱 $pkg';
  }

  bool _isCustomCommand(String phrase) {
    return !AppLauncherService.builtinCommands.containsKey(phrase);
  }

  @override
  Widget build(BuildContext context) {
    final customCmds = _commands.entries
        .where((e) => _isCustomCommand(e.key))
        .toList();
    final builtinCmds = _commands.entries
        .where((e) => !_isCustomCommand(e.key))
        .toList();

    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'МОИ КОМАНДЫ',
          style: TextStyle(
            color: AikaTheme.neonBlue,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
          ),
        ),
        centerTitle: true,
        iconTheme: IconThemeData(color: AikaTheme.neonBlue),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Кнопка добавить голосом
          GestureDetector(
            onLongPress: _startListening,
            onLongPressEnd: (_) async {
              await _stopListening();
              if (_listenedPhrase.isNotEmpty) {
                _showAddCommandDialog(prefillPhrase: _listenedPhrase);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: _isListening
                    ? AikaTheme.neonBlue.withOpacity(0.2)
                    : AikaTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isListening ? AikaTheme.neonBlue : AikaTheme.neonBlue.withOpacity(0.3),
                  width: _isListening ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _isListening ? Icons.mic : Icons.mic_none_rounded,
                    color: AikaTheme.neonBlue,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isListening
                        ? 'Слушаю... говори фразу'
                        : 'Зажми чтобы записать фразу голосом',
                    style: TextStyle(
                      color: _isListening ? AikaTheme.neonBlue : Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                  if (_listenedPhrase.isNotEmpty && !_isListening) ...[
                    const SizedBox(height: 6),
                    Text('"$_listenedPhrase"',
                        style: const TextStyle(color: Colors.white, fontSize: 15)),
                  ]
                ],
              ),
            ),
          ),

          // Кнопка добавить вручную
          OutlinedButton.icon(
            onPressed: () => _showAddCommandDialog(),
            icon: Icon(Icons.add_rounded, color: AikaTheme.neonBlue),
            label: Text('Добавить вручную',
                style: TextStyle(color: AikaTheme.neonBlue, letterSpacing: 1)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.4)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 24),

          // Мои команды
          if (customCmds.isNotEmpty) ...[
            _sectionLabel('МОИ КОМАНДЫ'),
            ...customCmds.map((e) => _commandTile(e.key, e.value, isCustom: true)),
            const SizedBox(height: 20),
          ],

          // Встроенные
          _sectionLabel('ВСТРОЕННЫЕ'),
          ...builtinCmds.map((e) => _commandTile(e.key, e.value, isCustom: false)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text,
      style: TextStyle(
        color: AikaTheme.neonBlue,
        fontSize: 11,
        letterSpacing: 1.5,
        fontWeight: FontWeight.bold,
      )),
  );

  Widget _commandTile(String phrase, String packageName, {required bool isCustom}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AikaTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.12)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AikaTheme.neonBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.record_voice_over_rounded,
              color: AikaTheme.neonBlue.withOpacity(0.8), size: 20),
        ),
        title: Text('"$phrase"',
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(_appNameFromPackage(packageName),
          style: const TextStyle(color: Colors.white38, fontSize: 12)),
        trailing: isCustom
            ? IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                onPressed: () async {
                  await AppLauncherService.removeCommand(phrase);
                  await _loadCommands();
                },
              )
            : Icon(Icons.lock_outline_rounded, color: Colors.white.withOpacity(0.15), size: 18),
      ),
    );
  }
}

