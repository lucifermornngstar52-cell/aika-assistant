import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'groq_model_catalog.dart';

import 'overlay_service.dart';
import 'aika_log_service.dart';

/// ═════════════════════════════════════════════════════════════════════
/// Minecraft Pilot — игровой автопилот Айки.
///
/// Цикл: скриншот → Groq vision → действие → скриншот → …
/// Работает поверх AccessibilityService: жесты + реальный захват пикселей.
/// ═════════════════════════════════════════════════════════════════════
class MinecraftAutopilotService {
  static const _ch = MethodChannel('com.aika.assistant/screen_reader');

  // Groq vision (бесплатно) — та же мультимодальная модель, что и в AiService
  static const _groqUrl = 'https://api.groq.com/openai/v1/chat/completions';

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

  // Зашитый в сборку ключ — бэкап, если юзер не вводил свой в настройках.
  static const String _envKey = String.fromEnvironment('GROQ_API_KEY', defaultValue: '');

  static Future<void> _loadKey() async {
    if (_groqKey != null) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('groq_key') ?? '';
    _groqKey = saved.isNotEmpty ? saved : _envKey;
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
      final pRaw = action['params'];
      final p = pRaw is Map<String, dynamic> ? pRaw : <String, dynamic>{};
      AikaLogService.log('autopilot', 'шаг $_iteration: ${action['action']} $p');
      _addLog('── Шаг $_iteration/$maxIterations ──');
      _addLog('🧠 ${action['thought'] ?? ''}');
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
      // и пилот навсегда молчал. Модели берём из живого списка Groq.
      final visionChain =
          await GroqModelCatalog.resolveVision(_groqKey ?? '');
      final modelCandidates = <(String, bool)>[
        for (final m in visionChain) ...(m == visionChain.first
            ? [(m, true), (m, false)]
            : [(m, false)]),
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
      AikaLogService.error('autopilot', 'vision: $e');
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
        final modelCx = p['cx'] as num?;
        final modelCy = p['cy'] as num?;
        if (modelCx == null && modelCy == null) {
          // Модель не увидела джойстик/D-pad — идём вперёд по схеме
          var dur0 = (p['duration'] as num?)?.toDouble() ?? 1500;
          if (dur0 > 0 && dur0 < 10) dur0 *= 1000;
          await _moveForward(w, h, dur0.toInt().clamp(100, 8000));
          break;
        }
        var cx = modelCx?.toDouble() ?? w * 0.12;
        var cy = modelCy?.toDouble() ?? h * 0.88;
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

  // ═══════════════════════════════════════════════════════════════════
  //  ОФЛАЙН-СКИЛЛЫ: простые действия без vision-модели.
  //  Работают по сценарию: жмут за хозяина дерево рубить, копать, бродить.
  //  «Сыграй за меня <цель>» — агентский цикл со зрением (Groq).
  // ═══════════════════════════════════════════════════════════════════

  /// Разбирает голосовую команду автопилота. null — не команда.
  static McSkill? parseSkillCommand(String raw) {
    final t = raw.toLowerCase().replaceAll('ё', 'е');

    if (t.contains('стоп') && _running) return McSkill('stop', '');

    // «беги прямо 5 секунд» / «иди вперёд» — прямая ходьба
    const walkWords = ['беги прямо', 'иди прямо', 'беги вперед', 'иди вперед',
        'беги вперёд', 'иди вперёд', 'пробеги прямо', 'пройди прямо',
        'иди вперед', 'беги вперед', 'шагай прямо'];
    for (final w0 in walkWords) {
      final i = t.indexOf(w0);
      if (i >= 0) {
        // ищем секунды после фразы
        var secs = 3;
        final rest = t.substring(i + w0.length);
        final m = RegExp(r'(\d+)\s*(сек|с)\b').firstMatch(rest);
        if (m != null) secs = int.tryParse(m.group(1)!) ?? 3;
        return McSkill('walk', secs.toString());
      }
    }

    const chopWords = ['наруби дерево', 'руби дерево', 'сруби дерево',
        'напили дерева', 'добудь дерева', 'руби деревья', 'наруби лес'];
    if (chopWords.any((w) => t.contains(w))) return McSkill('chop', '');

    const digWords = ['прокопайся', 'покопай вниз', 'копай вниз',
        'докопайся', 'прокопай вниз', 'копни вниз'];
    if (digWords.any((w) => t.contains(w))) return McSkill('dig', '');

    const wanderWords = ['поброди', 'погуляй в майнкрафте', 'побегай',
        'погуляй по миру', 'поброди по миру'];
    if (wanderWords.any((w) => t.contains(w))) return McSkill('wander', '');

    // «сыграй за меня …» / «сделай в майнкрафте …» — свободная цель для
    // агентского цикла со зрением.
    for (final kw in ['сыграй за меня', 'играй за меня', 'поиграй за меня']) {
      final i = t.indexOf(kw);
      if (i >= 0) {
        var goal = raw.substring(i + kw.length).trim();
        if (goal.isEmpty) goal = 'Наруби древесины и построй укрытие';
        return McSkill('goal', goal);
      }
    }
    for (final kw in ['дойди до координат', 'иди на координаты', 'доберись до координат']) {
      final i = t.indexOf(kw);
      if (i >= 0) {
        final goal =
            'Дойди до координат ${raw.substring(i + kw.length).trim()}. '
            'Координаты показаны в левом верхнем углу экрана. '
            'Иди джойстиком, свайпай камеру, избегай лавы и обрывов.';
        return McSkill('goal', goal);
      }
    }
    return null;
  }

  /// Запускает разобранный скилл. Возвращает итоговый текст-отчёт.
  static Future<String> runSkill(McSkill skill) async {
    switch (skill.name) {
      case 'stop':
        stop();
        await OverlayService().hideTip();
        return 'Остановилась ✓';
      case 'chop':
        return _chop();
      case 'dig':
        return _dig();
      case 'wander':
        return _wander();
      case 'walk':
        return _walk(seconds: int.tryParse(skill.arg) ?? 3);
      case 'goal':
        return start(skill.arg);
      default:
        return 'Не поняла задачу';
    }
  }

  /// Активен ли сейчас какой-то автопилот (скилл или агентский цикл).
  static bool get isBusy => _running;

  // ═══════════════════════════════════════════════════════════════════
  //  СХЕМА УПРАВЛЕНИЯ Bedrock
  //  'classic'  — D-pad (классика, дефолт Bedrock): ходьба = удержание
  //               стрелки «вверх» (≈10% ширины, 76% высоты).
  //  'joystick' — джойстик слева: ходьба = перетаскивание джойстика.
  //  Без этой настройки свайп по экрану попадал в левую стрелку D-pad —
  //  отсюда «бежит влево, когда просил прямо».
  // ═══════════════════════════════════════════════════════════════════
  static String controlScheme = 'classic';
  static const kSchemeClassic = 'classic';
  static const kSchemeJoystick = 'joystick';

  static Future<void> loadControlScheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      controlScheme =
          prefs.getString('mc_control_scheme') ?? kSchemeClassic;
      AikaLogService.log('autopilot', 'схема управления: $controlScheme');
    } catch (_) {}
  }

