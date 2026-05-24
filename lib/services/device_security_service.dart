import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'telegram_bot_service.dart';

/// Система защиты устройства через Telegram-команды
class DeviceSecurityService {
  static const _channel     = MethodChannel('com.aika.assistant/security');
  static const _keyEnabled  = 'security_enabled';
  static const _keyPassword = 'security_password'; // кодовое слово для команд
  static const _owmKey      = '30b398816f9dc8ec92454b67c2172c31';

  // ── Настройки ────────────────────────────────────────────────────────────
  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_keyEnabled) ?? false;
  }

  static Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyEnabled, v);
  }

  static Future<String> getPassword() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyPassword) ?? '';
  }

  static Future<void> setPassword(String pw) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyPassword, pw.trim().toLowerCase());
  }

  // ── Распознавание команды безопасности ──────────────────────────────────
  /// Вернёт true если текст — команда безопасности (и выполнит её)
  static Future<bool> handleTelegramCommand(String text, String chatId) async {
    if (!(await isEnabled())) return false;

    final t    = text.toLowerCase().trim();
    final pass = await getPassword();

    // Формат: "[пароль] команда" или просто команда (если пароль не задан)
    String cmd = t;
    if (pass.isNotEmpty) {
      if (!t.startsWith(pass)) return false; // не наш
      cmd = t.substring(pass.length).trim();
    }

    if (_isLockCommand(cmd)) {
      await _executeLockAndLocate(chatId);
      return true;
    }
    if (_isLocateCommand(cmd)) {
      await _sendLocation(chatId);
      return true;
    }
    if (_isAlarmCommand(cmd)) {
      await _executeAlarm(chatId);
      return true;
    }
    if (_isStatusCommand(cmd)) {
      await _sendStatus(chatId);
      return true;
    }
    return false;
  }

  /// Проверка команд из голосового чата Айки (без пароля — уже на телефоне)
  static bool isSecurityVoiceCommand(String text) {
    final t = text.toLowerCase();
    return t.contains('заблокируй') && (t.contains('экран') || t.contains('телефон') || t.contains('устройство')) ||
        t.contains('покажи где я') || t.contains('моя геолокация') ||
        t.contains('режим тревоги') || t.contains('сигнал тревоги') ||
        t.contains('защита устройства');
  }

  static Future<String> handleVoiceSecurityCommand(String text) async {
    final t = text.toLowerCase();
    if (t.contains('заблокируй')) {
      await lockScreen();
      return '🔒 Экран заблокирован';
    }
    if (t.contains('покажи где я') || t.contains('геолокац')) {
      final loc = await getLocationText();
      return '📍 $loc';
    }
    if (t.contains('тревог') || t.contains('сигнал')) {
      await triggerAlarm();
      return '🚨 Тревога включена!';
    }
    return '';
  }

  // ── Команды ─────────────────────────────────────────────────────────────
  static bool _isLockCommand(String t) =>
      t.contains('заблокируй') || t.contains('lock') || t.contains('блокировка') ||
      t.contains('заблокировать') || t == 'lock screen';

  static bool _isLocateCommand(String t) =>
      t.contains('где') || t.contains('locate') || t.contains('геолокац') ||
      t.contains('местополож') || t == 'где ты' || t.contains('найди телефон');

  static bool _isAlarmCommand(String t) =>
      t.contains('тревог') || t.contains('alarm') || t.contains('сигнал') ||
      t.contains('sos') || t.contains('помогите');

  static bool _isStatusCommand(String t) =>
      t.contains('статус') || t.contains('status') || t.contains('состояние') ||
      t.contains('заряд') || t.contains('battery');

  // ── Действия ─────────────────────────────────────────────────────────────
  static Future<void> lockScreen() async {
    try {
      await _channel.invokeMethod('lockScreen');
    } catch (e) {
      // Fallback: попробуем через accessibility
      try {
        await _channel.invokeMethod('lockScreenAccessibility');
      } catch (_) {}
    }
  }

  static Future<void> triggerAlarm() async {
    try {
      await _channel.invokeMethod('triggerAlarm');
    } catch (_) {}
  }

  static Future<String> getLocationText() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return 'GPS выключен';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return 'Нет разрешения на GPS';
      }
      if (permission == LocationPermission.deniedForever) return 'GPS заблокирован в настройках';

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // Обратное геокодирование через OWM
      final url = 'https://api.openweathermap.org/data/2.5/weather'
          '?lat=${pos.latitude}&lon=${pos.longitude}&appid=$_owmKey&lang=ru';
      String cityInfo = '';
      try {
        final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
        final d = jsonDecode(resp.body);
        cityInfo = d['name'] ?? '';
      } catch (_) {}

      final latStr = pos.latitude.toStringAsFixed(6);
      final lonStr = pos.longitude.toStringAsFixed(6);
      final googleLink = 'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';

      String result = '';
      if (cityInfo.isNotEmpty) result += '📌 $cityInfo\n';
      result += '🌐 $latStr, $lonStr\n';
      result += '🗺 <a href="$googleLink">Открыть на карте</a>';
      return result;
    } catch (e) {
      return 'Ошибка GPS: $e';
    }
  }

  // ── Составные действия ───────────────────────────────────────────────────
  static Future<void> _executeLockAndLocate(dynamic chatId) async {
    // Сначала геолокацию (пока экран ещё не заблокирован)
    final loc = await getLocationText();
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';

    await TelegramBotService.sendToChatId(
      chatId,
      '🔒 <b>Экран заблокирован</b>\n'
      '🕐 $timeStr\n\n'
      '📍 <b>Последнее местоположение:</b>\n$loc',
    );

    // Блокируем экран
    await lockScreen();
  }

  static Future<void> _sendLocation(dynamic chatId) async {
    final loc = await getLocationText();
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';

    await TelegramBotService.sendToChatId(
      chatId,
      '📍 <b>Местоположение устройства</b>\n'
      '🕐 $timeStr\n\n'
      '$loc',
    );
  }

  static Future<void> _executeAlarm(dynamic chatId) async {
    await triggerAlarm();
    final loc = await getLocationText();
    await TelegramBotService.sendToChatId(
      chatId,
      '🚨 <b>ТРЕВОГА АКТИВИРОВАНА</b>\n\n'
      '📍 <b>Местоположение:</b>\n$loc\n\n'
      'Устройство издаёт сигнал тревоги.',
    );
  }

  static Future<void> _sendStatus(dynamic chatId) async {
    final loc = await getLocationText();
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';

    await TelegramBotService.sendToChatId(
      chatId,
      '📱 <b>Статус устройства</b>\n'
      '🕐 $timeStr\n\n'
      '📍 <b>Местоположение:</b>\n$loc\n\n'
      '✅ Устройство онлайн и отвечает',
    );
  }
}
