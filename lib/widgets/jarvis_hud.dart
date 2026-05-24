import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════
// JARVIS HUD — полный функционал как у Айки
// ══════════════════════════════════════════════════════

class JarvisHud extends StatefulWidget {
  final bool isListening;
  final bool isThinking;
  final String lastResponse;
  final VoidCallback? onMicTap;
  final VoidCallback? onThemeSwitch;

  // Полный функционал Айки
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
    this.isThinking = false,
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
    this.assistantName = 'JARVIS',
    this.userName = '',
  }) : super(key: key);

  @override
  State<JarvisHud> createState() => _JarvisHudState();
}

class _JarvisHudState extends State<JarvisHud> with TickerProviderStateMixin {
  late AnimationController _ring1Ctrl;
  late AnimationController _ring2Ctrl;
  late AnimationController _ring3Ctrl;
  late AnimationController _reactorCtrl;
  late Animation<double> _reactorPulse;
  late AnimationController _scanCtrl;
  late Animation<double> _scanAnim;
  late AnimationController _radarCtrl;

  int _batteryLevel = 85;
  double _cpuLoad = 42.0;
  double _ramUsage = 67.0;
  Timer? _dataTimer;

  // Внутренний контроллер если внешний не передан
  late TextEditingController _internalTextCtrl;
  late ScrollController _internalScrollCtrl;
  TextEditingController get _textCtrl => widget.textController ?? _internalTextCtrl;
  ScrollController get _scrollCtrl => widget.scrollController ?? _internalScrollCtrl;

  @override
  void initState() {
    super.initState();
    _internalTextCtrl = TextEditingController();
    _internalScrollCtrl = ScrollController();

    _ring1Ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _ring2Ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
    _ring3Ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
    _reactorCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _reactorPulse = Tween<double>(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: _reactorCtrl, curve: Curves.easeInOut));
    _scanCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _scanAnim = Tween<double>(begin: 0.0, end: 1.0).animate(_scanCtrl);
    _radarCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

