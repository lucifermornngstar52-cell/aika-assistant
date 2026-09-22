import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// ═════════════════════════════════════════════════════════════════════
/// Minecraft Pilot — игровой автопилот Айки.
///
/// Цикл: скриншот → Groq vision → действие → скриншот → …
/// Работает поверх AccessibilityService: жесты + реальный захват пикселей.
/// ═════════════════════════════════════════════════════════════════════
class MinecraftPilotService {
  static const _ch = MethodChannel('com.aika.assistant/screen_reader');

  // Groq vision (бесплатно) — та же мультимодальная модель, что и в AiService
  static const _groqUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const _visionModel = 'qwen/qwen3.6-27b';

  // ── Состояние ─────────────────────────────────────────────────────
  static bool _running = false;
  static bool get isRunning => _running;

  static int _iteration = 0;
  static int get iteration => _iteration;

  static String _goal = '';
  static final List<String> _log = [];

  /// Слушатель лога для UI (каждая строка лога).
  static void Function(String line)? onLog;

  // ── Настройки цикла ───────────────────────────────────────────────
  /// Пауза после действия перед новым скриншотом (мс).
  static int actionDelayMs = 2500;
  /// Максимальное число итераций (защита от вечного цикла).
  static int maxIterations = 100;

  static String? _groqKey;

  static Future<void> _loadKey() async {
    if (_groqKey != null) return;
    final prefs = await SharedPreferences.getInstance();
    _groqKey = prefs.getString('groq_key') ?? '';
  }

  static void _addLog(String line) {
    _log.add(line);
    if (_log.length > 200) _log.removeRange(0, _log.length - 200);
    onLog?.call(line);
  }

  static List<String> get logs => List.unmodifiable(_log);

  /// Останавливает пилота.
  static void stop() {
    _running = false;
    _addLog('⏹ Остановлено пользователем (итерация $_iteration)');
  }

