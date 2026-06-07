import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/voice_command_parser.dart';
import '../services/offline_voice_service.dart';

/// Экран настройки голосовых команд.
/// Пользователь видит встроенные команды и может создавать свои.
/// Кастомные команды хранятся в SharedPreferences — без сервера, офлайн.
class VoiceSettingsScreen extends StatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<CustomVoiceCommand> _customCommands = [];
  bool _bgEnabled = true;
  String _assistantName = 'Айка';
  bool _loading = true;

  static const _prefKey = 'custom_voice_commands';
  static const _bgKey   = 'voice_bg_enabled';
  static const _nameKey = 'assistant_name';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    setState(() {
      _bgEnabled = prefs.getBool(_bgKey) ?? true;
      _assistantName = prefs.getString(_nameKey) ?? 'Айка';
      if (raw != null) {
        try {
          final list = jsonDecode(raw) as List;
          _customCommands = list.map((e) => CustomVoiceCommand.fromJson(e)).toList();
        } catch (_) {}
      }
      _loading = false;
    });
  }

  Future<void> _saveCustomCommands() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(_customCommands.map((c) => c.toJson()).toList()));
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bgKey, _bgEnabled);
    await prefs.setString(_nameKey, _assistantName);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D0D1A) : const Color(0xFFF5F5FF);
    final card = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final accent = const Color(0xFFFF2D78);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: const Text(
          'Голосовые команды',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: accent,
          labelColor: accent,
          unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
          tabs: const [
            Tab(text: 'Настройки'),
            Tab(text: 'Мои команды'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelp,
            tooltip: 'Помощь',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildSettingsTab(card, accent),
                _buildCustomCommandsTab(card, accent),
              ],
            ),
      floatingActionButton: _tabs.index == 1
          ? FloatingActionButton.extended(
              backgroundColor: accent,
              onPressed: _addCustomCommand,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Добавить команду',
                  style: TextStyle(color: Colors.white)),
            )
          : null,
    );
  }

  // ── Tab 1: Settings ────────────────────────────────────────────────────────

  Widget _buildSettingsTab(Color card, Color accent) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Фоновое прослушивание
        _card(card, [
          _sectionTitle('Фоновое прослушивание'),
          SwitchListTile(
            activeColor: accent,
            title: const Text('Слушать в фоне'),
            subtitle: const Text(
              'Работает даже когда экран заблокирован',
              style: TextStyle(fontSize: 12),
            ),
            value: _bgEnabled,
            onChanged: (val) async {
              setState(() => _bgEnabled = val);
              await _saveSettings();
              if (val) {
                await OfflineVoiceService().startBackground();
              } else {
                await OfflineVoiceService().stopBackground();
              }
            },
          ),
        ]),

        const SizedBox(height: 12),

        // Имя ассистента
        _card(card, [
          _sectionTitle('Имя ассистента'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: TextEditingController(text: _assistantName),
              decoration: InputDecoration(
                hintText: 'Айка',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: accent),
                ),
                suffixIcon: Icon(Icons.mic, color: accent),
              ),
              onChanged: (val) {
                _assistantName = val.trim().isEmpty ? 'Айка' : val.trim();
              },
              onSubmitted: (_) async {
                await _saveSettings();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Имя сохранено')));
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Скажите «$_assistantName» чтобы активировать',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ),
        ]),

        const SizedBox(height: 12),

        // Встроенные команды
        _card(card, [
          _sectionTitle('Встроенные команды'),
          const SizedBox(height: 4),
          ..._builtinGroups.map((g) => _builtinGroup(g, accent)),
        ]),

        const SizedBox(height: 80),
      ],
    );
  }

  Widget _builtinGroup(_CommandGroup group, Color accent) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(group.icon, color: accent, size: 20),
        title: Text(group.title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        children: group.commands.map((cmd) => ListTile(
          dense: true,
          contentPadding: const EdgeInsets.fromLTRB(48, 0, 16, 0),
          title: Text('«${cmd.example}»',
              style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
          subtitle: Text(cmd.description, style: const TextStyle(fontSize: 11)),
        )).toList(),
      ),
    );
  }

  // ── Tab 2: Custom commands ─────────────────────────────────────────────────

  Widget _buildCustomCommandsTab(Color card, Color accent) {
    if (_customCommands.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Нет кастомных команд',
                style: TextStyle(color: Colors.grey[500], fontSize: 16)),
            const SizedBox(height: 8),
            Text('Нажмите + чтобы добавить',
                style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _customCommands.length,
      itemBuilder: (ctx, i) {
        final cmd = _customCommands[i];
        return Dismissible(
          key: Key('custom_$i'),
          background: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.red.shade700,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          direction: DismissDirection.endToStart,
          onDismissed: (_) async {
            setState(() => _customCommands.removeAt(i));
            await _saveCustomCommands();
          },
          child: _customCommandCard(cmd, card, accent, i),
        );
      },
    );
  }

  Widget _customCommandCard(
      CustomVoiceCommand cmd, Color card, Color accent, int i) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.15)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.mic, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('«${cmd.trigger}»',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic)),
                const SizedBox(height: 2),
                Text(cmd.description,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                if (cmd.appPackage != null)
                  Text('📱 ${cmd.appPackage}',
                      style: TextStyle(fontSize: 10, color: Colors.grey[400])),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit_outlined, color: accent),
            onPressed: () => _editCustomCommand(i),
          ),
        ],
      ),
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  Future<void> _addCustomCommand() async {
    final result = await showDialog<CustomVoiceCommand>(
      context: context,
      builder: (_) => const _CustomCommandDialog(),
    );
    if (result != null) {
      setState(() => _customCommands.add(result));
      await _saveCustomCommands();
    }
  }

  Future<void> _editCustomCommand(int i) async {
    final result = await showDialog<CustomVoiceCommand>(
      context: context,
      builder: (_) => _CustomCommandDialog(initial: _customCommands[i]),
    );
    if (result != null) {
      setState(() => _customCommands[i] = result);
      await _saveCustomCommands();
    }
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Как создать команду'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1. Нажмите кнопку + на вкладке "Мои команды"',
                  style: TextStyle(fontSize: 14)),
              SizedBox(height: 8),
              Text('2. Введите фразу-триггер (что вы скажете)',
                  style: TextStyle(fontSize: 14)),
              SizedBox(height: 8),
              Text('3. Выберите тип действия и заполните детали',
                  style: TextStyle(fontSize: 14)),
              SizedBox(height: 16),
              Text('Примеры:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Триггер: «включи мой плейлист»\n→ Действие: открыть Spotify + воспроизвести "Мой плейлист"',
                  style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
              SizedBox(height: 8),
              Text('Триггер: «открой работу»\n→ Действие: открыть приложение Gmail',
                  style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _card(Color color, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)],
      ),
      child: Column(children: children),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13,
                color: Color(0xFFFF2D78))),
      ),
    );
  }

  static const _builtinGroups = [
    _CommandGroup(icon: Icons.phone, title: 'Звонки', commands: [
      _Cmd('позвони маме', 'Позвонить контакту'),
      _Cmd('ответь', 'Принять входящий звонок'),
      _Cmd('сбрось звонок', 'Завершить/отклонить звонок'),
    ]),
    _CommandGroup(icon: Icons.music_note, title: 'Медиа', commands: [
      _Cmd('пауза / играй', 'Пауза или возобновить'),
      _Cmd('следующий трек', 'Следующая песня'),
      _Cmd('громче / тише', 'Изменить громкость'),
    ]),
    _CommandGroup(icon: Icons.settings, title: 'Телефон', commands: [
      _Cmd('включи фонарик', 'Фонарик'),
      _Cmd('включи WiFi / Bluetooth', 'Быстрые настройки'),
      _Cmd('заблокируй экран', 'Заблокировать'),
      _Cmd('скриншот', 'Снимок экрана'),
      _Cmd('авиарежим', 'Режим полёта'),
    ]),
    _CommandGroup(icon: Icons.smart_display, title: 'YouTube', commands: [
      _Cmd('лайк', 'Лайкнуть видео'),
      _Cmd('на весь экран', 'Полноэкранный режим'),
      _Cmd('подписаться', 'Подписаться на канал'),
      _Cmd('найди котов в YouTube', 'Поиск в YouTube'),
    ]),
    _CommandGroup(icon: Icons.chat, title: 'Мессенджеры', commands: [
      _Cmd('открой чат с Машей в Telegram', 'Открыть чат'),
      _Cmd('напиши Паше в WhatsApp привет', 'Отправить сообщение'),
    ]),
    _CommandGroup(icon: Icons.navigation, title: 'Навигация', commands: [
      _Cmd('домой', 'На главный экран'),
      _Cmd('назад', 'Вернуться'),
      _Cmd('шторка', 'Открыть уведомления'),
      _Cmd('прокрути вниз / вверх', 'Прокрутка'),
    ]),
    _CommandGroup(icon: Icons.alarm, title: 'Будильник и таймер', commands: [
      _Cmd('поставь будильник на 7:30', 'Создать будильник'),
      _Cmd('поставь таймер на 5 минут', 'Запустить таймер'),
    ]),
  ];
}

