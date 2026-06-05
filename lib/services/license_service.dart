import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// API сервер — обрабатывает лицензии и устройства
const String _apiUrl =
    'https://superagent-f0b687b3.base44.app/functions/updateLicense';
const String _appToken = 'app-aika-assistant-v1';

// Telegram бот для уведомлений владельца
const String _botToken = '8339740462:AAH8HywtjV2TfCS6MVnSwka4CidpNPdSIK4';
const int _ownerChatId = 7500697130;

class LicenseStatus {
  final bool valid;
  final String reason;
  final String? expiresAt;
  final String? email;
  final String? plan;

  LicenseStatus({
    required this.valid,
    required this.reason,
    this.expiresAt,
    this.email,
    this.plan,
  });
}

class LicenseService {
  static const _keyEmail     = 'license_email';
  static const _keyStatus    = 'license_status';
  static const _keyExpires   = 'license_expires';
  static const _keyLastCheck = 'license_last_check';
  static const _keyDeviceId  = 'device_id';

  static Future<void> saveEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, email.toLowerCase().trim());
  }

  static Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyEmail);
  }

  // Генерируем уникальный ID устройства (один раз при первом запуске)
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_keyDeviceId);
    if (id == null) {
      id = 'android_${DateTime.now().millisecondsSinceEpoch}_${Platform.numberOfProcessors}';
      await prefs.setString(_keyDeviceId, id);
    }
    return id;
  }

  // Проверяем лицензию через наш API (с регистрацией устройства)
  static Future<LicenseStatus> checkLicenseByEmail(String email) async {
    try {
      final deviceId = await getDeviceId();
      final model = Platform.operatingSystem;
      final androidVersion = Platform.operatingSystemVersion;

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Authorization': 'Bearer $_appToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'action': 'check_license',
          'email': email.toLowerCase().trim(),
          'device_id': deviceId,
          'model': model,
          'android_version': androidVersion,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final valid = data['valid'] == true;
        final reason = data['reason'] as String? ?? 'unknown';

        if (valid) {
          final expiresStr = data['expires_at'] as String?;
          await _cacheStatus('active', expiresStr);
          return LicenseStatus(
            valid: true,
            reason: 'active',
            expiresAt: expiresStr,
            email: email,
            plan: data['plan'] as String?,
          );
        }

        if (reason == 'device_blocked') {
          return LicenseStatus(valid: false, reason: 'device_blocked');
        }
        return LicenseStatus(valid: false, reason: reason);
      }
      return await _checkCached();
    } catch (e) {
      return await _checkCached();
    }
  }

  static Future<void> _cacheStatus(String status, String? expires) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStatus, status);
    await prefs.setString(_keyLastCheck, DateTime.now().toIso8601String());
    if (expires != null) await prefs.setString(_keyExpires, expires);
  }

  static Future<LicenseStatus> _checkCached() async {
    final prefs = await SharedPreferences.getInstance();
    final status = prefs.getString(_keyStatus);
    final expiresStr = prefs.getString(_keyExpires);
    final lastCheckStr = prefs.getString(_keyLastCheck);

    if (lastCheckStr != null) {
      final diff = DateTime.now().difference(DateTime.parse(lastCheckStr)).inDays;
      if (diff > 3) return LicenseStatus(valid: false, reason: 'offline_expired');
    }

    if (status == 'active' && expiresStr != null) {
      final expires = DateTime.tryParse(expiresStr);
      if (expires != null && expires.isAfter(DateTime.now())) {
        return LicenseStatus(valid: true, reason: 'active', expiresAt: expiresStr);
      }
    }
    return LicenseStatus(valid: false, reason: status ?? 'not_found');
  }

  static Future<Map<String, dynamic>> register({
    required String email,
    required String fullName,
  }) async {
    await saveEmail(email);
    return {'success': true};
  }

  // Отправляем заявку НАПРЯМУЮ в Telegram владельцу
  static Future<Map<String, dynamic>> submitPayment({
    required String email,
    required String fullName,
    required String plan,
    required String paymentMethod,
  }) async {
    try {
      final amount = plan == 'purchase' ? 3000 : 2800;
      final planLabel = plan == 'purchase' ? '🛒 Покупка' : '🔄 Подписка';
      final bankLabel = paymentMethod == 'kaspi' ? '🟡 Kaspi' : '🟢 Freedom';

      final text =
          '💳 <b>Новая заявка на доступ</b>\n\n'
          '👤 Email: <code>$email</code>\n'
          '📋 Тариф: $planLabel — <b>$amount ₸</b>\n'
          '🏦 Оплата: $bankLabel\n\n'
          '⏳ Ожидает подтверждения оплаты';

      final keyboard = {
        'inline_keyboard': [
          [
            {'text': '✅ Одобрить', 'callback_data': 'approve:$email'},
            {'text': '❌ Отклонить', 'callback_data': 'reject:$email'},
          ]
        ]
      };

      final response = await http.post(
        Uri.parse('https://api.telegram.org/bot$_botToken/sendMessage'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': _ownerChatId,
          'text': text,
          'parse_mode': 'HTML',
          'reply_markup': keyboard,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (data['ok'] == true) {
        await _cacheStatus('pending', null);
        return {'success': true};
      }
      return {'success': false, 'error': data['description'] ?? 'Ошибка Telegram'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyStatus);
    await prefs.remove(_keyExpires);
    await prefs.remove(_keyLastCheck);
  }
}
