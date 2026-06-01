import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════
// JARVIS HUD — Iron Man style interface
// ══════════════════════════════════════════════════════

class JarvisMessage {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  const JarvisMessage({
    required this.content,
    required this.isUser,
    required this.timestamp,
  });
}

class JarvisHud extends StatefulWidget {
  final bool isListening;
  final bool isThinking;
  final String lastResponse;
  final VoidCallback? onMicTap;
  final VoidCallback? onThemeSwitch;

  final List<JarvisMessage> messages;
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

  const JarvisHud({
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
    this.assistantName = 'J.A.R.V.I.S',
    this.userName = '',
  }) : super(key: key);

  @override
  State<JarvisHud> createState() => _JarvisHudState();
}

class _JarvisHudState extends State<JarvisHud> with TickerProviderStateMixin {
  // Palette
  static const Color _cyan     = Color(0xFF00E5FF);
  static const Color _blue     = Color(0xFF1565C0);
  static const Color _darkBg   = Color(0xFF020B18);
  static const Color _surface  = Color(0xFF041525);
  static const Color _gold     = Color(0xFFFFC107);
  static const Color _red      = Color(0xFFFF1744);

  late AnimationController _ring1;
  late AnimationController _ring2;
  late AnimationController _ring3;
  late AnimationController _pulse;
  late Animation<double>   _pulseAnim;
  late AnimationController _scan;
  late Animation<double>   _scanAnim;
  late AnimationController _glitch;

  late TextEditingController _textCtrl;
  late ScrollController      _scrollCtrl;

  Timer? _clockTimer;
  String _timeStr = '';
  String _dateStr = '';
  int    _battery = 87;
  double _cpu     = 34.0;
  double _ram     = 58.0;
  Timer? _dataTimer;

  @override
  void initState() {
    super.initState();
    _textCtrl   = widget.textController  ?? TextEditingController();
    _scrollCtrl = widget.scrollController ?? ScrollController();

    _ring1 = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
    _ring2 = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat(reverse: true);
    _ring3 = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _scan  = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _scanAnim = Tween<double>(begin: 0, end: 1).animate(_scan);
    _glitch = AnimationController(vsync: this, duration: const Duration(milliseconds: 80));

    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
    _dataTimer  = Timer.periodic(const Duration(seconds: 3), (_) => _randomizeData());
  }

