import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════
// F.R.I.D.A.Y. HUD — Iron Man AI v2 (warm teal/green)
// ══════════════════════════════════════════════════════

class FridayMessage {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  const FridayMessage({
    required this.content,
    required this.isUser,
    required this.timestamp,
  });
}

class FridayHud extends StatefulWidget {
  final bool isListening;
  final bool isThinking;
  final String lastResponse;
  final VoidCallback? onMicTap;
  final VoidCallback? onThemeSwitch;
  final List<FridayMessage> messages;
  final TextEditingController? textController;
  final ScrollController? scrollController;
  final Function(String)? onSendMessage;
  final bool wakeWordEnabled;
  final VoidCallback? onToggleWakeWord;
  final bool hasOverlayPermission;
  final VoidCallback? onOverlayPermission;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenCurrency;
  final VoidCallback? onOpenMoodDiary;
  final VoidCallback? onOpenSchedule;
  final VoidCallback? onOpenTelegram;
  final VoidCallback? onOpenAppCommands;
  final String assistantName;
  final String userName;

  const FridayHud({
    Key? key,
    this.isListening = false,
    this.isThinking  = false,
    this.lastResponse = '',
    this.onMicTap,
    this.onThemeSwitch,
    this.messages = const [],
    this.textController,
    this.scrollController,
    this.onSendMessage,
    this.wakeWordEnabled = false,
    this.onToggleWakeWord,
    this.hasOverlayPermission = true,
    this.onOverlayPermission,
    this.onOpenSettings,
    this.onOpenCurrency,
    this.onOpenMoodDiary,
    this.onOpenSchedule,
    this.onOpenTelegram,
    this.onOpenAppCommands,
    this.assistantName = 'F.R.I.D.A.Y.',
    this.userName = '',
  }) : super(key: key);

  @override
  State<FridayHud> createState() => _FridayHudState();
}

class _FridayHudState extends State<FridayHud> with TickerProviderStateMixin {
  // Palette — warm teal + amber + green glow
  static const Color _teal       = Color(0xFF00BFA5);
  static const Color _green      = Color(0xFF69F0AE);
  static const Color _amber      = Color(0xFFFFCA28);
  static const Color _darkBg     = Color(0xFF010E0B);
  static const Color _surface    = Color(0xFF031A12);
  static const Color _accent     = Color(0xFF00E676);
  static const Color _warm       = Color(0xFFFFAB40);
  static const Color _textDim    = Color(0xFF4DB6AC);

  late AnimationController _orbit;
  late AnimationController _pulse;
  late Animation<double>   _pulseAnim;
  late AnimationController _scan;
  late Animation<double>   _scanAnim;
  late AnimationController _hexRotate;
  late AnimationController _dataFlow;
  late Animation<double>   _dataFlowAnim;

  late TextEditingController _textCtrl;
  late ScrollController      _scrollCtrl;

  Timer? _clockTimer;
  String _timeStr = '';
  String _dateStr = '';
  int    _battery = 94;
  double _cpu     = 28.0;
  double _ram     = 51.0;
  Timer? _dataTimer;

