import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_live2d/flutter_live2d.dart';

/// Состояние Live2D аватара
enum AikaLive2DState { idle, listening, thinking, talking, greeting }

/// Виджет Live2D аватара — перетаскиваемый, анимированный, с прозрачным фоном.
/// Используется как внутри приложения, так и в overlay поверх других приложений.
class AikaLive2DMascot extends StatefulWidget {
  final double initialX;
  final double initialY;
  final double size;
  final AikaLive2DState state;
  final VoidCallback? onTap;
  final bool draggable;

  const AikaLive2DMascot({
    Key? key,
    this.initialX = 20,
    this.initialY = 120,
    this.size = 180,
    this.state = AikaLive2DState.idle,
    this.onTap,
    this.draggable = true,
  }) : super(key: key);

  @override
  State<AikaLive2DMascot> createState() => _AikaLive2DMascotState();
}

class _AikaLive2DMascotState extends State<AikaLive2DMascot>
    with TickerProviderStateMixin {
  late double _x;
  late double _y;
  bool _isDragging = false;

  final _ctrl = Live2DViewController();
  bool _modelLoaded = false;

  // Float анимация
  late AnimationController _floatCtrl;
  late Animation<double> _floatAnim;

  // Bounce при тапе
  late AnimationController _bounceCtrl;
  late Animation<double> _bounceAnim;

  // Таймер для смены мотивов
  Timer? _motionTimer;

  @override
  void initState() {
    super.initState();
    _x = widget.initialX;
    _y = widget.initialY;

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -7, end: 7).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );

    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _bounceAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _bounceCtrl, curve: Curves.elasticOut),
    );

    // Загружаем модель когда native view готов
    _ctrl.whenAttached.then((_) => _loadModel());
  }

  Future<void> _loadModel() async {
    final ok = await _ctrl.loadModel(
      modelDir: 'assets/models/Haru/',
      modelFileName: 'Haru.model3.json',
    );
    if (ok && mounted) {
      setState(() => _modelLoaded = true);
      _applyState(widget.state);
      _startMotionLoop();
    }
  }

  void _applyState(AikaLive2DState state) {
    if (!_modelLoaded) return;
    switch (state) {
      case AikaLive2DState.idle:
        _ctrl.startMotion(group: 'Idle', priority: 1);
        break;
      case AikaLive2DState.listening:
        _ctrl.setExpression(1); // настороженное выражение
        _ctrl.startMotion(group: 'TapBody', priority: 2);
        break;
      case AikaLive2DState.thinking:
        _ctrl.setExpression(2);
        _ctrl.startMotion(group: 'Idle', index: 3, priority: 2);
        break;
      case AikaLive2DState.talking:
        _ctrl.setExpression(0);
        _ctrl.startMotion(group: 'TapBody', index: 1, priority: 2);
        break;
      case AikaLive2DState.greeting:
        _ctrl.setExpression(3);
        _ctrl.startMotion(group: 'TapBody', index: 0, priority: 3);
        break;
    }
  }

  void _startMotionLoop() {
    _motionTimer?.cancel();
    _motionTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (widget.state == AikaLive2DState.idle && _modelLoaded) {
        // Случайный idle мотив
        final idx = DateTime.now().second % 5;
        _ctrl.startMotion(group: 'Idle', index: idx, priority: 1);
      }
    });
  }

  @override
  void didUpdateWidget(AikaLive2DMascot old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      _applyState(widget.state);
    }
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _bounceCtrl.dispose();
    _motionTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap() {
    _bounceCtrl.forward(from: 0);
    _ctrl.startMotion(group: 'TapBody', priority: 3);
    _ctrl.setExpression(4);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final mascot = AnimatedBuilder(
      animation: Listenable.merge([_floatAnim, _bounceAnim]),
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _isDragging ? 0 : _floatAnim.value),
        child: Transform.scale(
          scale: _bounceAnim.value,
          child: child,
        ),
      ),
      child: GestureDetector(
        onTap: _onTap,
        child: SizedBox(
          width: widget.size,
          height: widget.size * 1.5,
          child: _modelLoaded
              ? Live2DView(controller: _ctrl)
              : _buildPlaceholder(),
        ),
      ),
    );

    if (!widget.draggable) return mascot;

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
        child: mascot,
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.pinkAccent.withOpacity(0.7),
        ),
      ),
    );
  }
}
