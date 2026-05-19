import 'dart:convert';
import 'package:http/http.dart' as http;

class CurrencyRate {
  final String code;
  final String name;
  final double rateToRub;
  final String flag;

  CurrencyRate({
    required this.code,
    required this.name,
    required this.rateToRub,
    required this.flag,
  });
}

class CurrencyService {
  static const String _apiKey = '31a5cdd36c14660779c42f77';
  static const String _baseUrl = 'https://free.currconv.com/api/v7';

  // Валюты которые отслеживаем
  static const List<Map<String, String>> _currencies = [
    {'code': 'USD', 'name': 'Доллар США', 'flag': '🇺🇸'},
    {'code': 'EUR', 'name': 'Евро', 'flag': '🇪🇺'},
    {'code': 'GBP', 'name': 'Фунт стерлингов', 'flag': '🇬🇧'},
    {'code': 'CNY', 'name': 'Юань', 'flag': '🇨🇳'},
    {'code': 'KZT', 'name': 'Тенге', 'flag': '🇰🇿'},
  ];

  Future<List<CurrencyRate>> getRates() async {
    try {
      // Формируем запрос для всех пар к RUB
      final pairs = _currencies
          .where((c) => c['code'] != 'RUB')
          .map((c) => '${c['code']}_RUB')
          .join(',');

      final url = Uri.parse('$_baseUrl/convert?q=$pairs&compact=ultra&apiKey=$_apiKey');
      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      return _currencies.where((c) => c['code'] != 'RUB').map((currency) {
        final key = '${currency['code']}_RUB';
        final rate = (data[key] as num?)?.toDouble() ?? 0.0;
        return CurrencyRate(
          code: currency['code']!,
          name: currency['name']!,
          rateToRub: rate,
          flag: currency['flag']!,
        );
      }).toList();
    } catch (e) {
      throw Exception('Ошибка получения курсов: $e');
    }
  }

  Future<String> getRatesText() async {
    final rates = await getRates();
    final sb = StringBuffer('Актуальные курсы валют:\n\n');
    for (final r in rates) {
      sb.writeln('${r.flag} ${r.code} (${r.name}): ${r.rateToRub.toStringAsFixed(2)} ₽');
    }
    return sb.toString().trim();
  }

  Future<String> getSingleRate(String code) async {
    final rates = await getRates();
    final rate = rates.firstWhere(
      (r) => r.code == code.toUpperCase(),
      orElse: () => CurrencyRate(code: code, name: code, rateToRub: 0, flag: ''),
    );
    if (rate.rateToRub == 0) return 'Курс $code не найден';
    return '${rate.flag} 1 ${rate.code} = ${rate.rateToRub.toStringAsFixed(2)} ₽';
  }
}