// ── Dialog ────────────────────────────────────────────────────────────────────

class _CustomCommandDialog extends StatefulWidget {
  final CustomVoiceCommand? initial;
  const _CustomCommandDialog({this.initial});

  @override
  State<_CustomCommandDialog> createState() => _CustomCommandDialogState();
}

class _CustomCommandDialogState extends State<_CustomCommandDialog> {
  final _triggerCtrl  = TextEditingController();
  final _descCtrl     = TextEditingController();
  final _paramCtrl    = TextEditingController();
  final _pkgCtrl      = TextEditingController();
  String _actionType  = 'open_app';

  static const _actions = [
    ('open_app',   Icons.apps,           'Открыть приложение'),
    ('media_play', Icons.play_arrow,     'Включить музыку/видео'),
    ('call',       Icons.phone,          'Позвонить контакту'),
    ('web_search', Icons.search,         'Поиск в интернете'),
    ('open_url',   Icons.link,           'Открыть сайт'),
    ('type_text',  Icons.keyboard,       'Ввести текст'),
    ('tap_by_text',Icons.touch_app,      'Нажать кнопку'),
    ('set_alarm',  Icons.alarm,          'Поставить будильник'),
    ('torch_on',   Icons.flashlight_on,  'Включить фонарик'),
    ('go_home',    Icons.home,           'На главный экран'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _triggerCtrl.text = widget.initial!.trigger;
      _descCtrl.text    = widget.initial!.description;
      _paramCtrl.text   = widget.initial!.param ?? '';
      _pkgCtrl.text     = widget.initial!.appPackage ?? '';
      _actionType       = widget.initial!.actionType;
    }
  }

