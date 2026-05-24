import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/license_service.dart';
import '../theme/app_theme.dart';
import 'main_screen.dart';

class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;
  String _message = '';
  String _step = 'email'; // email, payment, waiting
  String? _email;
  String _selectedPlan = 'purchase';
  String _selectedBank = 'kaspi';
  Map<String, dynamic>? _paymentInfo;

  static const _kaspiCard = '4400 4300 6272 0914';
  static const _freedomCard = '4002 8900 5058 4816';

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _tryAutoLogin() async {
    final savedEmail = await LicenseService.getSavedEmail();
    if (savedEmail != null) {
      setState(() { _loading = true; _message = 'Проверка лицензии...'; });
      final status = await LicenseService.checkLicenseByEmail(savedEmail);
      if (!mounted) return;
      if (status.valid) {
        _goToMain();
        return;
      }
      setState(() {
        _loading = false;
        _email = savedEmail;
        _emailController.text = savedEmail;
        _step = status.reason == 'pending' ? 'waiting' : 'payment';
        _message = _statusMessage(status.reason);
      });
    }
  }

  String _statusMessage(String reason) {
    switch (reason) {
      case 'pending': return 'Заявка ожидает подтверждения оплаты';
      case 'rejected': return 'Заявка отклонена. Свяжитесь с поддержкой';
      case 'expired': return 'Подписка истекла. Продлите доступ';
      case 'not_found': return 'Введите email для доступа к Айке';
      default: return 'Оформите доступ для продолжения';
    }
  }

  Future<void> _continueWithEmail() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      setState(() { _message = 'Введите корректный email'; });
      return;
    }
    setState(() { _loading = true; _message = 'Проверяем...'; });

    await LicenseService.saveEmail(email);
    await LicenseService.register(email: email, fullName: email.split('@')[0]);

    final status = await LicenseService.checkLicenseByEmail(email);
    if (!mounted) return;

    if (status.valid) {
      _goToMain();
      return;
    }

    setState(() {
      _loading = false;
      _email = email;
      _step = status.reason == 'pending' ? 'waiting' : 'payment';
      _message = _statusMessage(status.reason);
    });
  }

  Future<void> _submitPayment() async {
    if (_email == null) return;
    setState(() { _loading = true; _message = 'Отправка заявки...'; });

    final result = await LicenseService.submitPayment(
      email: _email!,
      fullName: _email!.split('@')[0],
      plan: _selectedPlan,
      paymentMethod: _selectedBank,
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      _step = result['success'] == true ? 'waiting' : 'payment';
      _message = result['success'] == true
          ? 'Заявка отправлена! Ожидайте подтверждения.'
          : 'Ошибка: ${result['error'] ?? 'попробуйте ещё раз'}';
    });
  }

  Future<void> _checkAgain() async {
    if (_email == null) return;
    setState(() { _loading = true; _message = 'Проверяем статус...'; });
    final status = await LicenseService.checkLicenseByEmail(_email!);
    if (!mounted) return;
    if (status.valid) { _goToMain(); return; }
    setState(() {
      _loading = false;
      _message = status.reason == 'pending'
          ? 'Пока не подтверждено. Ожидайте...'
          : _statusMessage(status.reason);
    });
  }

  void _goToMain() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  String get _cardNumber => _selectedBank == 'kaspi' ? _kaspiCard : _freedomCard;
  int get _amount => _selectedPlan == 'purchase' ? 3000 : 2800;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      body: SafeArea(
        child: _loading ? _buildLoading() : _buildContent(),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AikaTheme.neonBlue),
          const SizedBox(height: 20),
          Text(_message, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AikaTheme.neonBlue.withOpacity(0.4), blurRadius: 30, spreadRadius: 10)],
            ),
            child: ClipOval(
              child: Image.asset('assets/images/aika_avatar.png', fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AikaTheme.card),
                  child: const Icon(Icons.person, color: AikaTheme.neonBlue, size: 50),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Айка', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_message.isNotEmpty)
            Text(_message, textAlign: TextAlign.center,
              style: TextStyle(
                color: _message.startsWith('Ошибка') ? Colors.redAccent : Colors.white60,
                fontSize: 13,
              )),
          const SizedBox(height: 32),
          if (_step == 'email') _buildEmailStep(),
          if (_step == 'payment') _buildPaymentStep(),
          if (_step == 'waiting') _buildWaitingStep(),
        ],
      ),
    );
  }

  Widget _buildEmailStep() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: AikaTheme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.3)),
          ),
          child: TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Введите ваш email',
              hintStyle: TextStyle(color: Colors.white38),
              prefixIcon: Icon(Icons.email_outlined, color: AikaTheme.neonBlue),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _continueWithEmail,
            style: ElevatedButton.styleFrom(
              backgroundColor: AikaTheme.neonBlue,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Продолжить →', style: TextStyle(fontSize: 16, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Покупка: 3000 ₸  ·  Подписка: 2800 ₸/мес',
          style: TextStyle(color: Colors.white38, fontSize: 12)),
      ],
    );
  }

  Widget _buildPaymentStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Выберите тариф', style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 8),
        Row(children: [
          _chip(_selectedPlan == 'purchase', '🛒 Покупка — 3000 ₸', () => setState(() => _selectedPlan = 'purchase')),
          const SizedBox(width: 8),
          _chip(_selectedPlan == 'subscription', '🔄 Подписка — 2800 ₸', () => setState(() => _selectedPlan = 'subscription')),
        ]),
        const SizedBox(height: 16),
        const Text('Способ оплаты', style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 8),
        Row(children: [
          _chip(_selectedBank == 'kaspi', '🟡 Kaspi', () => setState(() => _selectedBank = 'kaspi')),
          const SizedBox(width: 8),
          _chip(_selectedBank == 'freedom', '🟢 Freedom', () => setState(() => _selectedBank = 'freedom')),
        ]),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AikaTheme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Переведите $_amount ₸ на карту:',
                style: const TextStyle(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text(_cardNumber,
                    style: const TextStyle(color: Colors.white, fontSize: 20,
                      fontWeight: FontWeight.bold, letterSpacing: 2))),
                  IconButton(
                    icon: const Icon(Icons.copy, color: AikaTheme.neonBlue, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _cardNumber.replaceAll(' ', '')));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Номер скопирован ✓'), duration: Duration(seconds: 1)));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text('После перевода нажмите кнопку ниже — я проверю и активирую доступ.',
          style: TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitPayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: AikaTheme.neonBlue,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('✅ Я оплатил — отправить заявку', style: TextStyle(fontSize: 15, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingStep() {
    return Column(
      children: [
        const Icon(Icons.hourglass_top_rounded, color: AikaTheme.neonBlue, size: 60),
        const SizedBox(height: 16),
        const Text('Заявка на рассмотрении', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Как только оплата будет подтверждена,\nприложение разблокируется автоматически.',
          textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 14)),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _checkAgain,
            style: ElevatedButton.styleFrom(
              backgroundColor: AikaTheme.neonBlue,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('🔄 Проверить статус', style: TextStyle(fontSize: 15, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() { _step = 'email'; _message = ''; }),
          child: const Text('Использовать другой email', style: TextStyle(color: Colors.white38, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _chip(bool selected, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AikaTheme.neonBlue : AikaTheme.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AikaTheme.neonBlue : Colors.white12),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white60, fontSize: 12)),
      ),
    );
  }
}
