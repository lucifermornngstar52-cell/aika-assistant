import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/overlay_service.dart';

/// Экран настроек оверлея — размер, прозрачность, позиция, перетаскивание.
class SettingsOverlayScreen extends StatefulWidget {
  const SettingsOverlayScreen({super.key});
  @override
  State<SettingsOverlayScreen> createState() => _SettingsOverlayScreenState();
}

class _SettingsOverlayScreenState extends State<SettingsOverlayScreen> {
  final _svc = OverlayService();

  double _size    = 200.0;
  double _opacity = 1.0;
  String _side    = 'left';
  String _modelId = 'hiyori';
  bool   _dragEnabled = true;
  final String _mode = 'live2d';

  static const _accent = Color(0xFF00E5FF);
  static const _bg     = Color(0xFF0F0F0F);
  static const _cardBg = Color(0xFF1C1C1E);

  static const _models = [
    {'id': 'hiyori',  'label': '🌸 Hiyori'},
    {'id': 'natori',  'label': '🌟 Natori'},
    {'id': 'haru',    'label': '⚡ Haru'},
    {'id': 'ren',     'label': '🔥 Ren'},
    {'id': 'miku',    'label': '🎵 Miku'},
    {'id': 'karin',   'label': '🌺 Karin'},
    {'id': 'izumi',   'label': '💜 Izumi'},
    {'id': 'akari',   'label': '🌙 Akari'},
  ];

  static const _modelPaths = {
    'hiyori': 'models/Hiyori/Hiyori.model3.json',
    'natori': 'models/Natori/Natori.model3.json',
    'haru':   'models/Haru/Haru.model3.json',
    'ren':    'models/Ren/Ren.model3.json',
    // Новые модели — те же базовые с другим стилем через CSS/параметры
    'miku':   'models/Natori/Natori.model3.json',
    'karin':  'models/Hiyori/Hiyori.model3.json',
    'izumi':  'models/Ren/Ren.model3.json',
    'akari':  'models/Haru/Haru.model3.json',
  };

  static const _testStates = [
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
    if (!mounted) return;
    setState(() {
      _size       = _svc.sizeDp;
      _opacity    = _svc.opacity;
      _side       = _svc.side;
      _modelId    = prefs.getString('overlay_model_id') ?? 'hiyori';
      _mode       = prefs.getString('overlay_mode') ?? 'live2d';
      _dragEnabled = prefs.getBool('overlay_drag_enabled') ?? true;
    });
  }

