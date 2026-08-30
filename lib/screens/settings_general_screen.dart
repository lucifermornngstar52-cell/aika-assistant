import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/theme_switcher_service.dart';
import '../services/overlay_service.dart';

class SettingsGeneralScreen extends StatefulWidget {
  const SettingsGeneralScreen({Key? key}) : super(key: key);
  @override
  State<SettingsGeneralScreen> createState() => _SettingsGeneralScreenState();
}

class _SettingsGeneralScreenState extends State<SettingsGeneralScreen> {
  final _nameCtrl = TextEditingController();
  final _userNameCtrl = TextEditingController();
  final _wakeWordCtrl = TextEditingController();
  double _avatarSize = 160;
  bool _loading = true;
  final _themeSwitcher = ThemeSwitcherService();
  final _overlaySvc = OverlayService();
  bool _hasOverlayPermission = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await _themeSwitcher.load();
    final hasPerm = await _overlaySvc.hasPermission();
    setState(() {
      _nameCtrl.text = prefs.getString('assistant_name') ?? 'Aivora';
      _userNameCtrl.text = prefs.getString('user_name') ?? '';
      _avatarSize = prefs.getDouble('avatar_size') ?? 160;
      _wakeWordCtrl.text = prefs.getString('custom_wake_word') ?? '';
      _hasOverlayPermission = hasPerm;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final name = _nameCtrl.text.trim();
    await prefs.setString('assistant_name', name.isEmpty ? 'Aivora' : name);
    await prefs.setString('user_name', _userNameCtrl.text.trim());
    await prefs.setDouble('avatar_size', _avatarSize);
    // Кастомный wake word
    final customWW = _wakeWordCtrl.text.trim().toLowerCase();
    await prefs.setString('custom_wake_word', customWW);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Сохранено'),
        backgroundColor: AikaTheme.neonBlue.withOpacity(0.8),
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Общие', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(onPressed: _save,
              child: Text('Сохранить', style: TextStyle(color: AikaTheme.neonBlue, fontSize: 15))),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AikaTheme.neonBlue))
          : ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _label('ИМЯ АССИСТЕНТА'),
          _card(TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Aivora',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: Icon(Icons.auto_awesome, color: AikaTheme.neonBlue),
              border: InputBorder.none,
            ),
          )),
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          _label('КАСТОМНЫЙ WAKE WORD'),
          _card(TextField(
            controller: _wakeWordCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'например: эй аивора, слушай, привет',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: Icon(Icons.record_voice_over, color: AikaTheme.neonPink),
              border: InputBorder.none,
              helperText: 'Добавь своё слово через запятую. Дефолт: аика, aika',
              helperStyle: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          )),
          const SizedBox(height: 16),
          _label('ИМЯ ПОЛЬЗОВАТЕЛЯ'),
          _card(TextField(
            controller: _userNameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Как вас зовут?',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: Icon(Icons.person_outline, color: AikaTheme.neonBlue),
              border: InputBorder.none,
            ),
          )),
          const SizedBox(height: 16),
          _label('РАЗМЕР АВАТАРА'),
          _card(Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Размер', style: TextStyle(color: Colors.white70)),
                Text('${_avatarSize.round()}px', style: TextStyle(color: AikaTheme.neonBlue)),
              ]),
              Slider(
                value: _avatarSize,
                min: 100, max: 300,
                activeColor: AikaTheme.neonBlue,
                inactiveColor: Colors.white12,
                onChanged: (v) => setState(() => _avatarSize = v),
              ),
            ],
          )),
          const SizedBox(height: 16),
          _label('ТЕМА ИНТЕРФЕЙСА'),
          _card(Row(
            children: [
              Icon(_themeSwitcher.isJarvis ? Icons.nightlight_round : Icons.wb_sunny_outlined,
                  color: AikaTheme.neonBlue),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_themeSwitcher.isJarvis ? 'J.A.R.V.I.S HUD' : 'Айка (обычная)',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const Text('Переключить визуальный стиль интерфейса',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              )),
              Switch(
                value: _themeSwitcher.isJarvis,
                activeColor: AikaTheme.neonBlue,
                onChanged: (v) async {
                  await _themeSwitcher.toggle();
                  setState(() {});
                },
              ),
            ],
          )),
          const SizedBox(height: 16),
          _label('РАЗРЕШЕНИЕ НА ОВЕРЛЕЙ'),
          _card(Row(
            children: [
              Icon(_hasOverlayPermission ? Icons.check_circle : Icons.error_outline,
                  color: _hasOverlayPermission ? Colors.greenAccent : Colors.orangeAccent),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_hasOverlayPermission ? 'Разрешение выдано' : 'Разрешение не выдано',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const Text('Нужно, чтобы персонаж показывался поверх других приложений',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              )),
              if (!_hasOverlayPermission)
                TextButton(
                  onPressed: () async {
                    await _overlaySvc.requestPermission();
                    await Future.delayed(const Duration(milliseconds: 500));
                    final has = await _overlaySvc.hasPermission();
                    if (mounted) setState(() => _hasOverlayPermission = has);
                  },
                  child: Text('Выдать', style: TextStyle(color: AikaTheme.neonBlue)),
                ),
            ],
          )),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(text, style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2)),
  );

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(14)),
    child: child,
  );
}
