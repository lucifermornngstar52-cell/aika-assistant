import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/personality_service.dart';
import 'services/wardrobe_service.dart';
import 'services/theme_switcher_service.dart';
import 'services/ai_service.dart';
import 'services/web_search_service.dart';
import 'main_overlay.dart' show overlayMain;

export 'main_overlay.dart' show overlayMain;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  AiService.setGeminiKey(prefs.getString('gemini_key') ?? '');
  AiService.setGroqKey(prefs.getString('groq_key') ?? '');
  AiService.setClaudeKey(prefs.getString('claude_key') ?? '');
  AiService.setDeepseekKey(prefs.getString('deepseek_key') ?? '');
  AiService.setPerplexityKey(prefs.getString('perplexity_key') ?? '');
  AiService.setLocalUrl(prefs.getString('local_url') ?? 'http://192.168.0.100:11434/v1/chat/completions');
  AiService.setLocalModel(prefs.getString('local_model') ?? 'llama3.2:1b');
  AiService.setPreferredModel(prefs.getString('ai_model') ?? 'auto');
  AiService.setWebSearch(prefs.getBool('ai_web_search') ?? true);
  AiService.setMaxTokens(prefs.getInt('ai_max_tokens') ?? 1024);
  WebSearchService.setBraveKey(prefs.getString('brave_key') ?? '');

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
    );
  }
}
