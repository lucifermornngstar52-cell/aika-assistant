import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/minecraft_autopilot_service.dart';
import '../theme/app_theme.dart';

/// Экран игрового автопилота: Айка играет в Minecraft вместо хозяина.
class MinecraftPilotScreen extends StatefulWidget {
  const MinecraftPilotScreen({super.key});

  @override
  State<MinecraftPilotScreen> createState() => _MinecraftPilotScreenState();
}

class _MinecraftPilotScreenState extends State<MinecraftPilotScreen> {
  final _goalCtrl = TextEditingController(
      text: 'Доберись до ближайшего дерева и наруби древесины');
  final _logLines = <String>[];
  bool _starting = false;
  bool _checking = false;
  String? _result;
  String _scheme = MinecraftAutopilotService.kSchemeClassic;

  @override
  void initState() {
    super.initState();
    MinecraftAutopilotService.loadControlScheme().then((_) {
      if (mounted) setState(() => _scheme = MinecraftAutopilotService.controlScheme);
    });
    MinecraftAutopilotService.onLog = (line) {
      if (mounted) {
        setState(() => _logLines.add(line));
      }
    };
  }

  @override
  void dispose() {
    MinecraftAutopilotService.stop();
    MinecraftAutopilotService.onLog = null;
    _goalCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() { _starting = true; _result = null; _logLines.clear(); });

    final err = await MinecraftAutopilotService.checkSupport();
    if (err != null) {
      setState(() { _starting = false; _result = err; });
      return;
    }

    final goal = _goalCtrl.text.trim();
    if (goal.isEmpty) {
      setState(() { _starting = false; _result = 'Напиши цель — что делать в игре'; });
      return;
    }

