import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

/// Перетаскиваемый 3D аватар поверх всего экрана
class Aika3DOverlay extends StatefulWidget {
  const Aika3DOverlay({Key? key}) : super(key: key);

  @override
  State<Aika3DOverlay> createState() => _Aika3DOverlayState();
}

class _Aika3DOverlayState extends State<Aika3DOverlay>
    with SingleTickerProviderStateMixin {
  Offset _position = const Offset(16, 120);
  double _size = 160;
  bool _isVisible = true;
  bool _showControls = false;

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
      _size = prefs.getDouble('avatar_size') ?? 160;
      _position = Offset(
        prefs.getDouble('avatar_x') ?? 16,
        prefs.getDouble('avatar_y') ?? 120,
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

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    final screenSize = MediaQuery.of(context).size;

    return Positioned(
      left: _position.dx.clamp(0, screenSize.width - _size),
      top: _position.dy.clamp(0, screenSize.height - _size - 80),
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx + details.delta.dx)
                  .clamp(0, screenSize.width - _size),
              (_position.dy + details.delta.dy)
                  .clamp(0, screenSize.height - _size - 80),
            );
          });
        },
        onPanEnd: (_) => _savePrefs(),
        onTap: () => setState(() => _showControls = !_showControls),
        child: AnimatedBuilder(
          animation: _glowAnim,
          builder: (_, child) => Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AikaTheme.neonBlue.withOpacity(_glowAnim.value * 0.6),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: child,
          ),
          child: Stack(
            children: [
              // 3D Model
              ClipOval(
                child: SizedBox(
                  width: _size,
                  height: _size,
                  child: ModelViewer(
                    src: '#assets/models/aika_model.glb',
                    alt: 'Aika',
                    autoPlay: true,
                    autoRotate: false,
                    cameraControls: false,
                    disableZoom: true,
                    backgroundColor: Colors.transparent,
                    animationName: 'idle',
                  ),
                ),
              ),

              // Controls panel
              if (_showControls)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(80),
                        bottomRight: Radius.circular(80),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Уменьшить
                        _controlBtn(Icons.remove, () {
                          setState(() => _size = (_size - 20).clamp(80, 300));
                          _savePrefs();
                        }),
                        const SizedBox(width: 8),
                        // Скрыть
                        _controlBtn(Icons.visibility_off, () {
                          setState(() {
                            _showControls = false;
                            _isVisible = false;
                          });
                        }),
                        const SizedBox(width: 8),
                        // Увеличить
                        _controlBtn(Icons.add, () {
                          setState(() => _size = (_size + 20).clamp(80, 300));
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
    );
  }

  Widget _controlBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AikaTheme.neonBlue.withOpacity(0.3),
            shape: BoxShape.circle,
            border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.5)),
          ),
          child: Icon(icon, size: 14, color: Colors.white),
        ),
      );
}
