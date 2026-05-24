import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/license_service.dart';
import '../theme/app_theme.dart';
import 'main_screen.dart';

class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  bool _loading = false;
  String _message = '';
  String _step = 'signin'; // signin, pending, payment, waiting
  String? _googleId;
  String? _email;
  String? _name;
  String _selectedPlan = 'purchase';
  String _selectedBank = 'kaspi';
  Map<String, dynamic>? _paymentInfo;

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    final savedId = await LicenseService.getSavedGoogleId();
    if (savedId != null) {
      setState(() { _loading = true; _message = 'Проверка лицензии...'; });
      final status = await LicenseService.checkLicense(savedId);
      if (!mounted) return;
      if (status.valid) {
        _goToMain();
      } else {
        setState(() {
          _loading = false;
          _googleId = savedId;
          _email = status.email;
          _step = status.reason == 'pending' ? 'pending' : 'payment';
          _message = _statusMessage(status.reason);
        });
      }
    }
  }

  String _statusMessage(String reason) {
    switch (reason) {
      case 'pending': return 'Ваша заявка ожидает подтверждения оплаты';
      case 'rejected': return 'Заявка отклонена. Свяжитесь с поддержкой';
      case 'expired': return 'Подписка истекла. Продлите доступ';
      case 'not_found': return 'Аккаунт не найден. Оформите доступ';
      case 'offline_expired': return 'Нет подключения. Проверьте интернет';
      default: return 'Требуется оплата для доступа к Айке';
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _message = 'Вход через Google...'; });
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        setState(() { _loading = false; _message = ''; });
        return;
      }

      await LicenseService.saveGoogleAccount(
        googleId: account.id,
        email: account.email,
        name: account.displayName ?? account.email,
      );

      setState(() { _message = 'Проверка лицензии...'; });
      
      // Регистрируем если нет
      await LicenseService.register(
        googleId: account.id,
        email: account.email,
        fullName: account.displayName ?? account.email,
      );

      final status = await LicenseService.checkLicense(account.id);

      if (!mounted) return;

      if (status.valid) {
        _goToMain();
        return;
      }

      // Загружаем реквизиты
      _paymentInfo = await LicenseService.getPaymentInfo(_selectedPlan);

      setState(() {
        _loading = false;
        _googleId = account.id;
        _email = account.email;
        _name = account.displayName;
        _step = status.reason == 'pending' ? 'pending' : 'payment';
        _message = _statusMessage(status.reason);
      });
    } catch (e) {
      setState(() { _loading = false; _message = 'Ошибка: ${e.toString()}'; });
    }
  }

  Future<void> _loadPaymentInfo() async {
    _paymentInfo = await LicenseService.getPaymentInfo(_selectedPlan);
    setState(() { _step = 'payment'; });
  }

  Future<void> _submitPayment() async {
    if (_googleId == null || _email == null) return;
    setState(() { _loading = true; _message = 'Отправка заявки...'; });

    final result = await LicenseService.submitPayment(
      googleId: _googleId!,
      email: _email!,
      fullName: _name ?? _email!,
      plan: _selectedPlan,
      paymentMethod: _selectedBank,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _loading = false;
        _step = 'waiting';
        _message = 'Заявка отправлена! Ожидайте подтверждения.';
      });
    } else {
      setState(() {
        _loading = false;
        _message = 'Ошибка отправки. Попробуйте ещё раз.';
      });
    }
  }

  Future<void> _checkAgain() async {
    if (_googleId == null) return;
    setState(() { _loading = true; _message = 'Проверяем статус...'; });
    final status = await LicenseService.checkLicense(_googleId!);
    if (!mounted) return;
    if (status.valid) {
      _goToMain();
    } else {
      setState(() {
        _loading = false;
        _step = status.reason == 'pending' ? 'pending' : 'waiting';
        _message = status.reason == 'pending'
            ? 'Ещё не подтверждено. Ждём оплату...'
            : _statusMessage(status.reason);
      });
    }
  }

  void _goToMain() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  String get _cardNumber {
    final info = _paymentInfo;
    if (info == null) return '';
    return info[_selectedBank]?['card'] ?? '';
  }

  int get _amount {
    final info = _paymentInfo;
    if (info == null) return _selectedPlan == 'purchase' ? 3000 : 2800;
    return info[_selectedBank]?['amount'] ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      body: SafeArea(
        child: _loading
            ? _buildLoading()
            : _buildContent(),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          // Аватар Айки
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
          Text(_message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 14)),
          const SizedBox(height: 40),

          if (_step == 'signin') _buildSignIn(),
          if (_step == 'payment') _buildPayment(),
          if (_step == 'pending' || _step == 'waiting') _buildWaiting(),
        ],
      ),
    );
  }

  Widget _buildSignIn() {
    return Column(
      children: [
        const Text('Войдите через Google\nдля доступа к приложению',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 16)),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _signInWithGoogle,
            icon: const Icon(Icons.login, color: Colors.white),
            label: const Text('Войти через Google', style: TextStyle(fontSize: 16, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AikaTheme.neonBlue,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Покупка: 3000 ₸ · Подписка: 2800 ₸/мес',
          style: TextStyle(color: Colors.white38, fontSize: 12)),
      ],
    );
  }

  Widget _buildPayment() {
    final card = _cardNumber;
    final amt = _amount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Выберите тариф', style: TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 8),
        Row(children: [
          _planChip('purchase', '🛒 Покупка — 3000 ₸'),
          const SizedBox(width: 8),
          _planChip('subscription', '🔄 Подписка — 2800 ₸'),
        ]),
        const SizedBox(height: 20),
        const Text('Способ оплаты', style: TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 8),
        Row(children: [
          _bankChip('kaspi', '🟡 Kaspi'),
          const SizedBox(width: 8),
          _bankChip('freedom', '🟢 Freedom'),
        ]),
        const SizedBox(height: 24),
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
              Text('Переведите $amt ₸ на карту:', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text(card, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1))),
                  IconButton(
                    icon: const Icon(Icons.copy, color: AikaTheme.neonBlue, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: card.replaceAll(' ', '')));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Номер скопирован'), duration: Duration(seconds: 1)));
                    },
                  ),
                ],
              ),
              Text('Получатель: ${_selectedBank == 'kaspi' ? 'Kaspi' : 'Freedom Bank'}',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text('После оплаты нажмите «Отправить заявку» — я проверю и активирую доступ.',
          style: TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 24),
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

  Widget _buildWaiting() {
    return Column(
      children: [
        const Icon(Icons.hourglass_top, color: AikaTheme.neonBlue, size: 60),
        const SizedBox(height: 16),
        const Text('Заявка отправлена!', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
      ],
    );
  }

  Widget _planChip(String plan, String label) {
    final selected = _selectedPlan == plan;
    return GestureDetector(
      onTap: () async {
        setState(() { _selectedPlan = plan; });
        _paymentInfo = await LicenseService.getPaymentInfo(plan);
        setState(() {});
      },
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

  Widget _bankChip(String bank, String label) {
    final selected = _selectedBank == bank;
    return GestureDetector(
      onTap: () => setState(() => _selectedBank = bank),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AikaTheme.neonBlue : AikaTheme.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AikaTheme.neonBlue : Colors.white12),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white60, fontSize: 13)),
      ),
    );
  }
}
