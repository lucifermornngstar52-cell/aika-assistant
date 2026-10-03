import 'package:flutter/services.dart';

/// ════════════════════════════════════════════════════════════════════════════
/// SystemControlService управление системными настройками:
/// Wi-Fi и Bluetooth (прямое переключение, с фолбэком на системную панель)
/// Яркость экрана (требует WRITE_SETTINGS запрашиваем у пользователя)
/// Громкость медиа (0100%)
/// Нативная сторона: канал com.aika.assistant/system в MainActivity.kt
/// ════════════════════════════════════════════════════════════════════════════
class SystemControlService {
 static const _ch = MethodChannel('com.aika.assistant/system');

 /// Есть ли право менять системные настройки (WRITE_SETTINGS).
 static Future<bool> hasWriteSettings() async {
 try {
 return await _ch.invokeMethod<bool>('hasWriteSettings')?? false;
 } catch (_) {
 return false;
 }
 }

 /// Открывает системный экран «Разрешить изменение настроек» для Айки.
 static Future<void> requestWriteSettings() async {
 try {
 await _ch.invokeMethod('requestWriteSettings');
 } catch (_) {}
 }

 /// Включает/выключает Wi-Fi.
 /// На Android 10+ прямое включение запрещено системой тогда откроется
 /// системная панель интернета (пользователь жмёт тумблер сам).
 /// Возвращает true, если переключено напрямую без панели.
 static Future<bool> setWifi(bool enabled) async {
 try {
 return await _ch.invokeMethod<bool>('setWifi', {'enabled': enabled})?? false;
 } catch (_) {
 return false;
 }
 }

 /// Включает/выключает Bluetooth (на Android 13+ выключение и включение
 /// ограничены фолбэк на системный диалог/настройки).
 static Future<bool> setBluetooth(bool enabled) async {
 try {
 return await _ch.invokeMethod<bool>('setBluetooth', {'enabled': enabled})?? false;
 } catch (_) {
 return false;
 }
 }

 /// Ставит яркость экрана в процентах (0100). Нужен WRITE_SETTINGS.
 /// Возвращает false, если права нет тогда надо запросить доступ.
 static Future<bool> setBrightness(int percent) async {
 try {
 return await _ch.invokeMethod<bool>('setBrightness', {
 'percent': percent.clamp(0, 100),
 })?? false;
 } catch (_) {
 return false;
 }
 }

 /// Текущая яркость: {'percent': int, 'auto': bool}
 static Future<Map<String, dynamic>?> getBrightness() async {
 try {
 final r = await _ch.invokeMethod('getBrightness');
 if (r == null) return null;
 final map = r as Map;
 return {
 'percent': map['percent']?? 50,
 'auto': map['auto']?? false,
 };
 } catch (_) {
 return null;
 }
 }

 /// Ставит громкость медиа в процентах (0100).
 static Future<bool> setVolume(int percent) async {
 try {
 return await _ch.invokeMethod<bool>('setVolume', {
 'percent': percent.clamp(0, 100),
 })?? false;
 } catch (_) {
 return false;
 }
 }

 /// Текущая громкость медиа в процентах (0100).
 static Future<int> getVolume() async {
 try {
 return await _ch.invokeMethod<int>('getVolume')?? 50;
 } catch (_) {
 return 50;
 }
 }

 // ═══════════════════════════════════════════════════════════════════════
 // ГОЛОСОВЫЕ КОМАНДЫ
 // ═══════════════════════════════════════════════════════════════════════

