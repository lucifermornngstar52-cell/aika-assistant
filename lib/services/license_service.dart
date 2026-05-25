import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Telegram Bot — прямые запросы без backend
const String _botToken = '8339740462:AAH8HywtjV2TfCS6MVnSwka4CidpNPdSIK4';
const String _ownerChatId = '7500697130';
const String _tgApi = 'https://api.telegram.org/bot$_botToken';

// Base44 API для проверки лицензии (только для check — читаем из базы через публичный endpoint)
// Для check используем Telegram polling (агент обновляет базу, Flutter проверяет через простой GET)
// Мы используем простой JSON файл на GitHub как "лицензионный сервер"
const String _licenseCheckUrl = 'https://raw.githubusercontent.com/lucifermornngstar52-cell/aika-assistant/main/licenses.json';

class LicenseStatus {
  final bool valid;
  final String reason;
  final String? expiresAt;
  final String? email;
  final String? plan;

  LicenseStatus({required this.valid, required this.reason, this.expiresAt, this.email, this.plan});
}

class LicenseService {
  static const _keyEmail = 'license_email';
  static const _keyStatus = 'license_status';
  static const _keyExpires = 'license_expires';
  static const _keyLastCheck = 'license_last_check';

  static Future<void> saveEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, email.toLowerCase().trim());
  }

  static Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyEmail);
  }

  // Проверяем лицензию через GitHub JSON файл (обновляется агентом)
  static Future<LicenseStatus> checkLicenseByEmail(String email) async {
    try {
      final response = await http.get(
        Uri.parse('$_licenseCheckUrl?t=${DateTime.now().millisecondsSinceEpoch}'),
        headers: {'Cache-Control': 'no-cache'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final userEmail = email.toLowerCase().trim();
        
        if (data.containsKey(userEmail)) {
          final info = data[userEmail] as Map<String, dynamic>;
          final status = info['status'] ?? 'pending';
          
          if (status == 'active') {
            final expiresStr = info['expires_at'] as String?;
            if (expiresStr != null) {
              final expires = DateTime.tryParse(expiresStr);
              if (expires != null && expires.isAfter(DateTime.now())) {
                await _cacheStatus('active', expiresStr);
                return LicenseStatus(valid: true, reason: 'active', expiresAt: expiresStr, email: email);
              }
              return LicenseStatus(valid: false, reason: 'expired');
            }
          }
          return LicenseStatus(valid: false, reason: status);
        }
        return LicenseStatus(valid: false, reason: 'not_found');
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

  // Регистрация — просто сохраняем локально
  static Future<Map<String, dynamic>> register({required String email, required String fullName}) async {
    await saveEmail(email);
    return {'success': true};
  }

  // Отправляем заявку напрямую в Telegram
  static Future<Map<String, dynamic>> submitPayment({
    required String email,
    required String fullName,
    required String plan,
    required String paymentMethod,
  }) async {
    try {
      final amount = plan == 'purchase' ? 3000 : 2800;
      final bankName = paymentMethod == 'kaspi' ? 'Kaspi' : 'Freedom';
      final planText = plan == 'purchase' ? '🛒 Покупка (3000 ₸)' : '🔄 Подписка (2800 ₸/мес)';
      final requestId = '${email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}_${DateTime.now().millisecondsSinceEpoch}';

      final msg = '🔔 <b>Новая заявка на оплату Aika</b>\n\n'
          '👤 <b>Имя:</b> ${fullName.isEmpty ? "—" : fullName}\n'
          '📧 <b>Email:</b> <code>$email</code>\n'
          '📱 <b>Тариф:</b> $planText\n'
          '💰 <b>Сумма:</b> $amount ₸\n'
          '🏦 <b>Способ:</b> $bankName\n'
          '🆔 <b>ID:</b> <code>$requestId</code>';

      final keyboard = {
        'inline_keyboard': [
          [
            {'text': '✅ Разрешить', 'callback_data': 'approve:$email'},
            {'text': '❌ Запретить', 'callback_data': 'reject:$email'},
          ]
        ]
      };

      final response = await http.post(
        Uri.parse('$_tgApi/sendMessage'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': _ownerChatId,
          'text': msg,
          'parse_mode': 'HTML',
          'reply_markup': keyboard,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (data['ok'] == true) {
        // Сохраняем статус pending локально
        await _cacheStatus('pending', null);
        return {'success': true, 'request_id': requestId};
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