  @override
  void initState() {
    super.initState();
    _textCtrl   = widget.textController  ?? TextEditingController();
    _scrollCtrl = widget.scrollController ?? ScrollController();

    _orbit = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _scan = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _scanAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scan, curve: Curves.linear));
    _hexRotate = AnimationController(vsync: this, duration: const Duration(seconds: 12))
      ..repeat();
    _dataFlow = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
    _dataFlowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _dataFlow, curve: Curves.linear));

    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
    _dataTimer  = Timer.periodic(const Duration(seconds: 3), (_) => _randomiseData());
  }

  void _updateClock() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final months = ['ЯНВ','ФЕВ','МАР','АПР','МАЙ','ИЮН','ИЮЛ','АВГ','СЕН','ОКТ','НОЯ','ДЕК'];
    final days   = ['ВС','ПН','ВТ','СР','ЧТ','ПТ','СБ'];
    if (!mounted) return;
    setState(() {
      _timeStr = '$h:$m:$s';
      _dateStr = '${days[now.weekday % 7]}  ${now.day.toString().padLeft(2,'0')} ${months[now.month-1]} ${now.year}';
    });
  }

  void _randomiseData() {
    if (!mounted) return;
    final rng = Random();
    setState(() {
      _battery = (_battery + rng.nextInt(3) - 1).clamp(20, 99);
      _cpu  = (20 + rng.nextDouble() * 40).clamp(10, 80);
      _ram  = (40 + rng.nextDouble() * 30).clamp(30, 90);
    });
  }

  @override
  void dispose() {
    _orbit.dispose(); _pulse.dispose(); _scan.dispose();
    _hexRotate.dispose(); _dataFlow.dispose();
    _clockTimer?.cancel(); _dataTimer?.cancel();
    if (widget.textController  == null) _textCtrl.dispose();
    if (widget.scrollController == null) _scrollCtrl.dispose();
    super.dispose();
  }

  // ─── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      color: _darkBg,
      child: Stack(
        children: [
          _buildGridBackground(),
          _buildCornerDecors(),
          Column(
            children: [
              _buildTopBar(),
              _buildOrbZone(),
              Expanded(child: _buildChatPanel()),
              _buildInputRow(),
              _buildBottomNav(),
            ],
          ),
          if (widget.isListening) _buildListeningOverlay(),
        ],
      ),
    );
  }

  // ─── Grid background ────────────────────────────────────────────────
  Widget _buildGridBackground() {
    return CustomPaint(
      painter: _GridPainter(color: _teal.withOpacity(0.06)),
      size: Size.infinite,
    );
  }

  Widget _buildCornerDecors() {
    return Stack(children: [
      _corner(0, 0, false, false),
      _corner(1, 0, true,  false),
      _corner(0, 1, false, true),
      _corner(1, 1, true,  true),
    ]);
  }

  Widget _corner(int col, int row, bool flipX, bool flipY) {
    return Positioned(
      left:   col == 0 ? 12 : null,
      right:  col == 1 ? 12 : null,
      top:    row == 0 ? 12 : null,
      bottom: row == 1 ? 12 : null,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..scale(flipX ? -1.0 : 1.0, flipY ? -1.0 : 1.0),
        child: SizedBox(
          width: 28, height: 28,
          child: CustomPaint(painter: _CornerPainter(color: _teal)),
        ),
      ),
    );
  }

  // ─── Top bar ───────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: _surface.withOpacity(0.8),
          border: Border(bottom: BorderSide(color: _teal.withOpacity(0.3))),
        ),
        child: Row(
          children: [
            // Status dot
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isListening ? _accent : _teal,
                  boxShadow: [BoxShadow(
                    color: (widget.isListening ? _accent : _teal).withOpacity(0.8 * _pulseAnim.value),
                    blurRadius: 10,
                  )],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(widget.assistantName,
              style: TextStyle(
                color: _green, fontSize: 13, letterSpacing: 2.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: _amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: _amber.withOpacity(0.5)),
              ),
              child: Text('v2.0', style: TextStyle(color: _amber, fontSize: 9, letterSpacing: 1)),
            ),
            const Spacer(),
            // Clock
            Text(_timeStr,
              style: TextStyle(
                color: _teal, fontSize: 15, letterSpacing: 2,
                fontFamily: 'monospace', fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 12),
            // Theme toggle
            GestureDetector(
              onTap: widget.onThemeSwitch,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _teal.withOpacity(0.4)),
                ),
                child: Row(children: [
                  Icon(Icons.swap_horiz, size: 13, color: _teal),
                  const SizedBox(width: 4),
                  Text('ТЕМА', style: TextStyle(color: _teal, fontSize: 9, letterSpacing: 1)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Orb zone ──────────────────────────────────────────────────────────
  Widget _buildOrbZone() {
    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Hex grid background
          AnimatedBuilder(
            animation: _hexRotate,
            builder: (_, __) => CustomPaint(
              painter: _HexGridPainter(
                color: _teal.withOpacity(0.07),
                rotation: _hexRotate.value * 2 * pi,
              ),
              size: const Size(300, 220),
            ),
          ),
          // Scan line
          AnimatedBuilder(
            animation: _scanAnim,
            builder: (_, __) => Positioned(
              top: _scanAnim.value * 200,
              left: 0, right: 0,
              child: Container(
                height: 1.5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.transparent,
                    _green.withOpacity(0.6),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),
          // Orbit rings
          AnimatedBuilder(
            animation: _orbit,
            builder: (_, __) => CustomPaint(
              painter: _FridayOrbitPainter(
                progress: _orbit.value,
                color: _teal,
              ),
              size: const Size(220, 220),
            ),
          ),
          // Central orb
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 80 * _pulseAnim.value,
              height: 80 * _pulseAnim.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _accent.withOpacity(0.9),
                    _teal.withOpacity(0.5),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
                boxShadow: [
                  BoxShadow(color: _green.withOpacity(0.6), blurRadius: 30),
                  BoxShadow(color: _teal.withOpacity(0.3), blurRadius: 60),
                ],
              ),
              child: Center(
                child: Text(
                  widget.isListening ? '👂' : widget.isThinking ? '💭' : '💚',
                  style: const TextStyle(fontSize: 28),
                ),
              ),
            ),
          ),
          // Stats row
          Positioned(
            bottom: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _statChip('CPU', '${_cpu.toStringAsFixed(0)}%', _teal),
                const SizedBox(width: 8),
                _statChip('RAM', '${_ram.toStringAsFixed(0)}%', _green),
                const SizedBox(width: 8),
                _statChip('PWR', '$_battery%', _amber),
              ],
            ),
          ),
          // Date
          Positioned(
            top: 12,
            child: Text(_dateStr,
              style: TextStyle(color: _textDim, fontSize: 10, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Text('$label ', style: TextStyle(color: color.withOpacity(0.7), fontSize: 9, letterSpacing: 1)),
        Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  // ─── Chat panel ───────────────────────────────────────────────────────
  Widget _buildChatPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _teal.withOpacity(0.2)),
      ),
      child: widget.messages.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic_none, color: _teal.withOpacity(0.4), size: 36),
                  const SizedBox(height: 8),
                  Text('Готова к работе, босс.',
                    style: TextStyle(color: _teal.withOpacity(0.5), fontSize: 13, letterSpacing: 1)),
                ],
              ),
            )
          : ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(12),
              itemCount: widget.messages.length,
              itemBuilder: (_, i) {
                final msg = widget.messages[i];
                return _FridayChatBubble(
                  message: msg.content,
                  isUser: msg.isUser,
                  teal: _teal,
                  green: _green,
                  amber: _amber,
                );
              },
            ),
    );
  }

  // ─── Input row ────────────────────────────────────────────────────────
  Widget _buildInputRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _teal.withOpacity(0.3)),
            ),
            child: TextField(
              controller: _textCtrl,
              style: TextStyle(color: _green, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Напечатай команду...',
                hintStyle: TextStyle(color: _teal.withOpacity(0.4), fontSize: 13),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: InputBorder.none,
              ),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) {
                  widget.onSendMessage?.call(v.trim());
                  _textCtrl.clear();
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Mic button
        GestureDetector(
          onTap: widget.onMicTap,
          child: AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  (widget.isListening ? _accent : _teal).withOpacity(0.8),
                  (widget.isListening ? _accent : _teal).withOpacity(0.3),
                ]),
                boxShadow: [BoxShadow(
                  color: (widget.isListening ? _accent : _teal)
                      .withOpacity(widget.isListening ? 0.8 * _pulseAnim.value : 0.3),
                  blurRadius: widget.isListening ? 20 : 10,
                )],
              ),
              child: Icon(
                widget.isListening ? Icons.graphic_eq : Icons.mic,
                color: Colors.black87,
                size: 22,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Send
        GestureDetector(
          onTap: () {
            final v = _textCtrl.text.trim();
            if (v.isNotEmpty) {
              widget.onSendMessage?.call(v);
              _textCtrl.clear();
            }
          },
          child: Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: _teal.withOpacity(0.15),
              border: Border.all(color: _teal.withOpacity(0.4)),
            ),
            child: Icon(Icons.send, color: _teal, size: 20),
          ),
        ),
      ]),
    );
  }

  // ─── Bottom nav ──────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    final items = [
      ('⚙️', 'Настройки', widget.onOpenSettings),
      ('💱', 'Валюта',    widget.onOpenCurrency),
      ('📅', 'Расписание', widget.onOpenSchedule),
      ('📱', 'Команды',   widget.onOpenAppCommands),
      ('✈️', 'Telegram',  widget.onOpenTelegram),
    ];
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: _surface,
          border: Border(top: BorderSide(color: _teal.withOpacity(0.25))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: items.map((e) => GestureDetector(
            onTap: e.$3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.$1, style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 2),
                Text(e.$2, style: TextStyle(color: _textDim, fontSize: 9, letterSpacing: 0.5)),
              ],
            ),
          )).toList(),
        ),
      ),
    );
  }

  // ─── Listening overlay ───────────────────────────────────────────────
  Widget _buildListeningOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: _accent.withOpacity(0.4 * _pulseAnim.value),
                width: 3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Chat bubble ──────────────────────────────────────────────────────────
