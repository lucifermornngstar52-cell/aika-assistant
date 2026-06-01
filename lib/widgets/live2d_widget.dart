import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live2D виджет через InAppWebView.
/// Поддерживает встроенные модели (из assets) и кастомные (с телефона).
class Live2DWidget extends StatefulWidget {
  final double width;
  final double height;
  final String state; // idle, listening, thinking, talking, greeting, dance

  /// Путь к встроенной модели внутри assets/ (напр. 'models/Hiyori/Hiyori.model3.json')
  /// Если null — берётся из SharedPreferences или дефолтная Hiyori
  final String? builtinModelAsset;

  /// Абсолютный путь к кастомной модели на устройстве
  final String? customModelPath;

  const Live2DWidget({
    Key? key,
    this.width = 220,
    this.height = 320,
    this.state = 'idle',
    this.builtinModelAsset,
    this.customModelPath,
  }) : super(key: key);

  @override
  State<Live2DWidget> createState() => _Live2DWidgetState();
}

class _Live2DWidgetState extends State<Live2DWidget> {
  InAppWebViewController? _ctrl;
  String _lastState = '';
  bool _ready = false;

  // Сохранённые настройки модели
  String _modelId = 'hiyori';
  String? _savedCustomPath;

  // Маппинг id -> путь внутри assets/models/
  static const _builtinPaths = {
    'natori': 'models/Natori/Natori.model3.json',
    'ren':    'models/Ren/Ren.model3.json',
    'hiyori': 'models/Hiyori/Hiyori.model3.json',
    'haru':   'models/Haru/Haru.model3.json',
  };

  @override
  void initState() {
    super.initState();
    _loadSavedModel();
  }

  Future<void> _loadSavedModel() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _modelId = prefs.getString('live2d_model_id') ?? 'natori';
        _savedCustomPath = prefs.getString('custom_model_path');
      });
    }
  }

  @override
  void didUpdateWidget(Live2DWidget old) {
    super.didUpdateWidget(old);
    if (widget.state != _lastState && _ready) {
      _sendState(widget.state);
    }
  }

  void _sendState(String state) {
    _lastState = state;
    _ctrl?.evaluateJavascript(source: "window.setAikaState('$state')");
  }

  String _buildInitJS() {
    // Определяем какую модель загружать
    final customPath = widget.customModelPath ?? (_modelId == 'custom' ? _savedCustomPath : null);
    final builtinAsset = widget.builtinModelAsset
        ?? _builtinPaths[_modelId]
        ?? _builtinPaths['hiyori']!;

    if (customPath != null) {
      return "window.loadCustomModel('file://$customPath');";
    } else {
      // Встроенная модель — меняем через JS переменную
      return "window.switchBuiltinModel('$builtinAsset');";
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: InAppWebView(
        initialFile: 'assets/live2d_viewer.html',
        initialSettings: InAppWebViewSettings(
          transparentBackground: true,
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          useHybridComposition: true,
          disableDefaultErrorPage: true,
        ),
        onWebViewCreated: (ctrl) {
          _ctrl = ctrl;
          ctrl.addJavaScriptHandler(
            handlerName: 'FlutterChannel',
            callback: (args) {
              final msg = args.isNotEmpty ? args[0].toString() : '';
              if (msg == 'modelLoaded') {
                setState(() => _ready = true);
                // Устанавливаем начальное состояние после загрузки
                Future.delayed(const Duration(milliseconds: 300), () {
                  _sendState(widget.state);
                });
              }
            },
          );
        },
        onLoadStop: (ctrl, url) {
          Future.delayed(const Duration(milliseconds: 800), () {
            // Сначала переключаем модель если нужно
            final initJs = _buildInitJS();
            ctrl.evaluateJavascript(source: initJs);
          });
        },
      ),
    );
  }
}
