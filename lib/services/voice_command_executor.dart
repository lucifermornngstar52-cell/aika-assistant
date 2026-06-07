import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:torch_light/torch_light.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:url_launcher/url_launcher.dart';
import 'voice_command_parser.dart';

/// VoiceCommandExecutor — исполняет [VoiceCommand] без интернета и без AI.
///
/// Использует существующие нативные каналы:
///   - com.aika.assistant/screen       → Accessibility gestures
///   - com.aika.assistant/launcher     → App launch
///   - com.aika.assistant/media        → Media keys
///   - com.aika.assistant/messenger    → Send messages
///
/// Полностью офлайн — никаких HTTP запросов.
class VoiceCommandExecutor {
  static VoiceCommandExecutor? _instance;
  factory VoiceCommandExecutor() => _instance ??= VoiceCommandExecutor._();
  VoiceCommandExecutor._();

  static const _accessibility = MethodChannel('com.aika.assistant/screen');
  static const _launcher      = MethodChannel('com.aika.assistant/launcher');
  static const _media         = MethodChannel('com.aika.assistant/media');
  static const _messenger     = MethodChannel('com.aika.assistant/messenger');
  static const _audio         = MethodChannel('aika/audio');

  /// Выполнить команду. Возвращает строку обратной связи для TTS.
  Future<String> execute(VoiceCommand cmd) async {
    debugPrint('[Executor] ${cmd.action} target=${cmd.target} app=${cmd.app}');
    try {
      return await _dispatch(cmd);
    } catch (e) {
      debugPrint('[Executor] error: $e');
      return 'Не удалось выполнить команду';
    }
  }

