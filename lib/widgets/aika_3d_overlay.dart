import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/avatar_animation_controller.dart';
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

  late AnimationController _glowController;
  late Animation<double> _glowAnim;

  final AvatarAnimationController _animCtrl = AvatarAnimationController.instance;

  @override
  void initState() {
    super.initState();
    _glowController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.3, end: 0.8).animate(
        CurvedAnimation(parent: _glowController, curve: Curves.easeInOut));
    _animCtrl.addListener(_onAnimationChange);
    _loadPrefs();
  }

  void _onAnimationChange() => setState(() {});

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
    _animCtrl.removeListener(_onAnimationChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final clampedX = _position.dx.clamp(0.0, screen.width - _size);
    final clampedY = _position.dy.clamp(0.0, screen.height - _size - 60.0);

    final currentAnim = _animCtrl.current;
    final glowColor = _getGlowColor(currentAnim);

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
        child: SizedBox(
          width: _size,
          height: _size + (_showControls ? 80 : 0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Glow
              Positioned(
                left: 0, top: 0,
                child: AnimatedBuilder(
                  animation: _glowAnim,
                  builder: (_, __) => Container(
                    width: _size,
                    height: _size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: glowColor.withOpacity(_glowAnim.value * 0.7),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
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
                    color: Colors.black.withOpacity(0.35),
                    child: ModelViewer(
                      src: '#assets/models/aika_model.glb',
                      alt: 'Aika',
                      autoPlay: true,
                      autoRotate: false,
                      cameraControls: false,
                      disableZoom: true,
                      backgroundColor: const Color(0x00000000),
                      animationName: currentAnim.glbName,
                    ),
                  ),
                ),
              ),

              // Status badge
              Positioned(
                bottom: _showControls ? 84 : 6,
                left: 0, right: 0,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      key: ValueKey(currentAnim),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: glowColor.withOpacity(0.4)),
                      ),
                      child: Text(
                        currentAnim.label,
                        style: TextStyle(color: glowColor, fontSize: 9, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                ),
              ),

              // Controls
              if (_showControls)
                Positioned(
                  top: _size + 6,
                  left: -20, right: -20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.3)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Size controls
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _btn(Icons.remove, () {
                              setState(() => _size = (_size - 20).clamp(80.0, 300.0));
                              _savePrefs();
                            }),
                            Text('${_size.toInt()}px',
                                style: TextStyle(color: AikaTheme.neonBlue, fontSize: 10)),
                            _btn(Icons.add, () {
                              setState(() => _size = (_size + 20).clamp(80.0, 300.0));
                              _savePrefs();
                            }),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Animation picker
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          alignment: WrapAlignment.center,
                          children: AvatarAnimation.values.map((anim) {
                            final isActive = currentAnim == anim;
                            return GestureDetector(
                              onTap: () => _animCtrl.setManual(anim),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? glowColor.withOpacity(0.3)
                                      : Colors.white10,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isActive
                                        ? glowColor.withOpacity(0.7)
                                        : Colors.white12,
                                  ),
                                ),
                                child: Text(anim.label,
                                    style: TextStyle(
                                      color: isActive ? glowColor : Colors.white38,
                                      fontSize: 9,
                                    )),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 4),
                        // Reset to auto
                        GestureDetector(
                          onTap: () {
                            _animCtrl.resetToAuto();
                            setState(() => _showControls = false);
                          },
                          child: Text('↺ авто', style: TextStyle(
                              color: Colors.white38, fontSize: 9)),
                        ),
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

  Color _getGlowColor(AvatarAnimation anim) {
    switch (anim) {
      case AvatarAnimation.dance:   return Colors.pinkAccent;
      case AvatarAnimation.wave:    return AikaTheme.neonBlue;
      case AvatarAnimation.thumbsUp: return Colors.greenAccent;
      case AvatarAnimation.jump:    return Colors.orangeAccent;
      case AvatarAnimation.no:      return Colors.redAccent;
      case AvatarAnimation.yes:     return Colors.greenAccent;
      case AvatarAnimation.running: return Colors.yellowAccent;
      case AvatarAnimation.sitting: return Colors.blueGrey;
      default:                      return AikaTheme.neonBlue;
    }
  }

  Widget _btn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: AikaTheme.neonBlue.withOpacity(0.2),
        shape: BoxShape.circle,
        border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.5)),
      ),
      child: Icon(icon, size: 16, color: AikaTheme.neonBlue),
    ),
  );
}
