import 'package:flutter/material.dart';
import '../services/currency_service.dart';
import '../theme/app_theme.dart';

class CurrencyScreen extends StatefulWidget {
  const CurrencyScreen({Key? key}) : super(key: key);

  @override
  State<CurrencyScreen> createState() => _CurrencyScreenState();
}

class _CurrencyScreenState extends State<CurrencyScreen> {
  final CurrencyService _currencyService = CurrencyService();
  List<CurrencyRate> _rates = [];
  bool _isLoading = true;
  String? _error;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _loadRates();
  }

  Future<void> _loadRates() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final rates = await _currencyService.getRates();
      setState(() {
        _rates = rates;
        _isLoading = false;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AikaTheme.darkBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Курсы валют',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AikaTheme.neonBlue),
            onPressed: _loadRates,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AikaTheme.neonBlue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.currency_exchange, color: AikaTheme.neonBlue, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _lastUpdated != null
                          ? 'Обновлено: ${_lastUpdated!.hour.toString().padLeft(2, '0')}:${_lastUpdated!.minute.toString().padLeft(2, '0')}'
                          : 'Курсы к рублю (RUB)',
                      style: TextStyle(color: AikaTheme.neonBlue, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Контент
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: AikaTheme.neonBlue),
                          const SizedBox(height: 16),
                          Text(
                            'Загружаю курсы...',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ],
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                              const SizedBox(height: 12),
                              Text(
                                'Ошибка загрузки',
                                style: const TextStyle(color: Colors.white, fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                style: const TextStyle(color: Colors.white38, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AikaTheme.neonBlue.withOpacity(0.2),
                                  side: BorderSide(color: AikaTheme.neonBlue),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: _loadRates,
                                icon: const Icon(Icons.refresh, color: Colors.white),
                                label: const Text('Повторить',
                                    style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _rates.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final rate = _rates[index];
                            return _CurrencyCard(rate: rate);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyCard extends StatelessWidget {
  final CurrencyRate rate;
  const _CurrencyCard({required this.rate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Text(rate.flag, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rate.code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  rate.name,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${rate.rateToRub.toStringAsFixed(2)} ₽',
                style: TextStyle(
                  color: AikaTheme.neonBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              Text(
                '1 ${rate.code}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
