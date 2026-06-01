import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../theme/app_theme.dart';

enum AikaState { idle, listening, thinking, greeting, dance, stretch }

class Aika3DAvatar extends StatefulWidget {
  final AikaState state;
  final double size;

  const Aika3DAvatar({Key? key, required this.state, this.size = 280}) : super(key: key);

  @override
  State<Aika3DAvatar> createState() => _Aika3DAvatarState();
}

class _Aika3DAvatarState extends State<Aika3DAvatar> with SingleTickerProviderStateMixin {
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  // Маппинг состояний на анимации модели
  // aika_model.glb содержит анимацию "UMain"
  // Через model-viewer можно управлять анимациями через JavaScript
  String get _animationName {
    switch (widget.state) {
      case AikaState.idle:      return 'UMain';
      case AikaState.listening: return 'UMain';
      case AikaState.thinking:  return 'UMain';
      case AikaState.greeting:  return 'UMain';
      case AikaState.dance:     return 'UMain';
      case AikaState.stretch:   return 'UMain';
    }
  }

  Color get _glowColor {
    switch (widget.state) {
      case AikaState.listening: return AikaTheme.neonPurple;
      case AikaState.thinking:  return Colors.blueAccent;
      case AikaState.greeting:  return Colors.greenAccent;
      case AikaState.dance:     return Colors.pinkAccent;
      case AikaState.stretch:   return Colors.purpleAccent;
      default:                  return AikaTheme.neonBlue;
    }
  }

  double get _glowRadius {
    switch (widget.state) {
      case AikaState.listening: return 55;
      case AikaState.dance:     return 65;
      default:                  return 30;
    }
  }

  String get _statusLabel {
    switch (widget.state) {
      case AikaState.listening: return '🎤 Слушаю...';
      case AikaState.thinking:  return '💭 Думаю...';
      case AikaState.greeting:  return '👋 Привет!';
      case AikaState.dance:     return '🎵 Танцую!';
      case AikaState.stretch:   return '🧘 Растягиваюсь';
      default:                  return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size * 1.3,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Анимированный glow под моделью
          AnimatedBuilder(
            animation: _glowAnim,
            builder: (ctx, _) => Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _glowColor.withOpacity(0.25 * _glowAnim.value),
                    blurRadius: _glowRadius * _glowAnim.value,
                    spreadRadius: 8 * _glowAnim.value,
                  ),
                ],
              ),
            ),
          ),

          // 3D модель через model_viewer_plus
          ClipRRect(
            borderRadius: BorderRadius.circular(widget.size * 0.15),
            child: SizedBox(
              width: widget.size,
              height: widget.size * 1.25,
              child: ModelViewer(
                src: 'asset:///assets/models/aika_model.glb',
                alt: 'Aika 3D',
                ar: false,
                autoRotate: widget.state == AikaState.idle,
                autoRotateDelay: 2000,
                autoPlay: true,
                animationName: _animationName,
                cameraControls: true,
                backgroundColor: Colors.transparent,
                disableZoom: false,
                cameraOrbit: '0deg 75deg 2.5m',
                minCameraOrbit: 'auto 40deg auto',
                maxCameraOrbit: 'auto 90deg auto',
                shadowIntensity: 0.8,
                exposure: 1.2,
              ),
            ),
          ),

          // Статус бейдж внизу
          Positioned(
            bottom: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _statusLabel.isNotEmpty
                  ? Container(
                      key: ValueKey(_statusLabel),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _glowColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _glowColor.withOpacity(0.8),
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        _statusLabel,
                        style: TextStyle(
                          color: _glowColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            ),
          ),
        ],
      ),
    );
  }
}
