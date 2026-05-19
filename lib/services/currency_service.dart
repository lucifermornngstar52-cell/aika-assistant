import 'dart:convert';
import 'package:http/http.dart' as http;

class CurrencyRate {
  final String code;
  final String name;
  final double rateToRub;
  final String flag;
  final double? change24h; // изменение за 24ч в %

  CurrencyRate({
    required this.code,
    required this.name,
    required this.rateToRub,
    required this.flag,
    this.change24h,
  });
}

class CurrencyService {
  // Бесплатный API — не требует ключа, лимит 1500 запросов/месяц
  static const String _baseUrl = 'https://open.er-api.com/v6/latest/RUB';

  static const List<Map<String, String>> _currencies = [
    {'code': 'USD', 'name': 'Доллар США',       'flag': '🇺🇸'},
    {'code': 'EUR', 'name': 'Евро',              'flag': '🇪🇺'},
    {'code': 'GBP', 'name': 'Фунт стерлингов',  'flag': '🇬🇧'},
    {'code': 'CNY', 'name': 'Юань',              'flag': '🇨🇳'},
    {'code': 'KZT', 'name': 'Тенге',             'flag': '🇰🇿'},
    {'code': 'BTC', 'name': 'Биткоин',           'flag': '₿'},
  ];

  Future<List<CurrencyRate>> getRates() async {
    try {
      final response = await http.get(Uri.parse(_baseUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (data['result'] != 'success') {
        throw Exception('API error: ${data['error-type'] ?? 'unknown'}');
      }

      // rates здесь — сколько единиц валюты за 1 RUB
      // нам нужно обратное: сколько RUB за 1 единицу валюты
      final rates = data['rates'] as Map<String, dynamic>;

      return _currencies.map((currency) {
        final code = currency['code']!;
        final perRub = (rates[code] as num?)?.toDouble() ?? 0.0;
        final rateToRub = perRub > 0 ? 1.0 / perRub : 0.0;

        return CurrencyRate(
          code: code,
          name: currency['name']!,
          rateToRub: rateToRub,
          flag: currency['flag']!,
        );
      }).toList();
    } catch (e) {
      throw Exception('Ошибка: $e');
    }
  }

  Future<String> getRatesText() async {
    final rates = await getRates();
    final sb = StringBuffer('Актуальные курсы к рублю:\n\n');
    for (final r in rates) {
      final val = r.code == 'BTC'
          ? r.rateToRub.toStringAsFixed(0)
          : r.rateToRub.toStringAsFixed(2);
      sb.writeln('${r.flag} 1 ${r.code} = $val ₽');
    }
    return sb.toString().trim();
  }

  Future<String> getSingleRate(String code) async {
    try {
      final rates = await getRates();
      final rate = rates.firstWhere(
        (r) => r.code == code.toUpperCase(),
        orElse: () => CurrencyRate(code: code, name: code, rateToRub: 0, flag: ''),
      );
      if (rate.rateToRub == 0) return 'Курс $code не найден';
      final val = rate.code == 'BTC'
          ? rate.rateToRub.toStringAsFixed(0)
          : rate.rateToRub.toStringAsFixed(2);
      return '${rate.flag} 1 ${rate.code} = $val ₽';
    } catch (e) {
      return 'Не удалось получить курс: $e';
    }
  }
}