  void _updateClock() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final weekdays = ['ВС', 'ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ'];
    final months   = ['ЯНВ','ФЕВ','МАР','АПР','МАЙ','ИЮН','ИЮЛ','АВГ','СЕН','ОКТ','НОЯ','ДЕК'];
    if (mounted) setState(() {
      _timeStr = '$h:$m:$s';
      _dateStr = '${weekdays[now.weekday % 7]} ${now.day} ${months[now.month - 1]} ${now.year}';
    });
  }

  void _randomizeData() {
    if (!mounted) return;
    final rng = Random();
    setState(() {
      _cpu = 20 + rng.nextDouble() * 50;
      _ram = 40 + rng.nextDouble() * 40;
    });
  }

  @override
  void dispose() {
    _ring1.dispose(); _ring2.dispose(); _ring3.dispose();
    _pulse.dispose(); _scan.dispose(); _glitch.dispose();
    _clockTimer?.cancel();
    _dataTimer?.cancel();
    if (widget.textController == null) _textCtrl.dispose();
    if (widget.scrollController == null) _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Builders ─────────────────────────────────────────────────────────────

  Widget _buildHexagonReactor() {
    return AnimatedBuilder(
      animation: Listenable.merge([_ring1, _ring2, _ring3, _pulse]),
      builder: (_, __) {
        final listening = widget.isListening;
        final thinking  = widget.isThinking;
        return SizedBox(
          width: 160, height: 160,
          child: CustomPaint(
            painter: _JarvisReactorPainter(
              ring1: _ring1.value,
              ring2: _ring2.value,
              ring3: _ring3.value,
              pulse: _pulseAnim.value,
              isListening: listening,
              isThinking: thinking,
              cyan: _cyan,
              gold: _gold,
            ),
          ),
        );
      },
    );
  }

  Widget _buildScanLine() {
    return AnimatedBuilder(
      animation: _scanAnim,
      builder: (_, __) {
        return Positioned(
          top: MediaQuery.of(context).size.height * _scanAnim.value * 0.4,
          left: 0, right: 0,
          child: Container(
            height: 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  _cyan.withOpacity(0.15),
                  _cyan.withOpacity(0.4),
                  _cyan.withOpacity(0.15),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          // Assistant name + status
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.assistantName.toUpperCase(),
                style: TextStyle(
                  color: _cyan,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                  shadows: [Shadow(color: _cyan.withOpacity(0.6), blurRadius: 8)],
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.isListening ? _gold
                           : widget.isThinking  ? _red
                           : Colors.green,
                      boxShadow: [BoxShadow(
                        color: (widget.isListening ? _gold
                               : widget.isThinking  ? _red
                               : Colors.green).withOpacity(0.8),
                        blurRadius: 6,
                      )],
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    widget.isListening ? 'СЛУШАЮ...'
                        : widget.isThinking ? 'АНАЛИЗИРУЮ...'
                        : 'ОНЛАЙН',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),

          // Clock
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_timeStr,
                  style: TextStyle(
                    color: _cyan,
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                  )),
              Text(_dateStr,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                    letterSpacing: 1,
                  )),
            ],
          ),

          const SizedBox(width: 8),
          // Settings icon
          GestureDetector(
            onTap: widget.onOpenSettings,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _cyan.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _cyan.withOpacity(0.2)),
              ),
              child: Icon(Icons.settings_outlined, color: _cyan.withOpacity(0.7), size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _statBadge('CPU', '${_cpu.round()}%', _cpu / 100),
          const SizedBox(width: 8),
          _statBadge('RAM', '${_ram.round()}%', _ram / 100),
          const SizedBox(width: 8),
          _statBadge('BAT', '$_battery%', _battery / 100),
          const Spacer(),
          // Wake word toggle
          GestureDetector(
            onTap: widget.onToggleWakeWord,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: widget.wakeWordEnabled
                    ? _cyan.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.wakeWordEnabled
                      ? _cyan.withOpacity(0.6)
                      : Colors.white24,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hearing,
                      size: 13,
                      color: widget.wakeWordEnabled ? _cyan : Colors.white38),
                  const SizedBox(width: 4),
                  Text(
                    widget.wakeWordEnabled ? 'СЛУХ' : 'ВЫКЛ',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: widget.wakeWordEnabled ? _cyan : Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBadge(String label, String value, double ratio) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _cyan.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8, letterSpacing: 1)),
          const SizedBox(height: 3),
          SizedBox(
            width: 48,
            child: Stack(
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: ratio.clamp(0.0, 1.0),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: ratio > 0.8 ? _red : ratio > 0.6 ? _gold : _cyan,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [BoxShadow(
                        color: _cyan.withOpacity(0.4), blurRadius: 3,
                      )],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                color: _cyan, fontSize: 10, fontWeight: FontWeight.bold,
              )),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      _QuickAction(icon: Icons.currency_exchange, label: 'Курсы', onTap: widget.onOpenCurrency),
      _QuickAction(icon: Icons.book_outlined, label: 'Дневник', onTap: widget.onOpenMoodDiary),
      _QuickAction(icon: Icons.calendar_today, label: 'График', onTap: widget.onOpenSchedule),
      _QuickAction(icon: Icons.send_rounded, label: 'Telegram', onTap: widget.onOpenTelegram),
      _QuickAction(icon: Icons.flash_on, label: 'Команды', onTap: widget.onOpenAppCommands),
      _QuickAction(icon: Icons.swap_horiz, label: 'Тема', onTap: widget.onThemeSwitch),
    ];

    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: actions.length,
        itemBuilder: (_, i) {
          final a = actions[i];
          return GestureDetector(
            onTap: a.onTap,
            child: Container(
              width: 62,
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _cyan.withOpacity(0.2)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(a.icon, color: _cyan, size: 20),
                  const SizedBox(height: 5),
                  Text(a.label,
                      style: const TextStyle(
                        color: Colors.white60, fontSize: 9, letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessageList() {
    if (widget.messages.isEmpty) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hexagon_outlined, color: _cyan.withOpacity(0.2), size: 48),
              const SizedBox(height: 12),
              Text(
                'СИСТЕМА ГОТОВА',
                style: TextStyle(
                  color: _cyan.withOpacity(0.4),
                  fontSize: 12,
                  letterSpacing: 3,
                ),
              ),
              if (widget.userName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Добро пожаловать, ${widget.userName}',
                  style: TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Expanded(
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: widget.messages.length,
        itemBuilder: (_, i) => _buildMessage(widget.messages[i]),
      ),
    );
  }

  Widget _buildMessage(JarvisMessage msg) {
    final isUser = msg.isUser;
    final h = msg.timestamp.hour.toString().padLeft(2, '0');
    final m = msg.timestamp.minute.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            // Jarvis avatar dot
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _cyan.withOpacity(0.1),
                border: Border.all(color: _cyan.withOpacity(0.4)),
              ),
              child: Center(
                child: Text('J',
                    style: TextStyle(
                      color: _cyan, fontSize: 11, fontWeight: FontWeight.bold,
                    )),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser
                        ? _blue.withOpacity(0.35)
                        : _cyan.withOpacity(0.06),
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(16),
                      topRight:    const Radius.circular(16),
                      bottomLeft:  Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4  : 16),
                    ),
                    border: Border.all(
                      color: isUser
                          ? _blue.withOpacity(0.4)
                          : _cyan.withOpacity(0.18),
                    ),
                    boxShadow: isUser ? [] : [
                      BoxShadow(
                        color: _cyan.withOpacity(0.05),
                        blurRadius: 8, spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Text(
                    msg.content,
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text('$h:$m',
                    style: const TextStyle(color: Colors.white24, fontSize: 9)),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _blue.withOpacity(0.2),
                border: Border.all(color: _blue.withOpacity(0.5)),
              ),
              child: const Center(
                child: Icon(Icons.person, color: Colors.white60, size: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThinkingIndicator() {
    if (!widget.isThinking) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _cyan.withOpacity(0.1),
              border: Border.all(color: _cyan.withOpacity(0.4)),
            ),
            child: Center(
              child: Text('J', style: TextStyle(color: _cyan, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _cyan.withOpacity(0.06),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16), topRight: Radius.circular(16),
                bottomRight: Radius.circular(16), bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: _cyan.withOpacity(0.18)),
            ),
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final offset = i * 0.33;
                    final v = sin((_pulse.value * 2 * pi) + offset * 2 * pi);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Container(
                        width: 6, height: 6 + v.abs() * 6,
                        decoration: BoxDecoration(
                          color: _cyan.withOpacity(0.5 + v.abs() * 0.5),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: _darkBg,
        border: Border(top: BorderSide(color: _cyan.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          // Mic button
          GestureDetector(
            onTap: widget.onMicTap,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) {
                final isActive = widget.isListening;
                return Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? _gold.withOpacity(0.15 + _pulseAnim.value * 0.1)
                        : _cyan.withOpacity(0.1),
                    border: Border.all(
                      color: isActive ? _gold : _cyan.withOpacity(0.4),
                      width: isActive ? 2 : 1,
                    ),
                    boxShadow: isActive
                        ? [BoxShadow(color: _gold.withOpacity(0.3), blurRadius: 12)]
                        : [BoxShadow(color: _cyan.withOpacity(0.15), blurRadius: 8)],
                  ),
                  child: Icon(
                    isActive ? Icons.mic : Icons.mic_none,
                    color: isActive ? _gold : _cyan,
                    size: 22,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          // Text input
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _cyan.withOpacity(0.2)),
              ),
              child: TextField(
                controller: _textCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) {
                    widget.onSendMessage?.call(v.trim());
                    _textCtrl.clear();
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Введите команду...',
                  hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.send_rounded, color: _cyan.withOpacity(0.7), size: 20),
                    onPressed: () {
                      final v = _textCtrl.text.trim();
                      if (v.isNotEmpty) {
                        widget.onSendMessage?.call(v);
                        _textCtrl.clear();
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Left decorative bars
          _buildSideBars(reverse: true),
          const SizedBox(width: 16),
          _buildHexagonReactor(),
          const SizedBox(width: 16),
          // Right decorative bars
          _buildSideBars(reverse: false),
        ],
      ),
    );
  }

  Widget _buildSideBars({required bool reverse}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: reverse ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: List.generate(5, (i) {
        final widths = [40.0, 28.0, 48.0, 20.0, 36.0];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: AnimatedBuilder(
            animation: _ring1,
            builder: (_, __) {
              final phase = (i * 0.2 + _ring1.value) % 1.0;
              final opacity = 0.2 + sin(phase * 2 * pi).abs() * 0.5;
              return Container(
                width: widths[i],
                height: 2,
                decoration: BoxDecoration(
                  color: _cyan.withOpacity(opacity),
                  borderRadius: BorderRadius.circular(1),
                  boxShadow: [BoxShadow(color: _cyan.withOpacity(opacity * 0.5), blurRadius: 3)],
                ),
              );
            },
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBg,
      body: SafeArea(
        child: Stack(
          children: [
            // Scan line overlay
            _buildScanLine(),
            // Grid background
            CustomPaint(
              size: Size(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height),
              painter: _GridPainter(color: _cyan),
            ),
            // Main content
            Column(
              children: [
                _buildTopBar(),
                _buildSystemStats(),
                _buildCenterPanel(),
                _buildQuickActions(),
                const SizedBox(height: 4),
                _buildMessageList(),
                _buildThinkingIndicator(),
                _buildInputBar(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick action data ─────────────────────────────────────────────────────

class _QuickAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _QuickAction({required this.icon, required this.label, this.onTap});
}

// ── Reactor painter ───────────────────────────────────────────────────────

class _JarvisReactorPainter extends CustomPainter {
  final double ring1, ring2, ring3, pulse;
  final bool isListening, isThinking;
  final Color cyan, gold;

  const _JarvisReactorPainter({
    required this.ring1, required this.ring2, required this.ring3,
    required this.pulse, required this.isListening, required this.isThinking,
    required this.cyan, required this.gold,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5;

    final activeColor = isListening ? gold : isThinking ? Colors.orange : cyan;

    // Background circle
    paint
      ..color = activeColor.withOpacity(0.05)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 72, paint);

    // Outer ring with tick marks
    paint
      ..color = activeColor.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(cx, cy), 72, paint);
    for (int i = 0; i < 36; i++) {
      final angle = (i / 36) * 2 * pi + ring1 * 2 * pi;
      final r1 = 70.0;
      final r2 = i % 6 == 0 ? 62.0 : 66.0;
      canvas.drawLine(
        Offset(cx + cos(angle) * r1, cy + sin(angle) * r1),
        Offset(cx + cos(angle) * r2, cy + sin(angle) * r2),
        paint..color = activeColor.withOpacity(i % 6 == 0 ? 0.7 : 0.3),
      );
    }

    // Middle rotating ring
    paint
      ..color = activeColor.withOpacity(0.5)
      ..strokeWidth = 2;
    final rect2 = Rect.fromCircle(center: Offset(cx, cy), radius: 52);
    canvas.drawArc(rect2, ring2 * 2 * pi, pi * 1.2, false, paint);
    canvas.drawArc(rect2, ring2 * 2 * pi + pi, pi * 0.4, false,
        paint..color = activeColor.withOpacity(0.3));

    // Inner spinning ring
    paint
      ..color = activeColor.withOpacity(0.6)
      ..strokeWidth = 1.5;
    final rect3 = Rect.fromCircle(center: Offset(cx, cy), radius: 38);
    canvas.drawArc(rect3, -ring3 * 2 * pi, pi * 0.8, false, paint);
    canvas.drawArc(rect3, -ring3 * 2 * pi + pi, pi * 0.6, false,
        paint..color = activeColor.withOpacity(0.2));

    // Hexagon core
    final hexPath = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (i / 6) * 2 * pi - pi / 6;
      final x = cx + cos(angle) * 22;
      final y = cy + sin(angle) * 22;
      if (i == 0) hexPath.moveTo(x, y); else hexPath.lineTo(x, y);
    }
    hexPath.close();
    paint
      ..color = activeColor.withOpacity(0.15)
      ..style = PaintingStyle.fill;
    canvas.drawPath(hexPath, paint);
    paint
      ..color = activeColor.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(hexPath, paint);

    // Core glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          activeColor.withOpacity(0.9 * pulse),
          activeColor.withOpacity(0.3 * pulse),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 18));
    canvas.drawCircle(Offset(cx, cy), 18, glowPaint);

    // Center dot
    paint
      ..color = activeColor.withOpacity(pulse)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 5, paint);
  }

  @override
  bool shouldRepaint(_JarvisReactorPainter old) => true;
}

// ── Grid background painter ───────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final Color color;
  const _GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.03)
      ..strokeWidth = 0.5;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}
