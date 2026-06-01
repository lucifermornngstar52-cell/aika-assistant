import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class Aika3DOverlay extends StatefulWidget {
  const Aika3DOverlay({Key? key}) : super(key: key);

  @override
  State<Aika3DOverlay> createState() => _Aika3DOverlayState();
}

class _Aika3DOverlayState extends State<Aika3DOverlay>
    with SingleTickerProviderStateMixin {
  Offset _position = const Offset(16, 120);
  double _size = 160.0;
  bool _showControls = false;
  String _currentAnimation = 'Idle';

  final List<String> _animations = [
    'Idle', 'Wave', 'Dance', 'Walking', 'Running', 'ThumbsUp', 'Jump', 'Yes', 'No',
  ];

  late AnimationController _glowController;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.3, end: 0.8)
        .animate(CurvedAnimation(parent: _glowController, curve: Curves.easeInOut));
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _size = prefs.getDouble('avatar_size') ?? 160.0;
      _position = Offset(
        prefs.getDouble('avatar_x') ?? 16.0,
        prefs.getDouble('avatar_y') ?? 120.0,
      );
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('avatar_size', _size);
    await prefs.setDouble('avatar_x', _position.dx);
    await prefs.setDouble('avatar_y', _position.dy);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  void _cycleAnimation() {
    final idx = _animations.indexOf(_currentAnimation);
    setState(() {
      _currentAnimation = _animations[(idx + 1) % _animations.length];
    });
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final clampedX = _position.dx.clamp(0.0, screen.width - _size);
    final clampedY = _position.dy.clamp(0.0, screen.height - _size - 60.0);

    return Positioned(
      left: clampedX,
      top: clampedY,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _position = Offset(
            (_position.dx + d.delta.dx).clamp(0.0, screen.width - _size),
            (_position.dy + d.delta.dy).clamp(0.0, screen.height - _size - 60.0),
          );
        }),
        onPanEnd: (_) => _savePrefs(),
        onTap: () => setState(() => _showControls = !_showControls),
        child: AnimatedBuilder(
          animation: _glowAnim,
          builder: (_, child) => Container(
            width: _size,
            height: _size + (_showControls ? 72 : 0),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Glow ring
                Positioned(
                  left: 0, top: 0,
                  child: Container(
                    width: _size,
                    height: _size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AikaTheme.neonBlue.withOpacity(_glowAnim.value * 0.7),
                          blurRadius: 20,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ),

                // 3D Model
                Positioned(
                  left: 0, top: 0,
                  child: ClipOval(
                    child: Container(
                      width: _size,
                      height: _size,
                      color: Colors.black.withOpacity(0.4),
                      child: ModelViewer(
                        src: '#assets/models/aika_model.glb',
                        alt: 'Aika',
                        autoPlay: true,
                        autoRotate: false,
                        cameraControls: false,
                        disableZoom: true,
                        backgroundColor: const Color(0x00000000),
                        animationName: _currentAnimation,
                      ),
                    ),
                  ),
                ),

                // Animation label
                Positioned(
                  bottom: _showControls ? 76 : 4,
                  left: 0, right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _currentAnimation,
                        style: TextStyle(
                            color: AikaTheme.neonBlue, fontSize: 9, letterSpacing: 1),
                      ),
                    ),
                  ),
                ),

                // Controls panel
                if (_showControls)
                  Positioned(
                    top: _size + 4,
                    left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _controlBtn(Icons.remove, '−', () {
                            setState(() => _size = (_size - 20).clamp(80.0, 300.0));
                            _savePrefs();
                          }),
                          _controlBtn(Icons.animation, '~', _cycleAnimation,
                              color: AikaTheme.neonPurple),
                          _controlBtn(Icons.close, '×', () {
                            setState(() => _showControls = false);
                          }, color: Colors.redAccent),
                          _controlBtn(Icons.add, '+', () {
                            setState(() => _size = (_size + 20).clamp(80.0, 300.0));
                            _savePrefs();
                          }),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controlBtn(IconData icon, String label, VoidCallback onTap, {Color? color}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: (color ?? AikaTheme.neonBlue).withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: (color ?? AikaTheme.neonBlue).withOpacity(0.5)),
          ),
          child: Icon(icon, size: 16, color: color ?? AikaTheme.neonBlue),
        ),
      );
}