  /// Сбрасывает счётчики и лог.
  static void reset() {
    _iteration = 0;
    _log.clear();
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ГЛАВНЫЙ ЦИКЛ
  // ═══════════════════════════════════════════════════════════════════

  /// Запускает игровой цикл. [goal] — что делать в игре, например
  /// «доберись до дерева и наруби 5 древесины».
  /// Работает, пока: не done, не maxIterations, не stop().
  static Future<String> start(String goal) async {
    if (_running) return 'Пилот уже запущен';
    await _loadKey();
    if (_groqKey == null || _groqKey!.isEmpty) {
      return 'Нет Groq API ключа — добавь его в Настройки → ИИ-модели';
    }

    _goal = goal;
    _running = true;
    _iteration = 0;
    _addLog('🚀 Пилот запущен. Цель: $goal');

    final history = <String>[];
    var result = 'Цикл завершён';

    // Геометрия экрана — джойстик и зона обзора считаем от неё
    final size = await _getScreenSize();
    if (size == null) {
      _running = false;
      return 'Не удалось получить размер экрана — включи Accessibility';
    }
    final w = size['width'] as int;
    final h = size['height'] as int;

    var consecutiveFails = 0;
    while (_running && _iteration < maxIterations) {
      // 1. Скриншот
      final b64 = await _captureScreen();
      if (b64 == null) {
        consecutiveFails++;
        _addLog('❌ Скриншот не получился ($consecutiveFails/5)');
        if (consecutiveFails >= 5) {
          result = 'Экран не захватывается. Проверь: Accessibility включён и перепривязан, Android 11+, игра открыта';
          break;
        }
        await Future.delayed(const Duration(seconds: 3));
        continue;
      }

      // 2. Спрашиваем vision-модель
      final action = await _askVision(b64, w, h, history);
      if (action == null) {
        // ФИКС: раньше неудача vision сжигала итерацию — 60 ошибок подряд
        // молча выедали весь лимит. Теперь считаем только реальные шаги.
        consecutiveFails++;
        _addLog('❌ Vision не ответил ($consecutiveFails/5), жду 5с');
        if (consecutiveFails >= 5) {
          result = 'Vision-модель не отвечает 5 раз подряд — смотри ошибки Groq выше (ключ? лимиты?)';
          break;
        }
        await Future.delayed(const Duration(seconds: 5));
        continue;
      }
      consecutiveFails = 0;

      _iteration++;
      _addLog('── Шаг $_iteration/$maxIterations ──');
      _addLog('🧠 ${action['thought'] ?? ''}');
      final pRaw = action['params'];
      final p = pRaw is Map<String, dynamic> ? pRaw : <String, dynamic>{};
      _addLog('🎮 ${action['action']} $p');

      history.add('${action['action']} ${jsonEncode(p)}');
      if (history.length > 8) history.removeAt(0);

      // 3. Выполняем.
      // ФИКС: раньше одно исключение из жеста убивало весь запуск
      // без единого сообщения — теперь логируем и продолжаем.
      final act = action['action'] as String? ?? 'none';
      var done = false;
      try {
        done = await _execute(act, p, w, h);
      } catch (e) {
        _addLog('⚠️ Жест не удался: $e — пробую дальше');
      }

      if (done) {
        _addLog('✅ Задача выполнена!');
        result = 'Готово: ${action['thought']}';
        break;
      }

      // 4. Ждём, пока действие применится
      await Future.delayed(Duration(milliseconds: actionDelayMs));
    }

    _running = false;
    if (_iteration >= maxIterations) {
      _addLog('⏹ Лимит итераций исчерпан');
      result = 'Достигнут лимит итераций ($maxIterations)';
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  VISION — Groq
  // ═══════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>?> _askVision(
      String imgB64, int w, int h, List<String> history) async {
    final prompt = '''
Ты — автопилот, который ИГРАЕТ В Minecraft Bedrock на Android-телефоне вместо хозяина.
Ты видишь скриншот экрана игры (размер экрана ${w}x${h} пикселей).

ЦЕЛЬ: $_goal
Последние действия: ${history.join(' | ')}

Управление Minecraft (сенсорное):
• Джойстик движения — левый нижний угол экрана
• Обзор/поворот камеры — свайп по правой половине экрана
• Разрушить блок — УДЕРЖИВАТЬ палец на блоке ~2-5 сек
• Поставить блок / атаковать / открыть сундук — короткий тап
• Кнопка прыжка — правый нижний угол
• Инвентарь, крафт, чат — тапом по соответствующим иконкам

Ответь ТОЛЬКО JSON (без markdown):
{
  "thought": "что ты видишь и что делаешь, 1 фраза на русском",
  "action": "move" | "look" | "tap" | "hold" | "none" | "done",
  "params": {
    // move: идти джойстиком; cx/cy — центр джойстика В ПИКСЕЛЯХ (видно на скриншоте, левый нижний угол)
    "angle": 0-360,
    "cx": 150, "cy": 1900,
    "duration": 1500,
    // look: повернуть камеру (dx>0=вправо, dy>0=вниз; доли экрана)
    "dx": 0.3, "dy": -0.1,
    // tap: короткое касание (поставить блок/атака/кнопка/меню)
    "x": 500, "y": 900,
    // hold: удержание пальца (ломать блок) — x, y, duration
  }
}

Правила:
• Действие за раз ОДНО, максимально конкретное.
• Координаты x/y — ПИКСЕЛИ экрана 0..$w и 0..$h.
• Если экран не игры (меню, лобби) — сначала тапни нужную кнопку.
• Если цель выполнена — "done".
• НИКОГДА не выдумывай кнопки, которых не видно на скриншоте.
''';

    try {
      // ФИКС: раньше один 400/404 (модель не та / параметр не тот) —
      // и пилот навсегда молчал. Теперь пробуем комбинации по очереди.
      const modelCandidates = [
        // (модель, с reasoning_effort или без)
        (_visionModel, true),
        (_visionModel, false),
        ('meta-llama/llama-4-scout-17b-16e-instruct', false), // запасная vision-модель Groq
      ];

      http.Response? resp;
      String? failReason;
      for (final (m, useRef) in modelCandidates) {
        final body = {
          'model': m,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/jpeg;base64,$imgB64'},
                },
              ],
            }
          ],
          'temperature': 0.2,
          'max_tokens': 400,
          // Без этого qwen уходит в thinking-режим и не выдаёт JSON действия.
          if (useRef) 'reasoning_effort': 'none',
        };
        resp = await http.post(
          Uri.parse(_groqUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_groqKey',
            // Cloudflare у Groq банит не-браузерные клиенты (403, код 1010).
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36',
            'Accept': 'application/json',
          },
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 30));

