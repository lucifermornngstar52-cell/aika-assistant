import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AikaTheme.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

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
