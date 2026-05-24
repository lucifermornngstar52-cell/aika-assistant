import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════
// JARVIS HUD WIDGET — живой интерфейс в стиле Iron Man
// ══════════════════════════════════════════════════════

class JarvisHud extends StatefulWidget {
  final bool isListening;
  final bool isThinking;
  final String lastResponse;
  final VoidCallback? onMicTap;
  final VoidCallback? onThemeSwitch;

  const JarvisHud({
    Key? key,
    this.isListening = false,
    this.isThinking = false,
    this.lastResponse = '',
    this.onMicTap,
    this.onThemeSwitch,
  }) : super(key: key);

  @override
  State<JarvisHud> createState() => _JarvisHudState();
}

class _JarvisHudState extends State<JarvisHud> with TickerProviderStateMixin {
  // Кольца
  late AnimationController _ring1Ctrl;
  late AnimationController _ring2Ctrl;
  late AnimationController _ring3Ctrl;
  // Пульс реактора
  late AnimationController _reactorCtrl;
  late Animation<double> _reactorPulse;
  // Глitch / scan line
  late AnimationController _scanCtrl;
  late Animation<double> _scanAnim;
  // Radar sweep
  late AnimationController _radarCtrl;
  // Частицы
  late AnimationController _particleCtrl;

  // HUD данные
  int _batteryLevel = 85;
  double _cpuLoad = 42.0;
  double _ramUsage = 67.0;
  Timer? _dataTimer;

