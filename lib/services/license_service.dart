import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// License check — читаем licenses.json с GitHub
const String _licenseCheckUrl =
    'https://raw.githubusercontent.com/lucifermornngstar52-cell/aika-assistant/main/licenses.json';

// Заявки отправляются на Superagent endpoint — он уведомит владельца
const String _submitUrl =
    'https://app.base44.com/api/apps/6a0da5c66b1ec5f4ed5468be/functions/submitLicenseRequest';

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
  static const _keyEmail   = 'license_email';
  static const _keyStatus  = 'license_status';
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

  // Проверяем лицензию через GitHub JSON
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
                return LicenseStatus(
                    valid: true, reason: 'active', expiresAt: expiresStr, email: email);
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

  static Future<Map<String, dynamic>> register({
    required String email,
    required String fullName,
  }) async {
    await saveEmail(email);
    return {'success': true};
  }

  // Отправляем заявку на Superagent — он сразу уведомит владельца
  static Future<Map<String, dynamic>> submitPayment({
    required String email,
    required String fullName,
    required String plan,
    required String paymentMethod,
  }) async {
    try {
      final amount = plan == 'purchase' ? 3000 : 2800;

      final response = await http.post(
        Uri.parse(_submitUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.toLowerCase().trim(),
          'full_name': fullName.isEmpty ? email.split('@')[0] : fullName,
          'plan': plan,
          'payment_method': paymentMethod,
          'amount': amount,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        await _cacheStatus('pending', null);
        return {'success': true, 'request_id': data['request_id'] ?? ''};
      }
      return {'success': false, 'error': data['error'] ?? 'Ошибка сервера'};
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
