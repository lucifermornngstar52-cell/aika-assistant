import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_launcher_service.dart';

/// ════════════════════════════════════════════════════════════════════════════
/// AppAliasService кастомные команды приложений.
/// Пользователь задаёт: команда «музон» → Яндекс Музыка.
/// Дальше «вруби музон» / «открой музон» Айка открывает нужное приложение.
/// Хранится локально в SharedPreferences: [{cmd, package, label}]
/// ════════════════════════════════════════════════════════════════════════════
class AppAlias {
 final String cmd;
 final String package;
 final String label;
 AppAlias({required this.cmd, required this.package, required this.label});

 Map<String, String> toJson() => {'cmd': cmd, 'package': package, 'label': label};
 static AppAlias fromJson(Map<String, dynamic> j) => AppAlias(
 cmd: j['cmd']?? '',
 package: j['package']?? '',
 label: j['label']?? '',
);
}

class AppAliasService {
 static const _key = 'aika_app_aliases_v1';
 static List<AppAlias>? _cache;

 /// Все алиасы пользователя.
 static Future<List<AppAlias>> getAll() async {
 if (_cache!= null) return _cache!;
 try {
 final prefs = await SharedPreferences.getInstance();
 final raw = prefs.getString(_key)?? '[]';
 _cache = (jsonDecode(raw) as List)
.map((e) => AppAlias.fromJson(Map<String, dynamic>.from(e as Map)))
.toList();
 } catch (_) {
 _cache = [];
 }
 return _cache!;
 }

 static Future<void> _save(List<AppAlias> list) async {
 _cache = list;
 final prefs = await SharedPreferences.getInstance();
 await prefs.setString(_key, jsonEncode(list.map((a) => a.toJson()).toList()));
 }

 /// Добавить или обновить алиас (по команде).
 static Future<void> upsert(AppAlias alias) async {
 final list = await getAll();
 final clean = alias.cmd.trim().toLowerCase();
 list.removeWhere((a) => a.cmd == clean);
 list.add(AppAlias(cmd: clean, package: alias.package, label: alias.label));
 await _save(list);
 }

 static Future<void> remove(String cmd) async {
 final list = await getAll();
 list.removeWhere((a) => a.cmd == cmd.trim().toLowerCase());
 await _save(list);
 }

 /// Ищет алиас по фразе пользователя (после отрезания «открой/вруби»).
 /// Возвращает пакет, если фраза совпала с командой алиаса.
 static Future<AppAlias?> resolve(String phrase) async {
 final t = phrase.trim().toLowerCase();
 if (t.isEmpty) return null;
 final aliases = await getAll();
 for (final a in aliases) {
 if (a.cmd.isEmpty) continue;
 // «музон» или «вруби музон» → совпадает
 if (t == a.cmd || t.contains(a.cmd)) return a;
 }
 return null;
 }

 /// Точное совпадение фразы с командой алиаса (без триггерных слов).
 /// «музон» == алиас «музон» → да; «музон это круто» → нет.
 static Future<AppAlias?> resolveExact(String phrase) async {
 final t = phrase.trim().toLowerCase();
 if (t.isEmpty) return null;
 // отрезаем мягкие хвостовые слова: «музон пожалуйста», «музон давай»
 for (final tail in const ['пожалуйста', 'давай', 'скорее', 'быстро']) {
 if (t.endsWith(' $tail')) {
 return resolveExact(t.substring(0, t.length - tail.length - 1));
 }
 }
 for (final a in await getAll()) {
 if (a.cmd.isNotEmpty && t == a.cmd) return a;
 }
 return null;
 }

 /// Точка входа для голосовых/текстовых команд: «вруби музон».
 /// Возвращает строку-ответ, если алиас сработал, иначе null.
 static Future<String?> tryLaunch(String phrase) async {
 // Отрезаем триггерные слова в начале (может быть два подряд:
 // «эй, вруби музон» → «музон»)
 var t = phrase.trim().toLowerCase();
 const prefixes = [
 'эй,', 'эй', 'ну', 'давай', 'мне', 'пожалуйста',
 'врубай', 'вруби', 'включи мне', 'включи', 'включить',
 'открой мне', 'открой-ка', 'открой', 'открыть мне', 'открыть',
 'запусти', 'запустить', 'покажи мне', 'покажи', 'показать',
 'зайди в', 'зайди', 'перейди в', 'перейди',
 'заведи', 'turn on', 'open', 'launch', 'start', 'go',
 ];
 // До двух префиксов подряд: «эй давай вруби музон»
 var strippedAny = false;
 for (var i = 0; i < 2; i++) {
 var stripped = false;
 for (final p in prefixes) {
 if (t.startsWith('$p ')) {
 t = t.substring(p.length + 1).trim();
 stripped = true;
 strippedAny = true;
 break;
 }
 }
 if (!stripped) break;
 }
 // Голая фраза без триггера («музон») — только ТОЧНОЕ совпадение:
 // обычная фраза с этим словом внутри приложения не запускает.
 // С триггером («вруби музон») — мягкий contains.
 final alias = strippedAny
 ? await resolve(t)
 : await resolveExact(t);
 if (alias == null) return null;
 // «выключи музон» не открываем
 if (phrase.trim().toLowerCase().startsWith('выключи') ||
 phrase.trim().toLowerCase().startsWith('отключи')) {
 return null;
 }
 final ok = await AppLauncherService.launchPackage(alias.package);
 return ok? 'Открываю ${alias.label}': '${alias.label} не установлено';
 }
}
