import 'package:flutter/material.dart';
import '../services/overlay_service.dart';

class OverlaySettingsWidget extends StatefulWidget {
  const OverlaySettingsWidget({super.key});
  @override
  State<OverlaySettingsWidget> createState() => _OverlaySettingsWidgetState();
}

class _OverlaySettingsWidgetState extends State<OverlaySettingsWidget> {
  final _svc = OverlayService();

  double _size    = 170.0;
  double _opacity = 1.0;
  String _side    = 'left';
  bool   _mirror  = false;

  static const _anims = [
    {'id': 'idle',       'label': '🧍 Idle'},
    {'id': 'SambaDance', 'label': '💃 Самба'},
    {'id': 'agree',      'label': '👍 Кивок'},
    {'id': 'headShake',  'label': '🤔 Отказ'},
    {'id': 'walk',       'label': '🚶 Ходьба'},
    {'id': 'run',        'label': '🏃 Бег'},
    {'id': 'sad_pose',   'label': '😢 Грусть'},
    {'id': 'sneak_pose', 'label': '🥷 Тихо'},
  ];

  @override
  void initState() {
    super.initState();
    _size    = _svc.sizeDp;
    _opacity = _svc.opacity;
    _side    = _svc.side;
    _mirror  = _svc.mirror;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: const [
              Text('🤖', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Text('Настройки 3D модели',
                  style: TextStyle(color: Color(0xFF00E5FF),
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
          ),
          const Divider(color: Colors.white12),

          _buildSection(
            '📐 Размер: \${_size.round()} dp',
            Slider(
              value: _size, min: 80, max: 350, divisions: 27,
              activeColor: const Color(0xFF00E5FF),
              inactiveColor: Colors.white12,
              onChanged: (v) => setState(() => _size = v),
              onChangeEnd: (v) async { setState(() => _size = v); await _svc.setSize(v); },
            ),
          ),

          _buildSection(
            '👁 Прозрачность: \${(_opacity * 100).round()}%',
            Slider(
              value: _opacity, min: 0.2, max: 1.0, divisions: 16,
              activeColor: const Color(0xFF00E5FF),
              inactiveColor: Colors.white12,
              onChanged: (v) => setState(() => _opacity = v),
              onChangeEnd: (v) async { setState(() => _opacity = v); await _svc.setOpacity(v); },
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              const Text('📌 Позиция: ',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(width: 8),
              _sideBtn('◀ Лево', 'left'),
              const SizedBox(width: 8),
              _sideBtn('Право ▶', 'right'),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('🪞 Зеркало',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                Switch(
                  value: _mirror,
                  activeColor: const Color(0xFF00E5FF),
                  onChanged: (v) async {
                    setState(() => _mirror = v);
                    await _svc.setMirror(v);
                  },
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white12),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('🎬 Тест анимаций',
                style: TextStyle(color: Color(0xFF00E5FF),
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Wrap(
              spacing: 6, runSpacing: 6,
              children: _anims.map((anim) {
                return GestureDetector(
                  onTap: () => _svc.playAnimation(anim['id']!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFF00E5FF).withOpacity(0.35)),
                    ),
                    child: Text(anim['label']!,
                        style: const TextStyle(
                            color: Color(0xFF00E5FF), fontSize: 11)),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String label, Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        child,
      ],
    ),
  );

  Widget _sideBtn(String label, String value) {
    final sel = _side == value;
    return GestureDetector(
      onTap: () async {
        setState(() => _side = value);
        await _svc.setSide(value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF00E5FF).withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: sel ? const Color(0xFF00E5FF) : Colors.white24),
        ),
        child: Text(label,
            style: TextStyle(
              color: sel ? const Color(0xFF00E5FF) : Colors.white38,
              fontSize: 12, fontWeight: FontWeight.w500,
            )),
      ),
    );
  }
}