  @override
  void initState() {
    super.initState();

    _ring1Ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat();
    _ring2Ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 5))
      ..repeat(reverse: false);
    _ring3Ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 12))
      ..repeat();

    _reactorCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _reactorPulse = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _reactorCtrl, curve: Curves.easeInOut));

    _scanCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _scanAnim = Tween<double>(begin: 0.0, end: 1.0).animate(_scanCtrl);

    _radarCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat();

    _particleCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat();

    // Симуляция реальных данных
    _dataTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        setState(() {
          _cpuLoad = 30 + Random().nextDouble() * 50;
          _ramUsage = 55 + Random().nextDouble() * 30;
        });
      }
    });
  }

  @override
  void dispose() {
    _ring1Ctrl.dispose();
    _ring2Ctrl.dispose();
    _ring3Ctrl.dispose();
    _reactorCtrl.dispose();
    _scanCtrl.dispose();
    _radarCtrl.dispose();
    _particleCtrl.dispose();
    _dataTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Container(
      width: size.width,
      height: size.height,
      color: const Color(0xFF000810),
      child: Stack(
        children: [
          // Фоновая сетка
          CustomPaint(painter: _GridPainter(), size: Size(size.width, size.height)),
          // Scan line
          _buildScanLine(size),
          // Верхняя строка статуса
          _buildTopBar(),
          // Центральный реактор
          _buildReactor(size),
          // Левая панель диагностики
          _buildLeftPanel(),
          // Правая панель
          _buildRightPanel(),
          // Нижняя панель
          _buildBottomBar(size),
          // Ответ ассистента
          if (widget.lastResponse.isNotEmpty) _buildResponseBubble(),
        ],
      ),
    );
  }

  Widget _buildScanLine(Size size) {
    return AnimatedBuilder(
      animation: _scanAnim,
      builder: (_, __) => Positioned(
        top: _scanAnim.value * size.height,
        left: 0,
        right: 0,
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.transparent,
              const Color(0xFF00D4FF).withOpacity(0.15),
              const Color(0xFF00D4FF).withOpacity(0.3),
              const Color(0xFF00D4FF).withOpacity(0.15),
              Colors.transparent,
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 40,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('J.A.R.V.I.S',
                style: TextStyle(
                  color: Color(0xFF00D4FF),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                  shadows: [Shadow(color: Color(0xFF00D4FF), blurRadius: 12)],
                )),
            const Text('SYSTEM ONLINE',
                style: TextStyle(color: Color(0xFF00FF88), fontSize: 10, letterSpacing: 3)),
          ]),
          Row(children: [
            GestureDetector(
              onTap: widget.onThemeSwitch,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.5), width: 1),
                  borderRadius: BorderRadius.circular(8),
                  color: const Color(0xFF001830),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('🌸', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 4),
                  Text('АЙКА', style: TextStyle(color: Color(0xFF00D4FF), fontSize: 10, letterSpacing: 2)),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            _buildCircularGauge('BATTERY', _batteryLevel.toDouble(), 100, const Color(0xFF00D4FF)),
          ]),
        ],
      ),
    );
  }

  Widget _buildCircularGauge(String label, double value, double max, Color color) {
    return SizedBox(
      width: 70,
      height: 70,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(70, 70),
            painter: _ArcPainter(value / max, color),
          ),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${value.toInt()}${label == "BATTERY" ? "%" : "°"}',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: color, blurRadius: 8)],
                )),
            Text(label, style: const TextStyle(color: Color(0xFF446677), fontSize: 7, letterSpacing: 1)),
          ]),
        ],
      ),
    );
  }

  Widget _buildReactor(Size size) {
    return Positioned(
      top: size.height * 0.18,
      left: 0,
      right: 0,
      child: Center(
        child: SizedBox(
          width: 260,
          height: 260,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Внешнее кольцо 1 (медленное)
              AnimatedBuilder(
                animation: _ring1Ctrl,
                builder: (_, __) => Transform.rotate(
                  angle: _ring1Ctrl.value * 2 * pi,
                  child: CustomPaint(
                    size: const Size(260, 260),
                    painter: _RingPainter(130, 3, const Color(0xFF00D4FF), dashes: 60),
                  ),
                ),
              ),
              // Кольцо 2 (обратное)
              AnimatedBuilder(
                animation: _ring2Ctrl,
                builder: (_, __) => Transform.rotate(
                  angle: -_ring2Ctrl.value * 2 * pi,
                  child: CustomPaint(
                    size: const Size(200, 200),
                    painter: _RingPainter(100, 2, const Color(0xFF0088FF), dashes: 40),
                  ),
                ),
              ),
              // Radar sweep
              AnimatedBuilder(
                animation: _radarCtrl,
                builder: (_, __) => CustomPaint(
                  size: const Size(180, 180),
                  painter: _RadarPainter(_radarCtrl.value),
                ),
              ),
              // Кольцо 3 (внутреннее)
              AnimatedBuilder(
                animation: _ring3Ctrl,
                builder: (_, __) => Transform.rotate(
                  angle: _ring3Ctrl.value * 2 * pi,
                  child: CustomPaint(
                    size: const Size(150, 150),
                    painter: _RingPainter(75, 1.5, const Color(0xFF00FFCC), dashes: 24),
                  ),
                ),
              ),
              // Реактор (центр)
              AnimatedBuilder(
                animation: _reactorPulse,
                builder: (_, __) => GestureDetector(
                  onTap: widget.onMicTap,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF001830),
                      border: Border.all(color: const Color(0xFF00D4FF), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: (widget.isListening
                              ? const Color(0xFF00FF88)
                              : const Color(0xFF00D4FF))
                              .withOpacity(_reactorPulse.value * 0.8),
                          blurRadius: 30 * _reactorPulse.value,
                          spreadRadius: 8 * _reactorPulse.value,
                        ),
                      ],
                    ),
                    child: Icon(
                      widget.isListening ? Icons.mic : (widget.isThinking ? Icons.psychology : Icons.blur_on),
                      color: widget.isListening
                          ? const Color(0xFF00FF88)
                          : const Color(0xFF00D4FF),
                      size: 36,
                    ),
                  ),
                ),
              ),
              // Статус под реактором
              Positioned(
                bottom: 10,
                child: Text(
                  widget.isListening ? 'LISTENING...' : (widget.isThinking ? 'PROCESSING...' : 'STANDBY'),
                  style: TextStyle(
                    color: widget.isListening ? const Color(0xFF00FF88) : const Color(0xFF446677),
                    fontSize: 10,
                    letterSpacing: 3,
                    shadows: [Shadow(
                      color: widget.isListening ? const Color(0xFF00FF88) : Colors.transparent,
                      blurRadius: 8,
                    )],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeftPanel() {
    return Positioned(
      top: 160,
      left: 12,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _hudLabel('SYSTEM DIAGNOSTICS'),
        const SizedBox(height: 8),
        _hudBar('CPU', _cpuLoad, const Color(0xFF00D4FF)),
        const SizedBox(height: 6),
        _hudBar('RAM', _ramUsage, const Color(0xFF0088FF)),
        const SizedBox(height: 6),
        _hudBar('NET', 23, const Color(0xFF00FFCC)),
        const SizedBox(height: 12),
        _hudLabel('CORE TEMP'),
        const SizedBox(height: 4),
        _buildCircularGauge('TEMP', 38, 100, const Color(0xFFFF4444)),
      ]),
    );
  }

  Widget _buildRightPanel() {
    return Positioned(
      top: 180,
      right: 12,
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _hudLabel('QUICK ACCESS'),
        const SizedBox(height: 8),
        ...[
          'Telegram', 'YouTube', 'VK', 'Яндекс', 'Chrome', 'Maps',
        ].map((app) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(app, style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 11, letterSpacing: 1)),
              const SizedBox(width: 6),
              Container(width: 6, height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF00FF88),
                  boxShadow: [BoxShadow(color: Color(0xFF00FF88), blurRadius: 4)],
                )),
            ],
          ),
        )).toList(),
      ]),
    );
  }

  Widget _buildBottomBar(Size size) {
    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _hudIconButton(Icons.settings, onTap: () {}),
            _hudIconButton(Icons.keyboard_arrow_up, onTap: () {}),
            _hudIconButton(Icons.mic, onTap: widget.onMicTap, active: widget.isListening),
            _hudIconButton(Icons.grid_view, onTap: () {}),
          ],
        ),
      ),
    );
  }

  Widget _buildResponseBubble() {
    return Positioned(
      bottom: 90,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF001830).withOpacity(0.9),
          border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.5), width: 1),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.1), blurRadius: 12)],
        ),
        child: Text(
          widget.lastResponse,
          style: const TextStyle(color: Color(0xFFCCEEFF), fontSize: 13, letterSpacing: 0.5),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _hudLabel(String text) => Text(
    text,
    style: const TextStyle(color: Color(0xFF446677), fontSize: 9, letterSpacing: 2),
  );

  Widget _hudBar(String label, double value, Color color) {
    return SizedBox(
      width: 110,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: Color(0xFF668899), fontSize: 9, letterSpacing: 1)),
          Text('${value.toInt()}%', style: TextStyle(color: color, fontSize: 9)),
        ]),
        const SizedBox(height: 3),
        Stack(children: [
          Container(height: 4, width: 110, decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(2),
          )),
          Container(height: 4, width: 110 * value / 100, decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 6)],
          )),
        ]),
      ]),
    );
  }

  Widget _hudIconButton(IconData icon, {VoidCallback? onTap, bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: _reactorPulse,
        builder: (_, __) => Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF001830),
            border: Border.all(
              color: active
                  ? const Color(0xFF00FF88)
                  : const Color(0xFF00D4FF).withOpacity(0.6),
              width: 1.5,
            ),
            boxShadow: active ? [
              BoxShadow(
                color: const Color(0xFF00FF88).withOpacity(_reactorPulse.value * 0.7),
                blurRadius: 16,
                spreadRadius: 2,
              )
            ] : [
              BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.15), blurRadius: 8),
            ],
          ),
          child: Icon(icon, color: active ? const Color(0xFF00FF88) : const Color(0xFF00D4FF), size: 22),
        ),
      ),
    );
  }
}

