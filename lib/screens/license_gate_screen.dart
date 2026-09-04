import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/license_service.dart';
import '../theme/app_theme.dart';
import 'onboarding_screen.dart';
import 'main_screen.dart';
import 'permissions_onboarding_screen.dart';

/// Экран активации Aika. Показывается при первом запуске,
/// пока не введён код, привязанный к этому устройству.
class LicenseGateScreen extends StatefulWidget {
  const LicenseGateScreen({super.key});

  @override
  State<LicenseGateScreen> createState() => _LicenseGateScreenState();
}

class _LicenseGateScreenState extends State<LicenseGateScreen> {
  final _controller = TextEditingController();
  String _deviceHash = '...';
  String? _error;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    LicenseService.getDeviceHash().then((h) {
      if (mounted) setState(() => _deviceHash = h);
    });
  }

  Future<void> _tryActivate() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok = await LicenseService.activate(_controller.text);
    if (!mounted) return;
    if (ok) {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('user_name');
      if (!mounted) return;
      final permsDone = prefs.getBool('permissions_done') ?? false;
      final next = name == null
          ? const OnboardingScreen()
          : (permsDone ? const MainScreen() : const PermissionsOnboardingScreen());
      setState(() => _checking = false);
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => next,
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    } else {
      setState(() {
        _checking = false;
        _error = 'Неверный код. Проверь написание или обратись к разработчику.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('🌸', textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                const Text(
                  'Aika Assistant',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AikaTheme.textPrimary),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AikaTheme.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AikaTheme.glassWhite),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Приложение не активировано.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AikaTheme.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Отправь этот ID устройства вместе со скриншотом оплаты разработчику в Telegram @Unqry и получи код активации:',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: AikaTheme.textSecondary),
                      ),
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: _deviceHash));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('ID скопирован'),
                                duration: Duration(seconds: 1)),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          decoration: BoxDecoration(
                            color: AikaTheme.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _deviceHash,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 20,
                                letterSpacing: 3,
                                fontWeight: FontWeight.w700,
                                color: AikaTheme.textPrimary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text('нажми, чтобы скопировать',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11, color: AikaTheme.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _controller,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18,
                      letterSpacing: 2,
                      color: AikaTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'AK-XXXXXX',
                    hintStyle: const TextStyle(
                        color: AikaTheme.textSecondary, letterSpacing: 2),
                    filled: true,
                    fillColor: AikaTheme.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: _checking ? null : _tryActivate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AikaTheme.accent,
                    foregroundColor: AikaTheme.background,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _checking
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('🔓 Активировать',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.redAccent)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
