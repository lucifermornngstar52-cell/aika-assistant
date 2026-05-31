import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_live2d/flutter_live2d.dart';

/// Перетаскиваемый Live2D аватар Айки.
/// Показывается поверх UI внутри приложения.
class AikaMascot extends StatefulWidget {
  final double initialX;
  final double initialY;
  final double size;
  final VoidCallback? onTap;
  /// Состояние: idle | listening | thinking | talking | greeting | dance
  final String state;

  const AikaMascot({
    Key? key,
    this.initialX = 20,
    this.initialY = 120,
    this.size = 160,
    this.onTap,
    this.state = 'idle',
  }) : super(key: key);

  @override
  State<AikaMascot> createState() => _AikaMascotState();
}

class _AikaMascotState extends State<AikaMascot>
    with TickerProviderStateMixin {
  late double _x;
  late double _y;
  bool _isDragging = false;

  final _ctrl = Live2DViewController();
  bool _loaded = false;

  late AnimationController _floatCtrl;
  late Animation<double> _floatAnim;
  late AnimationController _bounceCtrl;
  late Animation<double> _bounceAnim;

  Timer? _idleTimer;

  // Маппинг состояний → motion group
  static const Map<String, String> _stateGroup = {
    'idle':      'Idle',
    'listening': 'TapBody',
    'thinking':  'Idle',
    'talking':   'TapBody',
    'greeting':  'TapBody',
    'dance':     'TapBody',
  };

  static const Map<String, int> _stateExpr = {
    'idle':      0,
    'listening': 1,
    'thinking':  2,
    'talking':   0,
    'greeting':  3,
    'dance':     4,
  };

  @override
  void initState() {
    super.initState();
    _x = widget.initialX;
    _y = widget.initialY;

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -7, end: 7)
        .animate(CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut));

    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _bounceAnim = Tween<double>(begin: 1.0, end: 1.18)
        .animate(CurvedAnimation(parent: _bounceCtrl, curve: Curves.elasticOut));

    _ctrl.whenAttached.then((_) => _loadModel());
  }

  Future<void> _loadModel() async {
    final ok = await _ctrl.loadModel(
      modelDir: 'assets/models/Haru/',
      modelFileName: 'Haru.model3.json',
    );
    if (!ok || !mounted) return;
    setState(() => _loaded = true);
    _applyState(widget.state);
    _startIdleLoop();
  }

  void _applyState(String state) {
    if (!_loaded) return;
    final group = _stateGroup[state] ?? 'Idle';
    final expr  = _stateExpr[state] ?? 0;
    final prio  = (state == 'greeting' || state == 'dance') ? 3 : 2;
    _ctrl.setExpression(expr);
    _ctrl.startMotion(group: group, priority: prio);
  }

  void _startIdleLoop() {
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (widget.state == 'idle' && _loaded) {
        final idx = DateTime.now().second % 6;
        _ctrl.startMotion(group: 'Idle', index: idx, priority: 1);
      }
    });
  }

  @override
  void didUpdateWidget(AikaMascot old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      _applyState(widget.state);
    }
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _bounceCtrl.dispose();
    _idleTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap() {
    _bounceCtrl.forward(from: 0);
    if (_loaded) {
      _ctrl.startMotion(group: 'TapBody', priority: 3);
      _ctrl.setExpression(4);
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _x,
      top: _y,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _isDragging = true),
        onPanUpdate: (d) {
          setState(() {
            _x += d.delta.dx;
            _y += d.delta.dy;
            final sz = MediaQuery.of(context).size;
            _x = _x.clamp(0.0, sz.width - widget.size);
            _y = _y.clamp(0.0, sz.height - widget.size * 1.5);
          });
        },
        onPanEnd: (_) {
          setState(() => _isDragging = false);
          _bounceCtrl.forward(from: 0);
        },
        onTap: _onTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_floatAnim, _bounceAnim]),
          builder: (_, child) => Transform.translate(
            offset: Offset(0, _isDragging ? 0 : _floatAnim.value),
            child: Transform.scale(
              scale: _bounceAnim.value,
              child: child,
            ),
          ),
          child: SizedBox(
            width: widget.size,
            height: widget.size * 1.5,
            child: _loaded
                ? Live2DView(controller: _ctrl)
                : _placeholder(),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Center(
    child: SizedBox(
      width: 32,
      height: 32,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Colors.pinkAccent.withOpacity(0.6),
      ),
    ),
  );
}