class _FridayChatBubble extends StatelessWidget {
  final String message;
  final bool isUser;
  final Color teal, green, amber;
  const _FridayChatBubble({
    required this.message, required this.isUser,
    required this.teal, required this.green, required this.amber,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser
              ? teal.withOpacity(0.15)
              : const Color(0xFF031A12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUser ? teal.withOpacity(0.4) : green.withOpacity(0.25),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isUser) ...[
              Text('💚', style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(message,
                style: TextStyle(
                  color: isUser ? teal : green,
                  fontSize: 14, height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Painters ────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final Color color;
  const _GridPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}

class _CornerPainter extends CustomPainter {
  final Color color;
  const _CornerPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 2..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0);
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}

class _HexGridPainter extends CustomPainter {
  final Color color;
  final double rotation;
  const _HexGridPainter({required this.color, required this.rotation});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 0.8..style = PaintingStyle.stroke;
    const r = 22.0;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(rotation);
    canvas.translate(-size.width / 2, -size.height / 2);
    for (double x = -r; x < size.width + r; x += r * 1.5) {
      for (double y = -r; y < size.height + r * 2; y += r * 1.732) {
        final offset = (x / (r * 1.5)).floor().isEven ? 0.0 : r * 0.866;
        _drawHex(canvas, paint, x, y + offset, r);
      }
    }
    canvas.restore();
  }

  void _drawHex(Canvas canvas, Paint paint, double cx, double cy, double r) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = pi / 180 * (60 * i - 30);
      final x = cx + r * cos(angle);
      final y = cy + r * sin(angle);
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HexGridPainter o) => o.rotation != rotation;
}

class _FridayOrbitPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _FridayOrbitPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Ring 1 — teal dashed
    _drawDashedCircle(canvas, cx, cy, 90, color.withOpacity(0.3), 6, progress);
    // Ring 2 — rotating dots
    _drawDotRing(canvas, cx, cy, 70, color.withOpacity(0.5), 6, progress);
    // Ring 3 — inner
    _drawDashedCircle(canvas, cx, cy, 50, color.withOpacity(0.2), 3, -progress * 1.5);
  }

  void _drawDashedCircle(Canvas canvas, double cx, double cy, double r,
      Color color, int dashes, double offset) {
    final paint = Paint()..color = color..strokeWidth = 1.2..style = PaintingStyle.stroke;
    for (int i = 0; i < dashes; i++) {
      final startAngle = (2 * pi / dashes) * i + offset * 2 * pi;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        startAngle,
        2 * pi / dashes * 0.5,
        false,
        paint,
      );
    }
  }

  void _drawDotRing(Canvas canvas, double cx, double cy, double r,
      Color color, int dots, double progress) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    for (int i = 0; i < dots; i++) {
      final angle = (2 * pi / dots) * i + progress * 2 * pi;
      final x = cx + r * cos(angle);
      final y = cy + r * sin(angle);
      canvas.drawCircle(Offset(x, y), 3.0, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FridayOrbitPainter o) => o.progress != progress;
}