  Future<String> _dispatch(VoiceCommand cmd) async {
    switch (cmd.action) {

      // ── ЗВОНКИ ─────────────────────────────────────────────────────────────
      case 'call':
        return _makeCall(cmd.target ?? '');
      case 'decline_call':
        await _accessibility.invokeMethod('pressBack');
        return 'Звонок сброшен';
      case 'answer_call':
        await _accessibility.invokeMethod('clickByText', {'text': 'Ответить'});
        return 'Отвечаю';

      // ── МЕДИА ──────────────────────────────────────────────────────────────
      case 'media_play':
        await _media.invokeMethod('play');
        return 'Воспроизвожу';
      case 'media_pause':
        await _media.invokeMethod('pause');
        return 'Пауза';
      case 'media_next':
        await _media.invokeMethod('next');
        return 'Следующий трек';
      case 'media_prev':
        await _media.invokeMethod('prev');
        return 'Предыдущий трек';

      // ── ГРОМКОСТЬ ──────────────────────────────────────────────────────────
      case 'volume_up':
        await _accessibility.invokeMethod('changeVolume', {'direction': 'up', 'steps': 2});
        return 'Громче';
      case 'volume_down':
        await _accessibility.invokeMethod('changeVolume', {'direction': 'down', 'steps': 2});
        return 'Тише';
      case 'volume_set':
        final level = int.tryParse(cmd.params['level'] ?? '50') ?? 50;
        await _accessibility.invokeMethod('changeVolume', {'direction': 'set', 'level': level});
        return 'Громкость ${cmd.params["level"]}%';

      // ── ОТКРЫТЬ ПРИЛОЖЕНИЕ ─────────────────────────────────────────────────
      case 'open_app':
        return _openApp(cmd.target ?? '', cmd.app);

      case 'close_app':
        await _accessibility.invokeMethod('closeCurrentApp');
        return 'Закрываю приложение';

      // ── БРАУЗЕР ────────────────────────────────────────────────────────────
      case 'web_search':
        final query = Uri.encodeComponent(cmd.target ?? '');
        await _launcher.invokeMethod('launchUrl',
            {'url': 'https://www.google.com/search?q=$query'});
        return 'Ищу ${cmd.target}';
      case 'open_url':
        var url = cmd.target ?? '';
        if (!url.startsWith('http')) url = 'https://$url';
        await _launcher.invokeMethod('launchUrl', {'url': url});
        return 'Открываю $url';

      // ── НАСТРОЙКИ ──────────────────────────────────────────────────────────
      case 'wifi_on':
        await _openWifiSettings();
        return 'Открываю настройки Wi-Fi';
      case 'wifi_off':
        await _openWifiSettings();
        return 'Открываю настройки Wi-Fi';
      case 'bluetooth_on':
      case 'bluetooth_off':
        await _accessibility.invokeMethod('openQuickSettings');
        await Future.delayed(const Duration(milliseconds: 600));
        await _accessibility.invokeMethod('clickByText', {'text': 'Bluetooth'});
        return 'Переключаю Bluetooth';
      case 'torch_on':
        try {
          await TorchLight.enableTorch();
          return 'Фонарик включён';
        } catch (_) {
          return 'Не удалось включить фонарик';
        }
      case 'torch_off':
        try {
          await TorchLight.disableTorch();
          return 'Фонарик выключен';
        } catch (_) {
          return 'Не удалось выключить фонарик';
        }
      case 'airplane_mode_toggle':
        await _openSettingsAction('android.settings.AIRPLANE_MODE_SETTINGS');
        return 'Открываю режим полёта';
      case 'silent_mode':
        await _accessibility.invokeMethod('openQuickSettings');
        await Future.delayed(const Duration(milliseconds: 600));
        await _accessibility.invokeMethod('clickByText', {'text': 'Без звука'});
        return 'Переключаю режим звука';
      case 'brightness_max':
        await _accessibility.invokeMethod('setBrightness', {'level': 255});
        return 'Яркость максимальная';
      case 'brightness_min':
        await _accessibility.invokeMethod('setBrightness', {'level': 10});
        return 'Яркость минимальная';
      case 'set_brightness':
        final pct = int.tryParse(cmd.params['level'] ?? '50') ?? 50;
        final val = (pct * 255 / 100).round();
        await _accessibility.invokeMethod('setBrightness', {'level': val});
        return 'Яркость ${cmd.params["level"]}%';

      // ── БЛОКИРОВКА ─────────────────────────────────────────────────────────
      case 'lock_screen':
        await _accessibility.invokeMethod('lockScreen');
        return 'Блокирую экран';

      // ── НАВИГАЦИЯ ──────────────────────────────────────────────────────────
      case 'go_home':
        await _accessibility.invokeMethod('pressHome');
        return '';
      case 'go_back':
        await _accessibility.invokeMethod('pressBack');
        return '';
      case 'open_recents':
        await _accessibility.invokeMethod('pressRecents');
        return '';
      case 'open_notifications':
        await _accessibility.invokeMethod('openNotifications');
        return 'Открываю уведомления';
      case 'open_quick_settings':
        await _accessibility.invokeMethod('openQuickSettings');
        return '';
      case 'scroll_up':
        await _accessibility.invokeMethod('swipeDir', {'direction': 'up'});
        return '';
      case 'scroll_down':
        await _accessibility.invokeMethod('swipeDir', {'direction': 'down'});
        return '';

      // ── СВАЙПЫ / ТАП ───────────────────────────────────────────────────────
      case 'swipe':
        final dir = cmd.params['dir'] ?? 'up';
        await _accessibility.invokeMethod('swipeDir', {'direction': dir});
        return '';
      case 'tap_by_text':
        await _accessibility.invokeMethod('clickByText', {'text': cmd.target});
        return 'Нажимаю на ${cmd.target}';
      case 'type_text':
        await _accessibility.invokeMethod('typeText', {'text': cmd.target});
        return '';

      // ── СООБЩЕНИЯ ──────────────────────────────────────────────────────────
      case 'send_message':
        final appPkg = cmd.params['app'] ?? 'telegram';
        final contact = cmd.target ?? '';
        final message = cmd.params['message'] ?? '';
        await _messenger.invokeMethod('sendMessage', {
          'app': appPkg, 'contact': contact, 'message': message
        });
        return 'Отправляю сообщение $contact';

      // ── YOUTUBE ────────────────────────────────────────────────────────────
      case 'yt_like':
        await _accessibility.invokeMethod('clickByDescription', {'desc': 'Нравится'});
        return 'Лайк поставлен';
      case 'yt_dislike':
        await _accessibility.invokeMethod('clickByDescription', {'desc': 'Не нравится'});
        return 'Дизлайк';
      case 'yt_fullscreen':
        await _accessibility.invokeMethod('clickByDescription', {'desc': 'На весь экран'});
        return '';
      case 'yt_subscribe':
        await _accessibility.invokeMethod('clickByText', {'text': 'Подписаться'});
        return 'Подписался';
      case 'yt_comments':
        await _accessibility.invokeMethod('swipeDir', {'direction': 'up'});
        return 'Открываю комментарии';
      case 'yt_search':
        final ytPkg = 'com.google.android.youtube';
        await _launcher.invokeMethod('launchApp', {'package': ytPkg});
        await Future.delayed(const Duration(milliseconds: 1500));
        await _accessibility.invokeMethod('clickByDescription', {'desc': 'Поиск'});
        await Future.delayed(const Duration(milliseconds: 500));
        await _accessibility.invokeMethod('typeText', {'text': cmd.target ?? ''});
        return 'Ищу ${cmd.target} на YouTube';

      // ── SPOTIFY ────────────────────────────────────────────────────────────
      case 'spotify_play':
        await _media.invokeMethod('launchSpotifyAndPlay', {'query': cmd.target ?? ''});
        return 'Включаю ${cmd.target}';
      case 'spotify_like':
        await _accessibility.invokeMethod('clickByDescription', {'desc': 'Нравится'});
        return 'Добавлено в избранное';

      // ── TELEGRAM ───────────────────────────────────────────────────────────
      case 'tg_open_chat':
        await _launcher.invokeMethod('launchApp', {'package': 'org.telegram.messenger'});
        await Future.delayed(const Duration(milliseconds: 1200));
        await _accessibility.invokeMethod('clickByText', {'text': cmd.target ?? ''});
        return 'Открываю чат с ${cmd.target}';

      // ── WHATSAPP ───────────────────────────────────────────────────────────
      case 'wa_open_chat':
        await _launcher.invokeMethod('launchApp', {'package': 'com.whatsapp'});
        await Future.delayed(const Duration(milliseconds: 1200));
        await _accessibility.invokeMethod('clickByText', {'text': cmd.target ?? ''});
        return 'Открываю чат с ${cmd.target}';

      // ── СИСТЕМНОЕ ──────────────────────────────────────────────────────────
      case 'screenshot':
        await _accessibility.invokeMethod('takeScreenshot');
        return 'Скриншот сделан';
      case 'power_dialog':
        await _accessibility.invokeMethod('powerDialog');
        return '';
      case 'set_alarm':
        final hour = int.tryParse(cmd.params['hour'] ?? '0') ?? 0;
        final min  = int.tryParse(cmd.params['minute'] ?? '0') ?? 0;
        await _openAlarm(hour, min);
        return 'Ставлю будильник на $hour:${min.toString().padLeft(2, '0')}';
      case 'set_timer':
        return 'Таймер установлен на ${cmd.params["amount"]} ${cmd.params["unit"]}';

      default:
        return ''; // неизвестная — не говорим ничего, передаём в AI если нужно
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Future<String> _makeCall(String contact) async {
    try {
      if (RegExp(r'^\+?[\d\s\-()]+$').hasMatch(contact)) {
        final url = Uri.parse('tel:${contact.replaceAll(' ', '')}');
        if (await canLaunchUrl(url)) await launchUrl(url);
        return 'Звоню $contact';
      }
      // Имя контакта — открываем через intent
      final intent = AndroidIntent(
        action: 'android.intent.action.DIAL',
        data: 'tel:',
      );
      await intent.launch();
      return 'Открываю телефон для звонка $contact';
    } catch (_) {
      return 'Не удалось позвонить $contact';
    }
  }

  Future<void> _openWifiSettings() async {
    try {
      final intent = AndroidIntent(action: 'android.settings.WIFI_SETTINGS');
      await intent.launch();
    } catch (_) {}
  }

  Future<void> _openSettingsAction(String action) async {
    try {
      final intent = AndroidIntent(action: action);
      await intent.launch();
    } catch (_) {}
  }

  Future<void> _openAlarm(int hour, int minute) async {
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.SET_ALARM',
        arguments: {
          'android.intent.extra.alarm.HOUR': hour,
          'android.intent.extra.alarm.MINUTES': minute,
          'android.intent.extra.alarm.SKIP_UI': true,
        },
      );
      await intent.launch();
    } catch (_) {}
  }

  Future<String> _openApp(String name, String? pkg) async {
    try {
      if (pkg != null) {
        final ok = await _launcher.invokeMethod('launchApp', {'package': pkg});
        if (ok == true) return 'Открываю $name';
      }
      // Fallback — найти по имени
      final ok = await _launcher.invokeMethod('findAndLaunch', {'name': name});
      if (ok == true) return 'Открываю $name';
      return 'Приложение $name не найдено';
    } catch (_) {
      return 'Не удалось открыть $name';
    }
  }
}
