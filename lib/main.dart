import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'widgets/smoke_background.dart';
import 'screens/splash_screen.dart';
import 'services/personality_service.dart';
import 'services/wardrobe_service.dart';
import 'services/theme_switcher_service.dart';
import 'services/ai_service.dart';
import 'services/local_llm_service.dart';
import 'services/aika_log_service.dart';
import 'services/web_search_service.dart';
import 'main_overlay.dart' show overlayMain;

export 'main_overlay.dart' show overlayMain;

/// Оригинальный вывод в консоль (только в debug-сборке).
void kDebugModeOnlyPrint(String? message) {
 if (kDebugMode) {
 // ignore: avoid_print
 print(message);
 }
}

void main() async {
 WidgetsFlutterBinding.ensureInitialized();

 // ПЕРЕХВАТ: все debugPrint по всему приложению пишутся в лог-просмотрщик.
 debugPrint = (String? message, {int? wrapWidth}) {
 final m = message?? '';
 // ФИКС: раньше тут было m.contains('') — пустая строка матчится всегда,
 // и ВЕСЬ лог красный. Ошибкой считаем только реальные маркеры ошибок.
 final isErr = m.contains('Exception') || m.contains('Error') ||
 m.contains('Ошибка') || m.contains('ошибка') ||
 m.contains('не удался') || m.contains('не удалось') ||
 m.contains('FAIL') || m.contains('403') ||
 m.contains('watchdog') || m.contains('не поднялся');
 AikaLogService.log('flutter', m,
 level: isErr? LogLevel.error: LogLevel.debug);
 kDebugModeOnlyPrint(message);
 };

 await SystemChrome.setPreferredOrientations([
 DeviceOrientation.portraitUp,
 DeviceOrientation.portraitDown,
 ]);

 SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
 statusBarColor: Colors.transparent,
 statusBarIconBrightness: Brightness.light,
 systemNavigationBarColor: AikaTheme.background,
 systemNavigationBarIconBrightness: Brightness.light,
));

 // ФИКС: сбой хранилища при запуске ронял приложение до SplashScreen —
 // теперь приложение стартует даже если настройки не прочитались
 try {
 await PersonalityService.load();
 await ThemeSwitcherService().load();
 await WardrobeService.load();

 final prefs = await SharedPreferences.getInstance();
 // ФИКС (баг «Все AI-сервисы недоступны»): пустые prefs затирали ключи,
 // зашитые в сборку через dart-define. Теперь ключ из настроек важен
 // только если он реально введён, иначе остаётся ключ из сборки.
 final groqSaved = prefs.getString('groq_key')?? '';
 AiService.setGroqKey(groqSaved.isNotEmpty? groqSaved
: const String.fromEnvironment('GROQ_API_KEY', defaultValue: ''));
 AiService.setPreferredModel('groq');
 AiService.setWebSearch(prefs.getBool('ai_web_search')?? true);
 AiService.setMaxTokens(prefs.getInt('ai_max_tokens')?? 1024);
 WebSearchService.setBraveKey(prefs.getString('brave_key')?? '');

 // Pro: локальный режим — если включён, Айка думает на устройстве.
 final localModeOn = prefs.getBool('local_ai_mode')?? false;
 AiService.setLocalMode(localModeOn);
 if (localModeOn) {
 // ФИКС «движок надо грузить руками»: автозагрузка при старте.
 // Стартуем с задержкой, чтобы не конкурировать с инициализацией UI,
 // и не блокируем main(): модель грузится в фоне.
 unawaited(Future.delayed(const Duration(seconds: 6), () async {
 try {
 final ok = await loadEngineFromManager();
 debugPrint('[LocalLLM] автозагрузка: ${ok? 'готово': 'модели не скачаны'}');
 } catch (e) {
 debugPrint('[LocalLLM] автозагрузка не удалась: $e');
 }
 }));
 }

 } catch (e) {
 debugPrint('Ошибка инициализации сервисов: $e');
 }
 runApp(const AikaApp());
}

class AikaApp extends StatelessWidget {
 const AikaApp({super.key});

 @override
 Widget build(BuildContext context) {
 return MaterialApp(
 title: 'Айка',
 debugShowCheckedModeBanner: false,
 theme: AikaTheme.theme,
 home: const SplashScreen(),
 // Дым-фон как на сайте HikariOS: единая атмосфера во всём
 // приложении, включая меню и все экраны настроек.
 builder: (context, child) => SmokeBackground(child: child?? const SizedBox.shrink()),
);
 }
}
