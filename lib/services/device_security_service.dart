import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'telegram_bot_service.dart';

/// Система защиты устройства через Telegram-команды
class DeviceSecurityService {
  static const _channel     = MethodChannel('com.aika.assistant/security');
  static const _keyEnabled  = 'security_enabled';
  static const _keyPassword = 'security_password';
  static const _owmKey      = '30b398816f9dc8ec92454b67c2172c31';

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

  static Future<bool> handleTelegramCommand(String text, String chatId) async {
    if (!(await isEnabled())) return false;
    final t    = text.toLowerCase().trim();
    final pass = await getPassword();

    String cmd = t;
    if (pass.isNotEmpty) {
      if (!t.startsWith(pass)) return false;
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

  static bool isSecurityVoiceCommand(String text) {
    final t = text.toLowerCase();
    return (t.contains('заблокируй') && (t.contains('экран') || t.contains('телефон') || t.contains('устройство'))) ||
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

  static Future<void> lockScreen() async {
    try {
      await _channel.invokeMethod('lockScreen');
    } catch (_) {
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

  /// Геолокация через IP (без GPS-разрешений)
  static Future<String> getLocationText() async {
    try {
      final resp = await http
          .get(Uri.parse('http://ip-api.com/json/?fields=city,regionName,country,lat,lon'))
          .timeout(const Duration(seconds: 6));
      final d = jsonDecode(resp.body);
      final city    = (d['city'] as String?) ?? '';
      final region  = (d['regionName'] as String?) ?? '';
      final country = (d['country'] as String?) ?? '';
      final lat     = (d['lat'] as num?)?.toDouble() ?? 0.0;
      final lon     = (d['lon'] as num?)?.toDouble() ?? 0.0;

      final googleLink = 'https://maps.google.com/?q=$lat,$lon';
      final latStr     = lat.toStringAsFixed(4);
      final lonStr     = lon.toStringAsFixed(4);

      String result = '';
      if (city.isNotEmpty) result += '📌 $city, $region, $country\n';
      result += '🌐 $latStr, $lonStr\n';
      result += '🗺 <a href="$googleLink">Открыть на карте</a>';
      return result;
    } catch (e) {
      return 'Ошибка определения местоположения: $e';
    }
  }

  static String _timeStr() {
    final now = DateTime.now();
    final h   = now.hour.toString().padLeft(2, '0');
    final m   = now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static Future<void> _executeLockAndLocate(dynamic chatId) async {
    final loc = await getLocationText();
    await TelegramBotService.sendToChatId(
      chatId,
      '🔒 <b>Экран заблокирован</b>\n'
      '🕐 ${_timeStr()}\n\n'
      '📍 <b>Последнее местоположение:</b>\n$loc',
    );
    await lockScreen();
  }

  static Future<void> _sendLocation(dynamic chatId) async {
    final loc = await getLocationText();
    await TelegramBotService.sendToChatId(
      chatId,
      '📍 <b>Местоположение устройства</b>\n'
      '🕐 ${_timeStr()}\n\n'
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
    await TelegramBotService.sendToChatId(
      chatId,
      '📱 <b>Статус устройства</b>\n'
      '🕐 ${_timeStr()}\n\n'
      '📍 <b>Местоположение:</b>\n$loc\n\n'
      '✅ Устройство онлайн и отвечает',
    );
  }
}