        if (resp.statusCode == 200) break;

        final snip = utf8.decode(resp.bodyBytes);
        failReason = 'HTTP ${resp.statusCode}: '
            '${snip.length > 120 ? snip.substring(0, 120) : snip}';
        if (resp.statusCode == 429) {
          _addLog('⏳ Лимит Groq, жду 15с…');
          await Future.delayed(const Duration(seconds: 15));
        }
        _addLog('⚠️ Groq $m → $failReason');
        if (resp.statusCode != 400 && resp.statusCode != 404) {
          // 401/403 — ключ, 500-е — сервис: дальше перебирать бессмысленно,
          // но не роняем пилот — вернёмся через цикл.
          return null;
        }
        // 400/404 — пробуем следующую комбинацию
      }
      if (resp == null || resp.statusCode != 200) {
        _addLog('⚠️ Groq отклонил все варианты: $failReason');
        return null;
      }

      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      var text = data['choices']?[0]?['message']?['content'] as String? ?? '';
      text = text.trim();
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start == -1 || end == -1 || end <= start) return null;
      final json = jsonDecode(text.substring(start, end + 1));
      return json is Map<String, dynamic> ? json : null;
    } catch (e) {
      _addLog('⚠️ Ошибка vision: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ВЫПОЛНЕНИЕ ДЕЙСТВИЙ
  // ═══════════════════════════════════════════════════════════════════

  /// Возвращает true, если задача завершена (done).
  static Future<bool> _execute(
      String action, Map<String, dynamic> p, int w, int h) async {
    switch (action) {
      case 'move':
        // Джойстик: модель ВИДИТ скриншот и может указать его точный центр (cx/cy).
        // Если не указала — левый нижний угол (как в Bedrock classic).
        var cx = (p['cx'] as num?)?.toDouble() ?? w * 0.12;
        var cy = (p['cy'] as num?)?.toDouble() ?? h * 0.88;
        // если модель прислала доли (0..1) вместо пикселей — переводим
        if (cx >= 0 && cx <= 1) cx *= w;
        if (cy >= 0 && cy <= 1) cy *= h;
        cx = cx.clamp(10.0, w - 10.0);
        cy = cy.clamp(10.0, h - 10.0);
        var angle = (p['angle'] as num?)?.toDouble();
        // Модель иногда присылает dx/dy вместо angle — переводим:
        // dx>0 = вправо, dy>0 = вниз; angle: 0=вперёд, 90=вправо, 180=назад, 270=влево
        if (angle == null) {
          final dx = (p['dx'] as num?)?.toDouble() ?? 0.0;
          final dy = (p['dy'] as num?)?.toDouble() ?? 0.0;
          if (dx != 0 || dy != 0) {
            angle = 90.0 * dx + 180.0 * dy.abs();
          }
        }
        angle ??= 0.0;
        var dur = (p['duration'] as num?)?.toDouble() ?? 1500;
        // модель может прислать секунды вместо миллисекунд
        if (dur > 0 && dur < 10) dur *= 1000;
        await _ch.invokeMethod('joystickMove', {
          'cx': cx, 'cy': cy,
          'angle': angle, 'duration': dur.toInt().clamp(100, 8000),
        });
        break;

      case 'look':
        // Модель присылает ЛИБО dx/dy (доли экрана), ЛИБО angle (0=вверх, 90=вправо).
        var dx = (p['dx'] as num?)?.toDouble();
        var dy = (p['dy'] as num?)?.toDouble();
        final angle = (p['angle'] as num?)?.toDouble();
        if (dx == null && dy == null && angle != null) {
          // angle: 90 → вправо на пол-экрана, 270 → влево, 0 → вверх, 180 → вниз
          dx = 0.5 * (angle == 90 ? 1 : angle == 270 ? -1 : 0);
          dy = angle == 0 ? -0.25 : angle == 180 ? 0.25 : 0.0;
        }
        dx ??= 0.3;
        dy ??= 0.0;
        final sx = w * 0.75, sy = h * 0.45;
        // ФИКС: было sx - dx*w — камера крутилась в ПРОТИВОПОЛОЖНУЮ сторону:
        // модель просит вправо, а пилот смотрел влево, и промахивался всегда.
        // Теперь свайп идёт в ту сторону, которую просит модель.
        final x2 = (sx + dx * w).clamp(10.0, w - 10.0);
        final y2 = (sy + dy * h).clamp(10.0, h - 10.0);
        await _ch.invokeMethod('swipe', {
          'x1': sx, 'y1': sy,
          'x2': x2.toDouble(), 'y2': y2.toDouble(),
          'duration': 300,
        });
        await Future.delayed(const Duration(milliseconds: 400));
        break;

      case 'tap':
        var x = (p['x'] as num?)?.toDouble() ?? w / 2;
        var y = (p['y'] as num?)?.toDouble() ?? h / 2;
        // модель любит присылать координаты долями экрана (0..1) — учитываем
        if (x >= 0 && x <= 1 && y >= 0 && y <= 1) { x *= w; y *= h; }
        await _ch.invokeMethod('tapAt', {
          'x': x.clamp(5.0, w - 5.0).toDouble(),
          'y': y.clamp(5.0, h - 5.0).toDouble(),
        });
        break;

      case 'hold':
        var x = (p['x'] as num?)?.toDouble() ?? w / 2;
        var y = (p['y'] as num?)?.toDouble() ?? h / 2;
        if (x >= 0 && x <= 1 && y >= 0 && y <= 1) { x *= w; y *= h; }
        var dur = (p['duration'] as num?)?.toDouble() ?? 3000;
        if (dur > 0 && dur < 10) dur *= 1000; // секунды → мс
        await _ch.invokeMethod('holdTouch', {
          'x': x.clamp(5.0, w - 5.0).toDouble(),
          'y': y.clamp(5.0, h - 5.0).toDouble(),
          'duration': dur.toInt().clamp(300, 8000),
        });
        break;

      case 'done':
        return true;

      case 'none':
      default:
        await Future.delayed(const Duration(seconds: 2));
        break;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ХЕЛПЕРЫ
  // ═══════════════════════════════════════════════════════════════════

  static Future<Map<String, int>?> _getScreenSize() async {
    try {
      final res = await _ch.invokeMethod('getScreenSize');
      if (res is Map) {
        return {
          'width': (res['width'] as num).toInt(),
          'height': (res['height'] as num).toInt(),
        };
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _captureScreen() async {
    try {
      final b64 = await _ch.invokeMethod('captureScreen', {
        'maxWidth': 720,
        'quality': 55,
      });
      return b64 as String?;
    } on PlatformException catch (e) {
      // ФИКС: раньше молча возвращали null — непонятно, почему сломано.
      // Теперь в логе видно точную причину (Accessibility, версия, код ошибки).
      _addLog('📷 Захват не удался: ${e.message ?? e.code}');
      return null;
    } catch (e) {
      _addLog('📷 Захват не удался: $e');
      return null;
    }
  }

  /// Проверка готовности: Accessibility включён.
  /// Возвращает null если всё ок, иначе текст ошибки.
  static Future<String?> checkSupport() async {
    try {
      final size = await _getScreenSize();
      if (size == null) {
        return 'AccessibilityService не запущен — включи его в настройках. '
            'Важно: после каждого обновления APK Android молча выключает '
            'accessibility-сервис — переподключи его заново';
      }
      return null;
    } on PlatformException catch (e) {
      return e.message;
    }
  }

  /// Запускает официальный Minecraft (Bedrock) через PackageManager.
  static Future<bool> launchMinecraft() async {
    try {
      const ch = MethodChannel('com.aika.assistant/launcher');
      return await ch.invokeMethod('launchApp', {'package': 'com.mojang.minecraftpe'}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
