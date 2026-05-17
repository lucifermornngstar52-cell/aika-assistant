import 'package:flutter/material.dart';

class AikaMascot extends StatefulWidget {
  final double initialX;
  final double initialY;
  final double size;
  final VoidCallback? onTap;

  const AikaMascot({
    Key? key,
    this.initialX = 20,
    this.initialY = 120,
    this.size = 100,
    this.onTap,
  }) : super(key: key);

  @override
  State<AikaMascot> createState() => _AikaMascotState();
}

class _AikaMascotState extends State<AikaMascot> with TickerProviderStateMixin {
  late double _x;
  late double _y;
  bool _isDragging = false;

  late AnimationController _floatController;
  late Animation<double> _floatAnim;
  late AnimationController _bounceController;
  late Animation<double> _bounceAnim;

  @override
  void initState() {
    super.initState();
    _x = widget.initialX;
    _y = widget.initialY;

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _bounceAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _floatController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() {
      _x += d.delta.dx;
      _y += d.delta.dy;
      final size = MediaQuery.of(context).size;
      _x = _x.clamp(0.0, size.width - widget.size);
      _y = _y.clamp(0.0, size.height - widget.size * 1.4);
    });
  }

  void _onPanEnd(DragEndDetails d) {
    setState(() => _isDragging = false);
    _bounceController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _x,
      top: _y,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _isDragging = true),
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_floatAnim, _bounceAnim]),
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _isDragging ? 0 : _floatAnim.value),
              child: Transform.scale(
                scale: _bounceAnim.value,
                child: child,
              ),
            );
          },
          child: SizedBox(
            width: widget.size,
            height: widget.size * 1.4,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  width: widget.size * 0.65,
                  height: 8,
                  margin: const EdgeInsets.only(top: 0),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: 8,
                  child: Image.asset(
                    'assets/images/aika_chibi.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
