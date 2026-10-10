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
 void _copy(String text) {
 Clipboard.setData(ClipboardData(text: text));
 ScaffoldMessenger.of(context).showSnackBar(
 SnackBar(
 content: Text('Скопировано: $text'),
 duration: const Duration(milliseconds: 900)),
 );
 }

 final _controller = TextEditingController();

 // ФИКС: контроллер не освобождался
 @override
 void dispose() {
 _controller.dispose();
 super.dispose();
 }
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
 final permsDone = prefs.getBool('permissions_done')?? false;
 final next = name == null
? const OnboardingScreen()
: (permsDone? const MainScreen(): const PermissionsOnboardingScreen());
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
 _error = 'Неверный код. Проверь написание или напиши в Telegram @Unqry.';
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
 const Text('', textAlign: TextAlign.center,
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
 'Пробные дни закончились',
 textAlign: TextAlign.center,
 style: TextStyle(
 fontSize: 16,
 fontWeight: FontWeight.w700,
 color: AikaTheme.textPrimary),
),
 const SizedBox(height: 8),
 const Text(
 'Полная версия — 1 000 ₸, навсегда. Переведи на карту и отправь скриншот оплаты вместе с этим ID в Telegram @Unqry:',
 textAlign: TextAlign.center,
 style: TextStyle(
 fontSize: 13, color: AikaTheme.textSecondary),
),
 const SizedBox(height: 14),
 Row(
 children: [
 _PaymentCard(
 label: 'Kaspi Gold',
 number: '4400 4300 6272 0914',
 onCopy: () => _copy('4400430062720914'),
 ),
 const SizedBox(width: 10),
 _PaymentCard(
 label: 'Freedom Bank',
 number: '4002 8900 5058 4816',
 onCopy: () => _copy('4002890050584816'),
 ),
 ],
 ),
 const SizedBox(height: 14),
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
 onPressed: _checking? null: _tryActivate,
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
: const Text(' Активировать',
 style: TextStyle(
 fontSize: 16, fontWeight: FontWeight.w600)),
),
 if (_error!= null)...[
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

class _PaymentCard extends StatelessWidget {
 final String label;
 final String number;
 final VoidCallback onCopy;

 const _PaymentCard({required this.label, required this.number, required this.onCopy});

 @override
 Widget build(BuildContext context) {
 return Expanded(
 child: InkWell(
 onTap: onCopy,
 borderRadius: BorderRadius.circular(12),
 child: Container(
 padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
 decoration: BoxDecoration(
 color: AikaTheme.surface,
 borderRadius: BorderRadius.circular(12),
 border: Border.all(color: AikaTheme.glassWhite),
 ),
 child: Column(
 children: [
 Text(label,
 textAlign: TextAlign.center,
 style: const TextStyle(
 fontSize: 12, fontWeight: FontWeight.w700, color: AikaTheme.textPrimary)),
 const SizedBox(height: 4),
 Text(number,
 textAlign: TextAlign.center,
 style: const TextStyle(
 fontSize: 11.5, letterSpacing: 0.4, color: AikaTheme.textSecondary)),
 ],
 ),
 ),
 ),
 );
 }
}
