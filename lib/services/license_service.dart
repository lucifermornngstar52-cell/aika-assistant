import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String _apiBase = 'https://6a0a90581faa5976de138d8f.base44.app/functions/aikaLicenseApi';

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
    await prefs.setString(_keyEmail, email);
  }

  static Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyEmail);
  }

  static Future<LicenseStatus> checkLicenseByEmail(String email) async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/check?email=${Uri.encodeComponent(email)}'),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      final valid = data['valid'] == true;
      final reason = data['reason'] ?? (valid ? 'active' : 'not_found');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyStatus, reason);
      await prefs.setString(_keyLastCheck, DateTime.now().toIso8601String());
      if (data['expires_at'] != null) {
        await prefs.setString(_keyExpires, data['expires_at']);
      }

      return LicenseStatus(valid: valid, reason: reason, expiresAt: data['expires_at'], email: email);
    } catch (e) {
      return _checkCached();
    }
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

  static Future<Map<String, dynamic>> register({required String email, required String fullName}) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBase/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'full_name': fullName, 'google_id': email}),
      ).timeout(const Duration(seconds: 10));
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> submitPayment({
    required String email,
    required String fullName,
    required String plan,
    required String paymentMethod,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBase/submit_payment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'google_id': email,
          'email': email,
          'full_name': fullName,
          'plan': plan,
          'payment_method': paymentMethod,
          'screenshot_url': '',
          'telegram_chat_id': '',
        }),
      ).timeout(const Duration(seconds: 10));
      return jsonDecode(response.body);
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