    _dataTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {
        _cpuLoad = 30 + Random().nextDouble() * 50;
        _ramUsage = 55 + Random().nextDouble() * 30;
      });
    });
  }

  @override
  void didUpdateWidget(JarvisHud old) {
    super.didUpdateWidget(old);
    if (widget.messages.length != old.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      });
    }
  }

  @override
  void dispose() {
    _ring1Ctrl.dispose(); _ring2Ctrl.dispose(); _ring3Ctrl.dispose();
    _reactorCtrl.dispose(); _scanCtrl.dispose(); _radarCtrl.dispose();
    _dataTimer?.cancel();
    if (widget.textController == null) _internalTextCtrl.dispose();
    if (widget.scrollController == null) _internalScrollCtrl.dispose();
    super.dispose();
  }

  void _handleSend(String text) {
    if (text.trim().isEmpty) return;
    widget.onSendMessage?.call(text);
    _textCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFF000810),
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        // Фоновая сетка
        CustomPaint(painter: _GridPainter(), size: Size(size.width, size.height)),
        // Scan line
        _buildScanLine(size),
        // Основной контент
        SafeArea(
          child: Column(children: [
            _buildTopBar(),
            if (widget.wakeWordEnabled) _buildWakeWordBanner(),
            // HUD панели + чат
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Левая диагностика
                _buildLeftPanel(),
                // Центр: реактор + чат
                Expanded(child: _buildCenterColumn(size)),
                // Правое меню
                _buildRightPanel(context),
              ]),
            ),
            // Input bar
            _buildInputBar(),
          ]),
        ),
      ]),
    );
  }

  Widget _buildScanLine(Size size) {
    return AnimatedBuilder(
      animation: _scanAnim,
      builder: (_, __) => Positioned(
        top: _scanAnim.value * size.height,
        left: 0, right: 0,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Заголовок
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('J.A.R.V.I.S',
                style: const TextStyle(
                  color: Color(0xFF00D4FF), fontSize: 18,
                  fontWeight: FontWeight.w900, letterSpacing: 5,
                  shadows: [Shadow(color: Color(0xFF00D4FF), blurRadius: 12)],
                )),
            Text(
              widget.userName.isNotEmpty ? 'ПРИВЕТ, ${widget.userName.toUpperCase()}' : 'SYSTEM ONLINE',
              style: const TextStyle(color: Color(0xFF00FF88), fontSize: 9, letterSpacing: 2),
            ),
          ]),
          // Кнопки управления
          Row(children: [
            // Wake word
            _hudSmallButton(
              icon: Icons.hearing,
              label: widget.wakeWordEnabled ? 'ON' : 'OFF',
              active: widget.wakeWordEnabled,
              onTap: widget.onToggleWakeWord,
            ),
            const SizedBox(width: 6),
            // Overlay
            if (!widget.hasOverlayPermission)
              _hudSmallButton(icon: Icons.face_outlined, label: 'HUD', active: false, color: Colors.orange, onTap: widget.onOverlayPermission),
            if (!widget.hasOverlayPermission) const SizedBox(width: 6),
            // Валюта
            _hudIconSmall(Icons.currency_exchange, onTap: widget.onOpenCurrency),
            const SizedBox(width: 4),
            // Меню
            _buildMenuButton(),
            const SizedBox(width: 6),
            // Кнопка Айка
            GestureDetector(
              onTap: widget.onThemeSwitch,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(6),
                  color: const Color(0xFF001830),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('🌸', style: TextStyle(fontSize: 12)),
                  SizedBox(width: 3),
                  Text('АЙКА', style: TextStyle(color: Color(0xFF00D4FF), fontSize: 9, letterSpacing: 2)),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            _buildCircularGauge(_batteryLevel.toDouble(), 100, const Color(0xFF00D4FF), size: 46),
          ]),
        ],
      ),
    );
  }

  Widget _buildWakeWordBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF00D4FF).withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.2)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.hearing, size: 11, color: Color(0xFF00D4FF)),
        const SizedBox(width: 5),
        Text('ПРОСЛУШИВАНИЕ: "${widget.assistantName.toUpperCase()}"',
            style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 10, letterSpacing: 2)),
      ]),
    );
  }

  Widget _buildLeftPanel() {
    return Container(
      width: 90,
      padding: const EdgeInsets.only(left: 8, top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _hudLabel('DIAGNOSTICS'),
        const SizedBox(height: 6),
        _hudBar('CPU', _cpuLoad, const Color(0xFF00D4FF)),
        const SizedBox(height: 5),
        _hudBar('RAM', _ramUsage, const Color(0xFF0088FF)),
        const SizedBox(height: 5),
        _hudBar('NET', 23, const Color(0xFF00FFCC)),
        const SizedBox(height: 10),
        _hudLabel('TEMP'),
        const SizedBox(height: 4),
        _buildCircularGauge(38, 100, const Color(0xFFFF4444), label: '°C', size: 56),
        const SizedBox(height: 10),
        // Мини-реактор
        Center(
          child: AnimatedBuilder(
            animation: _ring1Ctrl,
            builder: (_, __) => Transform.rotate(
              angle: _ring1Ctrl.value * 2 * pi,
              child: CustomPaint(
                size: const Size(50, 50),
                painter: _RingPainter(25, 1.5, const Color(0xFF00D4FF), dashes: 20),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildCenterColumn(Size size) {
    return Column(children: [
      // Реактор (компактный)
      SizedBox(
        height: 150,
        child: Center(child: _buildReactor()),
      ),
      // Чат
      Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF000D1A).withOpacity(0.7),
            border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.15)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: widget.messages.isEmpty
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.blur_on, color: Color(0xFF003355), size: 32),
                    const SizedBox(height: 8),
                    Text(
                      widget.isThinking ? 'ОБРАБОТКА...' : 'ОЖИДАНИЕ КОМАНДЫ',
                      style: const TextStyle(color: Color(0xFF224466), fontSize: 11, letterSpacing: 2),
                    ),
                  ]),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(8),
                  itemCount: widget.messages.length,
                  itemBuilder: (_, i) => _buildJarvisMessage(widget.messages[i]),
                ),
        ),
      ),
    ]);
  }

  Widget _buildJarvisMessage(JarvisMessage msg) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 20, height: 20,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF001830),
                border: Border.fromBorderSide(BorderSide(color: Color(0xFF00D4FF), width: 1)),
              ),
              child: const Icon(Icons.blur_on, color: Color(0xFF00D4FF), size: 12),
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFF001F3F).withOpacity(0.8)
                    : const Color(0xFF00090F).withOpacity(0.9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isUser
                      ? const Color(0xFF0088FF).withOpacity(0.4)
                      : const Color(0xFF00D4FF).withOpacity(0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isUser ? const Color(0xFF0088FF) : const Color(0xFF00D4FF)).withOpacity(0.08),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Text(
                msg.content,
                style: TextStyle(
                  color: isUser ? const Color(0xFF88CCFF) : const Color(0xFFCCEEFF),
                  fontSize: 12,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildRightPanel(BuildContext context) {
    return Container(
      width: 85,
      padding: const EdgeInsets.only(right: 8, top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _hudLabel('СИСТЕМЫ'),
        const SizedBox(height: 6),
        ...[
          _MenuEntry('📖', 'Дневник', widget.onOpenMoodDiary),
          _MenuEntry('📅', 'Расписание', widget.onOpenSchedule),
          _MenuEntry('🤖', 'Telegram', widget.onOpenTelegram),
          _MenuEntry('⚡', 'Команды', widget.onOpenAppCommands),
        ].map((e) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: GestureDetector(
            onTap: e.onTap,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(e.label, style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 10, letterSpacing: 0.5)),
              const SizedBox(width: 4),
              Text(e.icon, style: const TextStyle(fontSize: 11)),
            ]),
          ),
        )).toList(),
        const SizedBox(height: 10),
        _hudLabel('RADAR'),
        const SizedBox(height: 4),
        // Мини радар
        AnimatedBuilder(
          animation: _radarCtrl,
          builder: (_, __) => CustomPaint(
            size: const Size(60, 60),
            painter: _RadarPainter(_radarCtrl.value),
          ),
        ),
      ]),
    );
  }

  Widget _buildReactor() {
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(alignment: Alignment.center, children: [
        // Кольцо 1
        AnimatedBuilder(
          animation: _ring1Ctrl,
          builder: (_, __) => Transform.rotate(
            angle: _ring1Ctrl.value * 2 * pi,
            child: CustomPaint(size: const Size(140, 140),
                painter: _RingPainter(70, 2, const Color(0xFF00D4FF), dashes: 50)),
          ),
        ),
        // Кольцо 2 (обратное)
        AnimatedBuilder(
          animation: _ring2Ctrl,
          builder: (_, __) => Transform.rotate(
            angle: -_ring2Ctrl.value * 2 * pi,
            child: CustomPaint(size: const Size(100, 100),
                painter: _RingPainter(50, 1.5, const Color(0xFF0088FF), dashes: 32)),
          ),
        ),
        // Radar sweep
        AnimatedBuilder(
          animation: _radarCtrl,
          builder: (_, __) => CustomPaint(
            size: const Size(90, 90),
            painter: _RadarPainter(_radarCtrl.value),
          ),
        ),
        // Центральный реактор
        AnimatedBuilder(
          animation: _reactorPulse,
          builder: (_, __) => GestureDetector(
            onTap: widget.onMicTap,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF001830),
                border: Border.all(color: const Color(0xFF00D4FF), width: 1.5),
                boxShadow: [BoxShadow(
                  color: (widget.isListening ? const Color(0xFF00FF88) : const Color(0xFF00D4FF))
                      .withOpacity(_reactorPulse.value * 0.8),
                  blurRadius: 20 * _reactorPulse.value,
                  spreadRadius: 4 * _reactorPulse.value,
                )],
              ),
              child: Icon(
                widget.isListening ? Icons.mic : (widget.isThinking ? Icons.psychology : Icons.blur_on),
                color: widget.isListening ? const Color(0xFF00FF88) : const Color(0xFF00D4FF),
                size: 24,
              ),
            ),
          ),
        ),
        // Статус
        Positioned(
          bottom: 2,
          child: Text(
            widget.isListening ? 'СЛУШАЮ...' : (widget.isThinking ? 'ДУМАЮ...' : 'STANDBY'),
            style: TextStyle(
              color: widget.isListening ? const Color(0xFF00FF88) : const Color(0xFF446677),
              fontSize: 8, letterSpacing: 2,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF000D1A),
        border: const Border(top: BorderSide(color: Color(0xFF00D4FF), width: 0.5)),
      ),
      child: Row(children: [
        // Mic кнопка
        GestureDetector(
          onTap: widget.onMicTap,
          child: AnimatedBuilder(
            animation: _reactorPulse,
            builder: (_, __) => Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF001830),
                border: Border.all(
                  color: widget.isListening ? const Color(0xFF00FF88) : const Color(0xFF00D4FF).withOpacity(0.6),
                  width: 1.5,
                ),
                boxShadow: widget.isListening ? [BoxShadow(
                  color: const Color(0xFF00FF88).withOpacity(_reactorPulse.value * 0.7),
                  blurRadius: 12, spreadRadius: 2,
                )] : [],
              ),
              child: Icon(Icons.mic,
                color: widget.isListening ? const Color(0xFF00FF88) : const Color(0xFF00D4FF),
                size: 18,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Поле ввода
        Expanded(
          child: TextField(
            controller: _textCtrl,
            style: const TextStyle(color: Color(0xFFCCEEFF), fontSize: 13),
            decoration: InputDecoration(
              hintText: 'ВВЕДИТЕ КОМАНДУ...',
              hintStyle: const TextStyle(color: Color(0xFF224466), fontSize: 11, letterSpacing: 1),
              filled: true,
              fillColor: const Color(0xFF001020),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF00D4FF), width: 0.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: const Color(0xFF00D4FF).withOpacity(0.3), width: 0.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF00D4FF), width: 1),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onSubmitted: _handleSend,
          ),
        ),
        const SizedBox(width: 8),
        // Кнопка отправки
        GestureDetector(
          onTap: () => _handleSend(_textCtrl.text),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF001830),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.5)),
              boxShadow: [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.15), blurRadius: 8)],
            ),
            child: const Icon(Icons.send, color: Color(0xFF00D4FF), size: 18),
          ),
        ),
      ]),
    );
  }

  Widget _buildMenuButton() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.tune, color: Color(0xFF00D4FF), size: 20),
      color: const Color(0xFF001020),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF00D4FF), width: 0.5),
      ),
      onSelected: (value) {
        if (value == 'settings') widget.onOpenSettings?.call();
        if (value == 'mood') widget.onOpenMoodDiary?.call();
        if (value == 'schedule') widget.onOpenSchedule?.call();
        if (value == 'telegram') widget.onOpenTelegram?.call();
        if (value == 'appcommands') widget.onOpenAppCommands?.call();
        if (value == 'currency') widget.onOpenCurrency?.call();
        if (value == 'switchtheme') widget.onThemeSwitch?.call();
      },
      itemBuilder: (_) => [
        _hudMenuItem('switchtheme', '🌸', 'ПЕРЕКЛЮЧИТЬ → АЙКА'),
        _hudMenuItem('settings', '⚙️', 'НАСТРОЙКИ'),
        _hudMenuItem('mood', '📖', 'ДНЕВНИК НАСТРОЕНИЯ'),
        _hudMenuItem('schedule', '📅', 'РАСПИСАНИЕ'),
        _hudMenuItem('telegram', '🤖', 'TELEGRAM БОТ'),
        _hudMenuItem('appcommands', '⚡', 'КОМАНДЫ ПРИЛОЖЕНИЙ'),
        _hudMenuItem('currency', '💱', 'ВАЛЮТА'),
      ],
    );
  }

  PopupMenuItem<String> _hudMenuItem(String value, String icon, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 11, letterSpacing: 1)),
      ]),
    );
  }

  Widget _buildCircularGauge(double value, double max, Color color, {String label = '%', double size = 60}) {
    return SizedBox(
      width: size, height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(size: Size(size, size), painter: _ArcPainter(value / max, color)),
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${value.toInt()}$label',
              style: TextStyle(color: color, fontSize: size * 0.2,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: color, blurRadius: 8)])),
          Text('BAT', style: const TextStyle(color: Color(0xFF446677), fontSize: 6, letterSpacing: 1)),
        ]),
      ]),
    );
  }

  Widget _hudLabel(String text) => Text(text,
      style: const TextStyle(color: Color(0xFF446677), fontSize: 8, letterSpacing: 2));

  Widget _hudBar(String label, double value, Color color) {
    return SizedBox(
      width: 78,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: Color(0xFF668899), fontSize: 8, letterSpacing: 1)),
          Text('${value.toInt()}%', style: TextStyle(color: color, fontSize: 8)),
        ]),
        const SizedBox(height: 2),
        Stack(children: [
          Container(height: 3, width: 78,
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(2))),
          Container(height: 3, width: 78 * value / 100,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2),
                  boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 4)])),
        ]),
      ]),
    );
  }

  Widget _hudSmallButton({required IconData icon, required String label, bool active = false, Color? color, VoidCallback? onTap}) {
    final c = color ?? const Color(0xFF00D4FF);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: active ? c.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? c.withOpacity(0.6) : c.withOpacity(0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: active ? c : c.withOpacity(0.5)),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
              color: active ? c : c.withOpacity(0.5))),
        ]),
      ),
    );
  }

  Widget _hudIconSmall(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: const Color(0xFF00D4FF).withOpacity(0.6), size: 18),
    );
  }
}