// ═══════════ PAINTERS ═══════════

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00D4FF).withOpacity(0.04)
      ..strokeWidth = 0.5;
    const step = 30.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _ArcPainter extends CustomPainter {
  final double value;
  final Color color;
  _ArcPainter(this.value, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final bgPaint = Paint()
      ..color = color.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2, value * 2 * pi, false, fgPaint,
    );
  }
  @override bool shouldRepaint(_ArcPainter old) => old.value != value;
}

class _RingPainter extends CustomPainter {
  final double radius;
  final double strokeWidth;
  final Color color;
  final int dashes;
  _RingPainter(this.radius, this.strokeWidth, this.color, {this.dashes = 40});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final center = Offset(size.width / 2, size.height / 2);
    final dashAngle = 2 * pi / dashes;
    for (int i = 0; i < dashes; i++) {
      if (i % 3 == 2) continue; // пропускаем каждый 3й — получаются пунктиры
      final startAngle = i * dashAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, dashAngle * 0.6, false, paint,
      );
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _RadarPainter extends CustomPainter {
  final double sweep;
  _RadarPainter(this.sweep);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final sweepAngle = sweep * 2 * pi;

    // Radar sweep gradient
    final paint = Paint()..shader = SweepGradient(
      startAngle: sweepAngle - 0.8,
      endAngle: sweepAngle,
      colors: [Colors.transparent, const Color(0xFF00D4FF).withOpacity(0.3)],
      center: Alignment.center,
    ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);

    // Sweep line
    final linePaint = Paint()
      ..color = const Color(0xFF00D4FF).withOpacity(0.8)
      ..strokeWidth = 1.5;
    canvas.drawLine(center,
      Offset(center.dx + cos(sweepAngle) * radius, center.dy + sin(sweepAngle) * radius),
      linePaint,
    );
  }
  @override bool shouldRepaint(_RadarPainter old) => old.sweep != sweep;
}