  static Future<void> setControlScheme(String scheme) async {
    controlScheme = scheme;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mc_control_scheme', scheme);
    } catch (_) {}
    AikaLogService.log('autopilot', 'схема управления → $scheme');
  }

  /// Универсальный шаг вперёд: работает и с D-pad, и с джойстиком.
  /// [ms] — сколько идти. Возвращает true, если жест прошёл.
  static Future<void> _moveForward(int w, int h, int ms) async {
    if (controlScheme == kSchemeJoystick) {
      AikaLogService.debug('autopilot',
          'жест: джойстик вперёд ${ms}мс');
      await _ch.invokeMethod('joystickMove', {
        'cx': w * 0.11, 'cy': h * 0.82,
        'angle': 0.0, 'duration': ms,
      });
    } else {
      // Классика: держим стрелку «вверх» D-pad
      AikaLogService.debug('autopilot',
          'жест: D-pad вверх (${(w * 0.105).toInt()},${(h * 0.76).toInt()}) ${ms}мс');
      await _ch.invokeMethod('holdTouch', {
        'x': (w * 0.105).toDouble(), 'y': (h * 0.76).toDouble(),
        'duration': ms,
      });
    }
  }

  static Future<bool> _checkGestures() async {
    final size = await _getScreenSize();
    return size != null;
  }

  static Future<void> _status(String title, String body) async {
    try { await OverlayService().showTip(title, body, seconds: 120); } catch (_) {}
  }

  /// 🪓 Рубка дерева: циклы «удержание в центре + шаг вперёд за дропом».
  static Future<String> _chop({int cycles = 5}) async {
    if (!await _checkGestures()) {
      return 'Accessibility не включён — включи сервис в настройках';
    }
    final size = await _getScreenSize();
    if (size == null) return 'Не удалось получить размер экрана — включи Accessibility';
    final w = size['width'] as int;
    final h = size['height'] as int;
    _running = true;
    AikaLogService.log('autopilot', 'скилл chop: $cycles циклов, экран ${w}x$h');
    _addLog('🪓 Рублю дерево ($cycles циклов)');
    await _status('⛏️ Айка рубит дерево', 'Держу палец на стволе, не трогай экран');

    var broken = 0;
    for (var i = 0; i < cycles && _running; i++) {
      // Дерево рукой ломается ~3 секунды — держим 3.4 с, чтобы дошло.
      // Ломаем по очереди низ ствола, середину и верх (лезем пальцем вверх).
      for (final fy in [0.56, 0.47, 0.38]) {
        if (!_running) break;
        AikaLogService.debug('autopilot',
            'жест: ломаю блок (${(w * 0.5).toInt()},${(h * fy).toInt()}) 3400мс');
        await _ch.invokeMethod('holdTouch', {
          'x': (w * 0.5).toDouble(), 'y': (h * fy).toDouble(),
          'duration': 3400,
        });
        await Future.delayed(const Duration(milliseconds: 600));
      }
      if (!_running) break;
      broken++;
      _addLog('Цикл ${i + 1}/$cycles ✓');
      // Короткий шаг вперёд — подобрать дропы (не проскочить дерево)
      await _moveForward(w, h, 600);
      await Future.delayed(const Duration(milliseconds: 500));
    }
    final stopped = !_running;
    _running = false;
    await OverlayService().hideTip();
    return stopped
        ? 'Остановилась, успела $broken циклов рубки'
        : '🪓 Нарубила дерево: $broken циклов рубки. Проверь инвентарь!';
  }

  /// ⛏️ Копание вниз: «посмотреть под ноги → удержание → упать на блок».
  /// Максимум 3 блока — классика «не копай вниз» уважаем, но слушаем хозяина.
  static Future<String> _dig({int blocks = 3}) async {
    if (!await _checkGestures()) {
      return 'Accessibility не включён — включи сервис в настройках';
    }
    final size = await _getScreenSize();
    if (size == null) return 'Не удалось получить размер экрана — включи Accessibility';
    final w = size['width'] as int;
    final h = size['height'] as int;
    _running = true;
    AikaLogService.log('autopilot', 'скилл dig: $blocks блока вниз');
    _addLog('⛏️ Копаю вниз ($blocks блока)');
    await _status('⛏️ Айка копает вниз', 'Осторожно, я не вижу пещеры снизу!');

    for (var i = 0; i < blocks && _running; i++) {
      // Смотреть под ноги
      await _ch.invokeMethod('swipe', {
        'x1': (w * 0.75).toDouble(), 'y1': (h * 0.45).toDouble(),
        'x2': (w * 0.75).toDouble(), 'y2': (h * 0.75).toDouble(),
        'duration': 300,
      });
      await Future.delayed(const Duration(milliseconds: 400));
      // Держим в центре — ломается блок под ногами
      await _ch.invokeMethod('holdTouch', {
        'x': (w * 0.5).toDouble(), 'y': (h * 0.50).toDouble(), 'duration': 2300,
      });
      await Future.delayed(const Duration(milliseconds: 900));
      _addLog('Блок ${i + 1}/$blocks выкопан');
    }
    _running = false;
    await OverlayService().hideTip();
    return '⛏️ Прокопалась на $blocks блока вниз. Осторожно, снизу может быть пещера — не падай!';
  }

  /// 🏃 Бег прямо: «беги прямо 5 секунд».
  static Future<String> _walk({int seconds = 3}) async {
    if (!await _checkGestures()) {
      return 'Accessibility не включён — включи сервис в настройках';
    }
    final size = await _getScreenSize();
    if (size == null) return 'Не удалось получить размер экрана — включи Accessibility';
    final w = size['width'] as int;
    final h = size['height'] as int;
    _running = true;
    AikaLogService.log('autopilot', 'скилл walk: вперёд $seconds сек ($controlScheme)');
    _addLog('🏃 Бегу прямо $seconds сек');
    await _status('🏃 Айка бежит прямо', 'Держу направление, не трогай экран');

    var msLeft = seconds * 1000;
    // Классика: holdTouch ограничен — идём порциями по 4 секунды
    while (_running && msLeft > 0) {
      final chunk = msLeft > 4000 ? 4000 : msLeft;
      await _moveForward(w, h, chunk);
      await Future.delayed(const Duration(milliseconds: 300));
      msLeft -= chunk + 300;
    }
    _running = false;
    await OverlayService().hideTip();
    return '🏃 Пробежала прямо $seconds секунд ($controlScheme). Куда дальше?';
  }

  /// 🚶 Прогулка: случайные повороты + ходьба + прыжки.
  static Future<String> _wander({int seconds = 30}) async {
    if (!await _checkGestures()) {
      return 'Accessibility не включён — включи сервис в настройках';
    }
    final size = await _getScreenSize();
    if (size == null) return 'Не удалось получить размер экрана — включи Accessibility';
    final w = size['width'] as int;
    final h = size['height'] as int;
    _running = true;
    AikaLogService.log('autopilot', 'скилл wander: $seconds сек');
    _addLog('🚶 Гуляю $seconds сек');
    await _status('🚶 Айка бродит по миру', 'Иду куда глаза глядят');

    final rnd = DateTime.now().millisecondsSinceEpoch;
    final started = DateTime.now();
    var steps = 0;
    while (_running && DateTime.now().difference(started).inSeconds < seconds) {
      final phase = (rnd + steps * 137) % 360;
      // Ходьба 2 сек вперёд (схема-зависимо), направление меняем камерой
      await _moveForward(w, h, 2000);
      await Future.delayed(const Duration(milliseconds: 500));
      // Поворот камеры
      final dir = (rnd + steps * 71) % 2 == 0 ? 1 : -1;
      await _ch.invokeMethod('swipe', {
        'x1': (w * 0.75).toDouble(), 'y1': (h * 0.45).toDouble(),
        'x2': (w * (0.75 + dir * 0.15)).toDouble(),
        'y2': (h * 0.45).toDouble(),
        'duration': 400,
      });
      await Future.delayed(const Duration(milliseconds: 400));
      // Прыжок каждый 3-й шаг
      if (steps % 3 == 0) {
        await _ch.invokeMethod('tapAt', {
          'x': (w * 0.90).toDouble(), 'y': (h * 0.86).toDouble(),
        });
      }
      await Future.delayed(const Duration(milliseconds: 1200));
      steps++;
    }
    _running = false;
    await OverlayService().hideTip();
    return '🚶 Погуляла: $steps шагов. Красивый мир у тебя!';
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

/// Разобранная команда автопилота.
class McSkill {
  final String name; // chop | dig | wander | goal | stop
  final String arg;  // текст цели для 'goal'
  const McSkill(this.name, this.arg);
}
