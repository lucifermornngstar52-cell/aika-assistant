import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../theme/app_theme.dart';

class AikaAvatar extends StatelessWidget {
  final bool isThinking;
  final bool isListening;
  final bool use3DModel;

  const AikaAvatar({
    Key? key,
    this.isThinking = false,
    this.isListening = false,
    this.use3DModel = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: use3DModel ? _build3DModel() : _buildFallback(),
    );
  }

  Widget _build3DModel() {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          width: 190,
          height: 190,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: isListening
                    ? AikaTheme.neonPurple.withOpacity(0.5)
                    : isThinking
                        ? AikaTheme.neonBlue.withOpacity(0.3)
                        : AikaTheme.neonBlue.withOpacity(0.15),
                blurRadius: isListening ? 40 : 25,
                spreadRadius: isListening ? 10 : 4,
              ),
            ],
          ),
        ),
        ClipOval(
          child: SizedBox(
            width: 180,
            height: 180,
            child: ModelViewer(
              src: '#assets/models/aika_model.glb',
              alt: 'Aika 3D Model',
              autoRotate: true,
              cameraControls: true,
              disableZoom: true,
              backgroundColor: const Color.fromARGB(0, 0, 0, 0),
            ),
          ),
        ),
        Positioned(
          bottom: 16,
          child: AnimatedOpacity(
            opacity: isListening || isThinking ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AikaTheme.surface.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isListening
                      ? AikaTheme.neonPurple.withOpacity(0.7)
                      : AikaTheme.neonBlue.withOpacity(0.7),
                ),
              ),
              child: Text(
                isListening ? '● Слушаю...' : '● Думаю...',
                style: TextStyle(
                  color: isListening ? AikaTheme.neonPurple : AikaTheme.neonBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFallback() {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                isListening
                    ? AikaTheme.neonPurple.withOpacity(0.3)
                    : AikaTheme.neonBlue.withOpacity(0.2),
                Colors.transparent,
              ],
            ),
            border: Border.all(
              color: isListening ? AikaTheme.neonPurple : AikaTheme.neonBlue,
              width: 2,
            ),
          ),
          child: Icon(
            isListening ? Icons.mic : isThinking ? Icons.psychology : Icons.face,
            size: 60,
            color: AikaTheme.neonBlue,
          ),
        ),
      ],
    );
  }
}