    final res = await MinecraftAutopilotService.start(goal);
    if (mounted) setState(() { _starting = false; _result = res; });
  }

  void _stop() {
    MinecraftAutopilotService.stop();
    setState(() => _starting = false);
  }

  // ── Жест-тест: проверка нативного слоя без ИИ ──
  static const _ch = MethodChannel('com.aika.assistant/screen_reader');

  Future<void> _testGesture(String kind) async {
    try {
      final size = await _ch.invokeMethod('getScreenSize');
      final w = (size['width'] as num).toDouble();
      final h = (size['height'] as num).toDouble();
      switch (kind) {
        case 'tap':
          await _ch.invokeMethod('tapAt', {'x': w / 2, 'y': h / 2});
          break;
        case 'swipe':
          await _ch.invokeMethod('swipe', {
            'x1': w * 0.8, 'y1': h * 0.4,
            'x2': w * 0.2, 'y2': h * 0.4, 'duration': 300,
          });
          break;
        case 'hold':
          await _ch.invokeMethod('holdTouch', {'x': w / 2, 'y': h / 2, 'duration': 2000});
          break;
        case 'joy':
          await _ch.invokeMethod('joystickMove', {
            'cx': w * 0.11, 'cy': h * 0.82,
            'angle': 0.0, 'duration': 2000,
          });
          break;
        case 'fwd':
          if (MinecraftAutopilotService.controlScheme ==
              MinecraftAutopilotService.kSchemeJoystick) {
            await _ch.invokeMethod('joystickMove', {
              'cx': w * 0.11, 'cy': h * 0.82,
              'angle': 0.0, 'duration': 2000,
            });
          } else {
            await _ch.invokeMethod('holdTouch', {
              'x': w * 0.105, 'y': h * 0.76, 'duration': 2000,
            });
          }
          break;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Жест $kind отправлен — видно результат?'),
          backgroundColor: AikaTheme.surface,
        ));
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Ошибка: ${e.message}'),
          backgroundColor: Colors.red.shade900,
        ));
      }
    }
  }

  Future<void> _launch() async {
    setState(() => _checking = true);
    final ok = await MinecraftAutopilotService.launchMinecraft();
    if (mounted) {
      setState(() { _checking = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Minecraft запускается…' : 'Minecraft не найден на телефоне'),
        backgroundColor: AikaTheme.surface,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = _starting || MinecraftAutopilotService.isRunning;

    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: AikaTheme.surface,
        title: const Text('🎮 Minecraft-пилот'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Описание ──
            _card(
              icon: '🧠',
              title: 'Как это работает',
              child: Text(
                'Айка делает скриншот игры, распознаёт что происходит через '
                'vision-модель и жмёт на экран за тебя: ходит, ломает блоки, '
                'крафтит. Открой Minecraft, поставь игру в нужное место и задай цель.',
                style: TextStyle(color: AikaTheme.textSecondary, fontSize: 13, height: 1.5),
              ),
            ),
            const SizedBox(height: 12),

            // ── Цель ──
            _card(
              icon: '🎯',
              title: 'Цель в игре',
              child: TextField(
                controller: _goalCtrl,
                maxLines: 2,
                enabled: !running,
                style: const TextStyle(color: AikaTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'например: построй башню 3 блока',
                  hintStyle: TextStyle(color: AikaTheme.textSecondary, fontSize: 13),
                  filled: true,
                  fillColor: AikaTheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Кнопки ──
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: running ? null : _start,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Запустить'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AikaTheme.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: running ? _stop : null,
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Стоп'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AikaTheme.userBubble,
                      foregroundColor: AikaTheme.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _checking ? null : _launch,
              icon: const Icon(Icons.grid_on, size: 16),
              label: const Text('Открыть Minecraft'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AikaTheme.textPrimary,
                side: BorderSide(color: AikaTheme.glassWhite),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),

            // ── Результат ──
            if (_result != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AikaTheme.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AikaTheme.glassWhite),
                ),
                child: Text(_result!,
                    style: const TextStyle(color: AikaTheme.textPrimary, fontSize: 13)),
              ),

            // ── Лог ──
            Container(
              height: 280,
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AikaTheme.glassWhite),
              ),
              child: _logLines.isEmpty
                  ? Center(
                      child: Text(
                        running ? '⏳ Пилот думает…' : 'Лог пуст — запусти пилота',
                        style: TextStyle(color: AikaTheme.textSecondary, fontSize: 12),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _logLines.length,
                      itemBuilder: (c, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          _logLines[i],
                          style: const TextStyle(
                            color: AikaTheme.textPrimary,
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            // ── Схема управления ──
            _card(
              icon: '🎮',
              title: 'Схема управления в игре',
              child: Column(
                children: [
                  Text(
                    'Как двигается персонаж. «Классика» — стрелки D-pad (дефолт '
                    'Bedrock). «Джойстик» — левый стик. Выбери неверно — '
                    'Айка будет бегать в сторону!',
                    style: TextStyle(color: AikaTheme.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: MinecraftAutopilotService.kSchemeClassic,
                        label: Text('Классика (D-pad)'),
                        icon: Icon(Icons.gamepad_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: MinecraftAutopilotService.kSchemeJoystick,
                        label: Text('Джойстик'),
                        icon: Icon(Icons.sports_esports_outlined, size: 16),
                      ),
                    ],
                    selected: {_scheme},
                    onSelectionChanged: (v) {
                      setState(() => _scheme = v.first);
                      MinecraftAutopilotService.setControlScheme(v.first);
                    },
                    style: ButtonStyle(
                      foregroundColor: MaterialStateProperty.all(AikaTheme.textPrimary),
                    ),
                    selectedBackgroundColor: AikaTheme.accent,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // ── Жест-тест ──
            _card(
              icon: '🧪',
              title: 'Жест-тест (проверка без ИИ)',
              child: Column(
                children: [
                  Text(
                    'Открой Minecraft, потом жми кнопки — если экран игры реагирует, '
                    'жесты работают, и проблема только в модели.',
                    style: TextStyle(color: AikaTheme.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      _testBtn('Тап центр', 'tap'),
                      _testBtn('Свайп ←', 'swipe'),
                      _testBtn('Держать 2с', 'hold'),
                      _testBtn(
                          _scheme == MinecraftAutopilotService.kSchemeJoystick
                              ? 'Вперёд (стик) 2с' : 'Вперёд (D-pad) 2с',
                          'fwd'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Требуется: Android 11+, включённый Accessibility, Groq-ключ в настройках ИИ.',
              style: TextStyle(color: AikaTheme.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _testBtn(String label, String kind) => OutlinedButton(
        onPressed: () => _testGesture(kind),
        style: OutlinedButton.styleFrom(
          foregroundColor: AikaTheme.textPrimary,
          side: BorderSide(color: AikaTheme.glassWhite),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      );

  Widget _card({required String icon, required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AikaTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AikaTheme.glassWhite),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('$icon $title',
                style: const TextStyle(
                    color: AikaTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
          child,
        ],
      ),
    );
  }
}
