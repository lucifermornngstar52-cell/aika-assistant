import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 3D GLB модель через model_viewer_plus.
/// Пути без префикса "assets/" — model_viewer_plus добавляет его сам на Android.
class Aika3DAvatar extends StatefulWidget {
  final String? state;
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
  String _modelId = 'anime_girl';

  // Пути — model_viewer_plus принимает 'assets/...' на Flutter
  static const _models = {
    'anime_girl':  'assets/models/anime_girl.glb',
    'aika_glb':    'assets/models/aika_model.glb',
    'robot_glb':   'assets/models/robot.glb',
    'xbot_glb':    'assets/models/xbot.glb',
  };

  // Реальные имена анимаций из GLB файлов
  static const _animMapAnime = {
    'idle':      'idle',
    'listening': 'idle',
    'thinking':  'sneak_pose',
    'talking':   'agree',
    'greeting':  'agree',
    'dance':     'SambaDance',
    'music':     'SambaDance',
    'happy':     'agree',
    'sad':       'sad_pose',
    'surprised': 'headShake',
    'stretch':   'sneak_pose',
    'alarm':     'run',
    'walk':      'walk',
  };

  static const _animMapRobot = {
    'idle':      'Idle',
    'listening': 'Idle',
    'thinking':  'No',
    'talking':   'Yes',
    'greeting':  'Wave',
    'dance':     'Dance',
    'music':     'Dance',
    'happy':     'ThumbsUp',
    'sad':       'Death',
    'surprised': 'Jump',
    'stretch':   'Sitting',
    'alarm':     'Running',
    'walk':      'Walking',
  };

  String get _modelPath => _models[_modelId] ?? _models['anime_girl']!;

  bool get _isRobot => _modelId == 'robot_glb';

  String get _animName {
    final state = widget.state ?? 'idle';
    final map = _isRobot ? _animMapRobot : _animMapAnime;
    return map[state] ?? (_isRobot ? 'Idle' : 'idle');
  }

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('model_3d_id') ?? 'anime_girl';
    if (_models.containsKey(saved) && mounted) {
      setState(() => _modelId = saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ModelViewer(
        key: ValueKey(_modelPath + (_animName)),
        src: _modelPath,
        alt: 'Aika 3D avatar',
        autoPlay: true,
        animationName: _animName,
        disableZoom: true,
        backgroundColor: const Color(0x00000000),
        shadowIntensity: 0.3,
        shadowSoftness: 1.0,
        cameraControls: false,
        cameraOrbit: '0deg 75deg 2.5m',
        fieldOfView: '30deg',
      ),
    );
  }
}