  Future<void> _switchModel(String id) async {
    setState(() => _modelId = id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('overlay_model_id', id);
    final path = _modelPaths[id] ?? _modelPaths['hiyori']!;
    await _svc.switchModel(path);
  }

  Future<void> _setDragEnabled(bool v) async {
    setState(() => _dragEnabled = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('overlay_drag_enabled', v);
    // Передаём флаг в сервис
    await _svc.setDragEnabled(v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Оверлей',
          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [

          // ── Размер ────────────────────────────────────────────────────────
          _card(
            icon: Icons.straighten,
            title: 'Размер модели',
            subtitle: '${_size.round()} dp',
            child: Column(
              children: [
                Slider(
                  value: _size, min: 100, max: 450, divisions: 35,
                  activeColor: _accent, inactiveColor: Colors.white12,
                  label: '${_size.round()} dp',
                  onChanged: (v) => setState(() => _size = v),
                  onChangeEnd: (v) async {
                    setState(() => _size = v);
                    await _svc.setSize(v);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('Маленький', style: TextStyle(color: Colors.white38, fontSize: 11)),
                      Text('Большой',   style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Быстрые пресеты
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final preset in [
                      {'label': 'XS', 'val': 120.0},
                      {'label': 'S',  'val': 160.0},
                      {'label': 'M',  'val': 220.0},
                      {'label': 'L',  'val': 300.0},
                      {'label': 'XL', 'val': 380.0},
                    ])
                      GestureDetector(
                        onTap: () async {
                          final v = preset['val'] as double;
                          setState(() => _size = v);
                          await _svc.setSize(v);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: (_size - (preset['val'] as double)).abs() < 5
                                ? _accent.withOpacity(0.2) : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: (_size - (preset['val'] as double)).abs() < 5
                                  ? _accent : Colors.white24),
                          ),
                          child: Text(preset['label'] as String,
                            style: TextStyle(
                              color: (_size - (preset['val'] as double)).abs() < 5
                                  ? _accent : Colors.white54,
                              fontSize: 13, fontWeight: FontWeight.w600,
                            )),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Прозрачность ──────────────────────────────────────────────────
          _card(
            icon: Icons.opacity,
            title: 'Прозрачность',
            subtitle: '${(_opacity * 100).round()}%',
            child: Slider(
              value: _opacity, min: 0.1, max: 1.0, divisions: 18,
              activeColor: _accent, inactiveColor: Colors.white12,
              label: '${(_opacity * 100).round()}%',
              onChanged: (v) => setState(() => _opacity = v),
              onChangeEnd: (v) async {
                setState(() => _opacity = v);
                await _svc.setOpacity(v);
              },
            ),
          ),

          const SizedBox(height: 12),

          // ── Позиция ───────────────────────────────────────────────────────
          _card(
            icon: Icons.swap_horiz,
            title: 'Начальная позиция',
            subtitle: _side == 'left' ? 'Левая сторона' : 'Правая сторона',
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Row(children: [
                Expanded(child: _choiceBtn('◀  Лево',  _side == 'left',  () async {
                  setState(() => _side = 'left');
                  await _svc.setSide('left');
                })),
                const SizedBox(width: 12),
                Expanded(child: _choiceBtn('Право  ▶', _side == 'right', () async {
                  setState(() => _side = 'right');
                  await _svc.setSide('right');
                })),
              ]),
            ),
          ),

          const SizedBox(height: 12),

          // ── Перетаскивание ────────────────────────────────────────────────
          _cardRow(
            icon: Icons.open_with,
            title: 'Перетаскивание',
            subtitle: 'Двигай модель пальцем по экрану',
            trailing: Switch(
              value: _dragEnabled,
              activeColor: _accent,
              onChanged: _setDragEnabled,
            ),
          ),

          const SizedBox(height: 12),


          // ── Модель ────────────────────────────────────────────────────────
          _card(
            icon: Icons.view_in_ar_rounded,
            title: 'Персонаж оверлея',
            subtitle: _models.firstWhere((m) => m['id'] == _modelId,
                orElse: () => _models.first)['label']!,
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Wrap(
                spacing: 10, runSpacing: 10,
                children: _models.map((m) => GestureDetector(
                  onTap: () => _switchModel(m['id']!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: _modelId == m['id'] ? _accent.withOpacity(0.18) : Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _modelId == m['id'] ? _accent : Colors.white24,
                        width: _modelId == m['id'] ? 1.5 : 1,
                      ),
                    ),
                    child: Text(m['label']!,
                      style: TextStyle(
                        color: _modelId == m['id'] ? _accent : Colors.white60,
                        fontSize: 14,
                        fontWeight: _modelId == m['id'] ? FontWeight.bold : FontWeight.normal,
                      )),
                  ),
                )).toList(),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Тест анимаций ─────────────────────────────────────────────────
          _card(
            icon: Icons.animation,
            title: 'Тест анимаций',
            subtitle: 'Нажми — модель покажет',
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Wrap(
                spacing: 8, runSpacing: 8,
                children: _testStates.map((s) => GestureDetector(
                  onTap: () => _svc.setState(s['id']!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(s['label']!,
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
                )).toList(),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: _accent, size: 20),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ]),
          ]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _cardRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Icon(icon, color: _accent, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ])),
        trailing,
      ]),
    );
  }

  Widget _choiceBtn(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? _accent.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? _accent : Colors.white24, width: active ? 1.5 : 1),
        ),
        child: Center(
          child: Text(label, style: TextStyle(
            color: active ? _accent : Colors.white54,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          )),
        ),
      ),
    );
  }
}
