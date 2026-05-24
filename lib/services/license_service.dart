import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String _apiBase = 'https://6a0a90581faa5976de138d8f.base44.app/functions/aikaLicenseApi';

class LicenseStatus {
  final bool valid;
  final String reason; // not_found, pending, rejected, expired, active
  final String? expiresAt;
  final String? email;
  final String? fullName;
  final String? plan;

  LicenseStatus({
    required this.valid,
    required this.reason,
    this.expiresAt,
    this.email,
    this.fullName,
    this.plan,
  });
}

class LicenseService {
  static const _keyGoogleId = 'license_google_id';
  static const _keyEmail = 'license_email';
  static const _keyName = 'license_name';
  static const _keyStatus = 'license_status';
  static const _keyExpires = 'license_expires';
  static const _keyLastCheck = 'license_last_check';

  /// Сохранить данные Google аккаунта локально
  static Future<void> saveGoogleAccount({
    required String googleId,
    required String email,
    required String name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGoogleId, googleId);
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyName, name);
  }

  /// Получить сохранённый Google ID
  static Future<String?> getSavedGoogleId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyGoogleId);
  }

  static Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyEmail);
  }

  static Future<String?> getSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyName);
  }

  /// Проверить лицензию через сервер
  static Future<LicenseStatus> checkLicense(String googleId) async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/check?google_id=$googleId'),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      final valid = data['valid'] == true;
      final reason = data['reason'] ?? (valid ? 'active' : 'unknown');

      // Кэшируем результат
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyStatus, reason);
      await prefs.setString(_keyLastCheck, DateTime.now().toIso8601String());
      if (data['expires_at'] != null) {
        await prefs.setString(_keyExpires, data['expires_at']);
      }

      return LicenseStatus(
        valid: valid,
        reason: reason,
        expiresAt: data['expires_at'],
        email: data['email'],
        fullName: data['full_name'],
        plan: data['plan'],
      );
    } catch (e) {
      // Оффлайн режим — проверяем кэш
      return _checkCachedLicense();
    }
  }

  /// Проверить кэшированный статус (для оффлайна)
  static Future<LicenseStatus> _checkCachedLicense() async {
    final prefs = await SharedPreferences.getInstance();
    final status = prefs.getString(_keyStatus);
    final expiresStr = prefs.getString(_keyExpires);
    final lastCheckStr = prefs.getString(_keyLastCheck);

    // Если давно не проверяли (>3 дня) — не пускаем
    if (lastCheckStr != null) {
      final lastCheck = DateTime.tryParse(lastCheckStr);
      if (lastCheck != null) {
        final diff = DateTime.now().difference(lastCheck).inDays;
        if (diff > 3) {
          return LicenseStatus(valid: false, reason: 'offline_expired');
        }
      }
    }

    if (status == 'active' && expiresStr != null) {
      final expires = DateTime.tryParse(expiresStr);
      if (expires != null && expires.isAfter(DateTime.now())) {
        return LicenseStatus(
          valid: true,
          reason: 'active',
          expiresAt: expiresStr,
          email: prefs.getString(_keyEmail),
          fullName: prefs.getString(_keyName),
        );
      }
    }

    return LicenseStatus(valid: false, reason: status ?? 'not_found');
  }

  /// Зарегистрировать пользователя
  static Future<Map<String, dynamic>> register({
    required String googleId,
    required String email,
    required String fullName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBase/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'google_id': googleId,
          'email': email,
          'full_name': fullName,
        }),
      ).timeout(const Duration(seconds: 10));
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Отправить заявку на оплату
  static Future<Map<String, dynamic>> submitPayment({
    required String googleId,
    required String email,
    required String fullName,
    required String plan,
    required String paymentMethod,
    String? screenshotUrl,
    String? telegramChatId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBase/submit_payment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'google_id': googleId,
          'email': email,
          'full_name': fullName,
          'plan': plan,
          'payment_method': paymentMethod,
          'screenshot_url': screenshotUrl ?? '',
          'telegram_chat_id': telegramChatId ?? '',
        }),
      ).timeout(const Duration(seconds: 10));
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Получить реквизиты
  static Future<Map<String, dynamic>> getPaymentInfo(String plan) async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/payment_info?plan=$plan'),
      ).timeout(const Duration(seconds: 10));
      return jsonDecode(response.body);
    } catch (e) {
      return {
        'kaspi': {'card': '4400 4300 6272 0914', 'amount': plan == 'purchase' ? 3000 : 2800},
        'freedom': {'card': '4002 8900 5058 4816', 'amount': plan == 'purchase' ? 3000 : 2800},
      };
    }
  }

  /// Выйти из аккаунта
  static Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyGoogleId);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyName);
    await prefs.remove(_keyStatus);
    await prefs.remove(_keyExpires);
    await prefs.remove(_keyLastCheck);
  }
}
