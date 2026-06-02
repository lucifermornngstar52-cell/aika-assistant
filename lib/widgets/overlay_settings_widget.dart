import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/overlay_service.dart';

class OverlaySettingsWidget extends StatefulWidget {
  const OverlaySettingsWidget({super.key});
  @override
  State<OverlaySettingsWidget> createState() => _OverlaySettingsWidgetState();
}

class _OverlaySettingsWidgetState extends State<OverlaySettingsWidget> {
  final _svc = OverlayService();

  double _size    = 200.0;
  double _opacity = 1.0;
  String _side    = 'left';
  String _modelId = 'hiyori';

  static const _models = [
    {'id': 'hiyori', 'label': '🌸 Hiyori'},
    {'id': 'natori', 'label': '🌟 Natori'},
    {'id': 'haru',   'label': '⚡ Haru'},
    {'id': 'ren',    'label': '🔥 Ren'},
  ];

  static const _modelPaths = {
    'hiyori': 'models/Hiyori/Hiyori.model3.json',
    'natori': 'models/Natori/Natori.model3.json',
    'haru':   'models/Haru/Haru.model3.json',
    'ren':    'models/Ren/Ren.model3.json',
  };

  static const _states = [
    {'id': 'idle',      'label': '😴 Idle'},
    {'id': 'greeting',  'label': '👋 Привет'},
    {'id': 'thinking',  'label': '🤔 Думает'},
    {'id': 'listening', 'label': '👂 Слушает'},
    {'id': 'talking',   'label': '💬 Говорит'},
    {'id': 'dance',     'label': '💃 Танец'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _svc.init();
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() {
      _size    = _svc.sizeDp;
      _opacity = _svc.opacity;
      _side    = _svc.side;
      _modelId = prefs.getString('overlay_model_id') ?? 'hiyori';
    });
  }

  Future<void> _switchModel(String id) async {
    setState(() => _modelId = id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('overlay_model_id', id);
    final path = _modelPaths[id] ?? _modelPaths['hiyori']!;
    // Отправляем команду оверлею переключить модель
    await _svc.switchModel(path);
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF00E5FF);
    const bg     = Color(0xFF0D1117);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(children: const [
              Text('🤖', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text('Live2D оверлей',
                style: TextStyle(color: accent, fontSize: 15, fontWeight: FontWeight.bold)),
            ]),
          ),
          const Divider(color: Colors.white12, height: 1),

          // Размер
          _section(
            '📐 Размер: ${_size.round()} dp',
            Slider(
              value: _size, min: 100, max: 400, divisions: 30,
              activeColor: accent, inactiveColor: Colors.white12,
              onChanged: (v) => setState(() => _size = v),
              onChangeEnd: (v) async {
                setState(() => _size = v);
                await _svc.setSize(v);
              },
            ),
          ),

          // Прозрачность
          _section(
            '👁 Прозрачность: ${(_opacity * 100).round()}%',
            Slider(
              value: _opacity, min: 0.2, max: 1.0, divisions: 16,
              activeColor: accent, inactiveColor: Colors.white12,
              onChanged: (v) => setState(() => _opacity = v),
              onChangeEnd: (v) async {
                setState(() => _opacity = v);
                await _svc.setOpacity(v);
              },
            ),
          ),

          // Позиция
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              const Text('📌 Сторона: ',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(width: 8),
              _chip('◀ Лево', _side == 'left', () async {
                setState(() => _side = 'left');
                await _svc.setSide('left');
              }),
              const SizedBox(width: 8),
              _chip('Право ▶', _side == 'right', () async {
                setState(() => _side = 'right');
                await _svc.setSide('right');
              }),
            ]),
          ),

          const Divider(color: Colors.white12, height: 1),

          // Модель
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🎭 Модель персонажа',
                  style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 6,
                  children: _models.map((m) => _chip(
                    m['label']!,
                    _modelId == m['id'],
                    () => _switchModel(m['id']!),
                  )).toList(),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // Тест анимаций
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: const Text('🎬 Тест анимаций',
              style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
            child: Wrap(
              spacing: 6, runSpacing: 6,
              children: _states.map((s) => GestureDetector(
                onTap: () => _svc.setState(s['id']!),
                child: _chip(s['label']!, false, null),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String label, Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        child,
      ],
    ),
  );

  Widget _chip(String label, bool active, VoidCallback? onTap) {
    const accent = Color(0xFF00E5FF);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? accent.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? accent : Colors.white24),
        ),
        child: Text(label,
          style: TextStyle(
            color: active ? accent : Colors.white54,
            fontSize: 12, fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          )),
      ),
    );
  }
}
