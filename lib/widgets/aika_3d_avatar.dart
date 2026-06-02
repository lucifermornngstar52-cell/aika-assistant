import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 3D GLB модель через model_viewer_plus ^1.6.1.
/// Работает оффлайн — грузит модели из assets.
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
  String _modelPath = 'assets/models/aika_model.glb';

  static const _models = {
    'aika_glb':    'assets/models/aika_model.glb',
    'anime_girl':  'assets/models/anime_girl.glb',
    'michelle':    'assets/models/michelle.glb',
    'robot_glb':   'assets/models/robot.glb',
    'xbot_glb':    'assets/models/xbot.glb',
    'soldier_glb': 'assets/models/soldier.glb',
  };

  static const _animMap = {
    'idle':      'Idle',
    'listening': 'Idle',
    'thinking':  'No',
    'talking':   'Yes',
    'greeting':  'WaveHello',
    'dance':     'Dance',
    'stretch':   'Idle',
  };

  String get _animName =>
      _animMap[widget.state ?? 'idle'] ?? 'Idle';

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('live2d_model_id') ?? 'aika_glb';
    if (_models.containsKey(saved) && mounted) {
      setState(() => _modelPath = _models[saved]!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ModelViewer(
        key: ValueKey(_modelPath),
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
