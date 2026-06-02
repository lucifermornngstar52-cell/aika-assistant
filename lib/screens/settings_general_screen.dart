import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class SettingsGeneralScreen extends StatefulWidget {
  const SettingsGeneralScreen({Key? key}) : super(key: key);
  @override
  State<SettingsGeneralScreen> createState() => _SettingsGeneralScreenState();
}

class _SettingsGeneralScreenState extends State<SettingsGeneralScreen> {
  final _nameCtrl = TextEditingController();
  final _userNameCtrl = TextEditingController();
  double _avatarSize = 160;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameCtrl.text = prefs.getString('assistant_name') ?? 'Aika';
      _userNameCtrl.text = prefs.getString('user_name') ?? '';
      _avatarSize = prefs.getDouble('avatar_size') ?? 160;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final name = _nameCtrl.text.trim();
    await prefs.setString('assistant_name', name.isEmpty ? 'Aika' : name);
    await prefs.setString('user_name', _userNameCtrl.text.trim());
    await prefs.setDouble('avatar_size', _avatarSize);
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
              hintText: 'Aika',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: Icon(Icons.auto_awesome, color: AikaTheme.neonBlue),
              border: InputBorder.none,
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
