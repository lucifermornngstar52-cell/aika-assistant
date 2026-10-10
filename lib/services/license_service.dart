import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис лицензирования Aika.
/// Приложение активируется кодом, привязанным к ID устройства:
/// deviceIdHash = SHA-256('aika::' + ANDROID_ID) — первые 12 hex-символов, верхний регистр
/// код активации = 'AK-' + первые 6 символов HMAC-SHA256(SECRET, deviceIdHash) в hex, верхний регистр
/// Проверка полностью офлайн, без сервера.
class LicenseService {
 static const _channel = MethodChannel('com.aika.assistant/license');
 static const _secret = '185f4581ecc7a95d842b149299b26cb00f145cdeb74fa652';
 static const _prefKey = 'aika_licensed';
 static const _firstRunKey = 'aika_first_run_epoch';
 static const _trialDays = 4;

 /// Нативный ANDROID_ID устройства.
 static Future<String> _getAndroidId() async {
 try {
 final id = await _channel.invokeMethod<String>('getDeviceId');
 return id?? '';
 } catch (_) {
 return '';
 }
 }

 /// Публичный ID устройства (то, что видит пользователь на экране активации).
 static Future<String> getDeviceHash() async {
 final androidId = await _getAndroidId();
 final digest = sha256.convert(utf8.encode('aika::$androidId'));
 return digest.toString().substring(0, 12).toUpperCase();
 }

 /// Ожидаемый код активации для данного устройства.
 static String expectedCode(String deviceHash) {
 final digest = Hmac(sha256, utf8.encode(_secret))
.convert(utf8.encode(deviceHash));
 return 'AK-${digest.toString().substring(0, 6).toUpperCase()}';
 }

 /// Куплена ли полная версия (код введён).
 static Future<bool> isLicensed() async {
 final prefs = await SharedPreferences.getInstance();
 return prefs.getBool(_prefKey)?? false;
 }

 /// Осталось дней триала (0 — триал кончился).
 /// Дата первого запуска фиксируется при первом обращении.
 static Future<int> daysLeft() async {
 final prefs = await SharedPreferences.getInstance();
 final now = DateTime.now().millisecondsSinceEpoch;
 var first = prefs.getInt(_firstRunKey);
 if (first == null) {
 await prefs.setInt(_firstRunKey, now);
 first = now;
 }
 final left = _trialDays - (now - first) / 86400000;
 if (left <= 0) return 0;
 return left.ceil();
 }

 /// Действует ли доступ: либо куплено, либо триал ещё идёт.
 static Future<bool> isActivated() async {
 if (await isLicensed()) return true;
 return await daysLeft() > 0;
 }

 /// Проверяет введённый код. При успехе запоминает активацию.
 static Future<bool> activate(String code) async {
 final deviceHash = await getDeviceHash();
 final normalized = code.trim().toUpperCase();
 if (normalized == expectedCode(deviceHash)) {
 final prefs = await SharedPreferences.getInstance();
 await prefs.setBool(_prefKey, true);
 return true;
 }
 return false;
 }
}