 /// Разбирает команду управления настройками. null не команда.
 /// Возвращает текст-ответ для пользователя.
 static Future<String?> tryHandleCommand(String text) async {
 final t = text.toLowerCase().trim();
 if (t.isEmpty) return null;

 final isOn = t.contains('включи') || t.contains('вруб') || t.contains('включить') ||
 t.contains('зажги') || t.contains('подключи');
 final isOff = t.contains('выключи') || t.contains('выруби') || t.contains('выключить') ||
 t.contains('отключи') || t.contains('потуши');
 if (!isOn &&!isOff) {
 // яркость/громкость могут быть без включи/выключи
 return _tryBrightnessVolume(t, hasVerb: false);
 }
 final enable = isOn;

 // ── Wi-Fi ──
 if (_hasAny(t, ['wifi', 'вайфай', 'вай фай', 'wi-fi', 'wi fi', 'вайфае'])) {
 final direct = await setWifi(enable);
 if (direct) {
 return enable? 'Wi-Fi включён': 'Wi-Fi выключен';
 }
 return enable
? 'Прямое включение запрещено системой открыл панель интернета, переключи там'
: 'Открыл панель интернета выключи Wi-Fi тумблером';
 }

 // ── Bluetooth ──
 if (_hasAny(t, ['блютуз', 'bluetooth', 'блюзуб', 'блютуфе', 'bt']) &&
!_hasAny(t, ['гарнитура', 'наушник'])) {
 final direct = await setBluetooth(enable);
 if (direct) {
 return enable? 'Bluetooth включён': 'Bluetooth выключен';
 }
 return enable
? 'Открыл системный диалог подтверди включение Bluetooth'
: 'Открыл настройки Bluetooth выключи там';
 }

 return _tryBrightnessVolume(t, hasVerb: true);
 }

 static Future<String?> _tryBrightnessVolume(String t, {required bool hasVerb}) async {
 // ── Яркость: «яркость 70», «поставь яркость 50», «сделай ярче/темнее» ──
 if (_hasAny(t, ['яркост', 'ярче', 'темнее', 'потемнее', 'посветлее', 'brightness'])) {
 final percent = _extractNumber(t);
 final cur = await getBrightness();
 var target = cur?['percent']?? 50;

 if (_hasAny(t, ['ярче', 'посветлее', 'увеличь'])) {
 target = ((cur?['percent']?? 50) as int) + (percent?? 20);
 } else if (_hasAny(t, ['темнее', 'потемнее', 'уменьши'])) {
 target = ((cur?['percent']?? 50) as int) - (percent?? 20);
 } else if (percent!= null) {
 target = percent;
 } else if (t.contains('макси')) {
 target = 100;
 } else if (t.contains('мин')) {
 target = 5;
 }
 target = target.clamp(5, 100);

 if (!await hasWriteSettings()) {
 await requestWriteSettings();
 return 'Чтобы менять яркость, разреши Айке изменять системные настройки открыл окно';
 }
 final ok = await setBrightness(target);
 return ok? 'Яркость $target%': 'Не удалось изменить яркость';
 }

 // ── Громкость: «громкость 70», «сделай громче/тише» ──
 if (hasVerb && _hasAny(t, ['громкост', 'громче', 'потише', 'тише', 'volume'])) {
 final percent = _extractNumber(t);
 final cur = await getVolume();
 var target = cur;

 if (_hasAny(t, ['громче', 'увеличь'])) {
 target = cur + (percent?? 20);
 } else if (_hasAny(t, ['тише', 'потише', 'уменьши'])) {
 target = cur - (percent?? 20);
 } else if (percent!= null) {
 target = percent;
 } else if (t.contains('макси')) {
 target = 100;
 } else if (t.contains('миним')) {
 target = 5;
 }
 target = target.clamp(0, 100);

 final ok = await setVolume(target);
 return ok? 'Громкость $target%': 'Не удалось изменить громкость';
 }

 return null;
 }

 static bool _hasAny(String t, List<String> keys) {
 for (final k in keys) {
 if (t.contains(k)) return true;
 }
 return false;
 }

 static int? _extractNumber(String t) {
 final m = RegExp(r'(\d{1,3})').firstMatch(t);
 return m == null? null: int.tryParse(m.group(1)!);
 }
}
