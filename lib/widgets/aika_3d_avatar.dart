import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 3D GLB модель через model_viewer_plus.
/// Работает оффлайн — грузит модель из assets.
class Aika3DAvatar extends StatefulWidget {
  final String? state;          // idle | listening | thinking | dance | greeting
  final double width;
  final double height;

  const Aika3DAvatar({
    Key? key,
    this.state,
    this.width = double.infinity,
    this.height = 300,
  }) : super(key: key);

  @override
  State<Aika3DAvatar> createState() => _Aika3DAvatarState();
}

class _Aika3DAvatarState extends State<Aika3DAvatar> {
  String _modelPath = 'assets/models/aika_model.glb';
  String _modelId   = 'aika_glb';

  static const _models = {
    'aika_glb':    'assets/models/aika_model.glb',
    'anime_girl':  'assets/models/anime_girl.glb',
    'michelle':    'assets/models/michelle.glb',
    'robot_glb':   'assets/models/robot.glb',
    'xbot_glb':    'assets/models/xbot.glb',
    'soldier_glb': 'assets/models/soldier.glb',
  };

  // Маппинг состояний → имена анимаций
  static const _animMap = {
    'idle':      'Idle',
    'listening': 'Idle',
    'thinking':  'No',
    'talking':   'Yes',
    'greeting':  'WaveHello',
    'dance':     'Dance',
    'stretch':   'Idle',
  };

  String get _animName {
    return _animMap[widget.state ?? 'idle'] ?? 'Idle';
  }

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('live2d_model_id') ?? 'aika_glb';
    // Берём только 3D модели
    if (_models.containsKey(saved)) {
      setState(() {
        _modelId   = saved;
        _modelPath = _models[saved]!;
      });
    }
  }

  @override
  void didUpdateWidget(Aika3DAvatar old) {
    super.didUpdateWidget(old);
    // Перечитываем модель при изменении виджета
    if (old.state != widget.state) {
      // Состояние применяется через animationName ниже
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ModelViewer(
        key: ValueKey(_modelPath),                // Ключ — перестраиваем при смене модели
        src: _modelPath,
        alt: 'Aika 3D avatar',
        autoPlay: true,
        animationName: _animName,
        autoRotate: false,
        disableZoom: true,
        backgroundColor: const Color(0x00000000), // Прозрачный фон
        shadowIntensity: 0.3,
        shadowSoftness: 1.0,
        cameraControls: false,
        cameraOrbit: '0deg 75deg 2.5m',
        fieldOfView: '30deg',
        // Без CDN — работает через встроенный WebView
      ),
    );
  }
}