// ══════════════ Модель сообщения ══════════════
class JarvisMessage {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  JarvisMessage({required this.content, required this.isUser, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();
}

class _MenuEntry {
  final String icon, label;
  final VoidCallback? onTap;
  _MenuEntry(this.icon, this.label, this.onTap);
}

// ══════════════ PAINTERS ══════════════

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF00D4FF).withOpacity(0.04)..strokeWidth = 0.5;
    const step = 30.0;
    for (double x = 0; x < size.width; x += step)
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    for (double y = 0; y < size.height; y += step)
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
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
    canvas.drawCircle(center, radius,
        Paint()..color = color.withOpacity(0.1)..style = PaintingStyle.stroke..strokeWidth = 4);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -pi / 2, value * 2 * pi, false,
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round);
  }
  @override bool shouldRepaint(_ArcPainter o) => o.value != value;
}

class _RingPainter extends CustomPainter {
  final double radius, strokeWidth;
  final Color color;
  final int dashes;
  _RingPainter(this.radius, this.strokeWidth, this.color, {this.dashes = 40});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withOpacity(0.7)..style = PaintingStyle.stroke..strokeWidth = strokeWidth;
    final center = Offset(size.width / 2, size.height / 2);
    final dashAngle = 2 * pi / dashes;
    for (int i = 0; i < dashes; i++) {
      if (i % 3 == 2) continue;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
          i * dashAngle, dashAngle * 0.6, false, paint);
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
    final paint = Paint()..shader = SweepGradient(
      startAngle: sweepAngle - 0.8, endAngle: sweepAngle,
      colors: [Colors.transparent, const Color(0xFF00D4FF).withOpacity(0.3)],
      center: Alignment.center,
    ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
    canvas.drawLine(center,
      Offset(center.dx + cos(sweepAngle) * radius, center.dy + sin(sweepAngle) * radius),
      Paint()..color = const Color(0xFF00D4FF).withOpacity(0.8)..strokeWidth = 1.5);
  }
  @override bool shouldRepaint(_RadarPainter o) => o.sweep != sweep;
}