  @override
  void dispose() {
    _triggerCtrl.dispose();
    _descCtrl.dispose();
    _paramCtrl.dispose();
    _pkgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFFF2D78);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Новая голосовая команда',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 20),

            _field('Фраза-триггер', 'Например: включи мой плейлист',
                _triggerCtrl, Icons.mic),
            const SizedBox(height: 12),

            const Text('Действие', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _actions.map((a) {
                final selected = _actionType == a.$1;
                return FilterChip(
                  selected: selected,
                  selectedColor: accent.withOpacity(0.15),
                  checkmarkColor: accent,
                  avatar: Icon(a.$2, size: 16, color: selected ? accent : null),
                  label: Text(a.$3, style: TextStyle(fontSize: 12,
                      color: selected ? accent : null)),
                  onSelected: (_) => setState(() => _actionType = a.$1),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            _field(_paramLabel, _paramHint, _paramCtrl, Icons.edit),
            const SizedBox(height: 12),

            _field('Описание (необязательно)', 'Что делает эта команда', _descCtrl, Icons.notes),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  onPressed: _save,
                  child: const Text('Сохранить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _paramLabel {
    switch (_actionType) {
      case 'open_app':   return 'Пакет приложения';
      case 'call':       return 'Имя или номер';
      case 'web_search': return 'Поисковый запрос';
      case 'open_url':   return 'URL сайта';
      case 'type_text':  return 'Текст для ввода';
      case 'tap_by_text':return 'Текст кнопки';
      case 'set_alarm':  return 'Время (07:30)';
      default: return 'Параметр';
    }
  }

  String get _paramHint {
    switch (_actionType) {
      case 'open_app':   return 'com.spotify.music';
      case 'call':       return 'Мама / +79001234567';
      case 'web_search': return 'рецепт борща';
      case 'open_url':   return 'https://...';
      case 'type_text':  return 'Привет, мир!';
      case 'tap_by_text':return 'Отправить';
      case 'set_alarm':  return '07:30';
      default: return '';
    }
  }

  Widget _field(String label, String hint, TextEditingController ctrl, IconData icon) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF2D78)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  void _save() {
    final trigger = _triggerCtrl.text.trim();
    if (trigger.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите фразу-триггер')));
      return;
    }
    Navigator.pop(context, CustomVoiceCommand(
      trigger: trigger,
      actionType: _actionType,
      param: _paramCtrl.text.trim().isEmpty ? null : _paramCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty
          ? _actions.firstWhere((a) => a.$1 == _actionType, orElse: () => (_actionType, Icons.star, _actionType)).$3
          : _descCtrl.text.trim(),
      appPackage: _pkgCtrl.text.trim().isEmpty ? null : _pkgCtrl.text.trim(),
    ));
  }
}

// ── Models ────────────────────────────────────────────────────────────────────

class CustomVoiceCommand {
  final String  trigger;
  final String  actionType;
  final String? param;
  final String  description;
  final String? appPackage;

  const CustomVoiceCommand({
    required this.trigger,
    required this.actionType,
    required this.description,
    this.param,
    this.appPackage,
  });

  Map<String, dynamic> toJson() => {
    'trigger': trigger, 'actionType': actionType,
    'param': param, 'description': description, 'appPackage': appPackage,
  };
  factory CustomVoiceCommand.fromJson(Map<String, dynamic> j) =>
      CustomVoiceCommand(
        trigger: j['trigger'] ?? '', actionType: j['actionType'] ?? 'open_app',
        param: j['param'], description: j['description'] ?? '',
        appPackage: j['appPackage'],
      );

  /// Convert to VoiceCommand for execution
  VoiceCommand toVoiceCommand(String rawText) => VoiceCommand(
    action: actionType,
    target: param,
    app: appPackage,
    rawText: rawText,
  );
}

// ── Static data ───────────────────────────────────────────────────────────────

class _CommandGroup {
  final IconData icon;
  final String title;
  final List<_Cmd> commands;
  const _CommandGroup({required this.icon, required this.title, required this.commands});
}

class _Cmd {
  final String example;
  final String description;
  const _Cmd(this.example, this.description);
}
