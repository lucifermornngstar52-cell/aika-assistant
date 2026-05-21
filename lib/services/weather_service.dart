import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  // OpenWeatherMap — бесплатный ключ
  static const String _owmKey = '30b398816f9dc8ec92454b67c2172c31';
  static const String _owmBase = 'https://api.openweathermap.org/data/2.5';

  /// Погода по городу (или авто по IP)
  Future<String> getWeather({String city = ''}) async {
    try {
      final resolvedCity = city.isNotEmpty ? city : await _cityByIp();
      final url = '$_owmBase/weather?q=${Uri.encodeComponent(resolvedCity)}'
          '&appid=$_owmKey&units=metric&lang=ru';

      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return 'Не удалось получить погоду';
      return _formatWeather(jsonDecode(utf8.decode(resp.bodyBytes)));
    } catch (e) {
      return 'Ошибка погоды: $e';
    }
  }

  /// Прогноз на 5 дней
  Future<String> getForecast({String city = ''}) async {
    try {
      final resolvedCity = city.isNotEmpty ? city : await _cityByIp();
      final url = '$_owmBase/forecast?q=${Uri.encodeComponent(resolvedCity)}'
          '&appid=$_owmKey&units=metric&lang=ru&cnt=40';

      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return 'Не удалось получить прогноз';
      return _formatForecast(jsonDecode(utf8.decode(resp.bodyBytes)), resolvedCity);
    } catch (e) {
      return 'Ошибка прогноза: $e';
    }
  }

  /// Определяем город по IP
  Future<String> _cityByIp() async {
    try {
      final resp = await http
          .get(Uri.parse('http://ip-api.com/json/?fields=city,regionName,country'))
          .timeout(const Duration(seconds: 5));
      final data = jsonDecode(resp.body);
      return data['city'] ?? 'Almaty';
    } catch (_) {
      return 'Almaty';
    }
  }

  String _formatWeather(Map<String, dynamic> data) {
    final city    = data['name'] ?? '';
    final temp    = (data['main']?['temp'] as num?)?.round() ?? 0;
    final feels   = (data['main']?['feels_like'] as num?)?.round() ?? 0;
    final desc    = data['weather']?[0]?['description'] ?? '';
    final humidity= data['main']?['humidity'] ?? 0;
    final wind    = (data['wind']?['speed'] as num?)?.toStringAsFixed(1) ?? '0';
    final emoji   = _weatherEmoji(data['weather']?[0]?['id'] ?? 0);

    return '$emoji $city\n'
        '🌡 $temp°C (ощущается $feels°C)\n'
        '☁️ ${_cap(desc)}\n'
        '💧 Влажность: $humidity%\n'
        '💨 Ветер: $wind м/с';
  }

  String _formatForecast(Map<String, dynamic> data, String city) {
    final list = data['list'] as List<dynamic>;
    final buf  = StringBuffer('📅 Прогноз для $city:\n');
    final Map<String, dynamic> byDay = {};

    for (final item in list) {
      final dt  = DateTime.fromMillisecondsSinceEpoch((item['dt'] as int) * 1000);
      final key = '${dt.day}.${dt.month.toString().padLeft(2, '0')}';
      if (!byDay.containsKey(key) || (dt.hour >= 11 && dt.hour <= 14)) {
        byDay[key] = item;
      }
    }

    final weekdays = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];
    for (final entry in byDay.entries.take(5)) {
      final item  = entry.value;
      final dt    = DateTime.fromMillisecondsSinceEpoch((item['dt'] as int) * 1000);
      final temp  = (item['main']?['temp'] as num?)?.round() ?? 0;
      final desc  = item['weather']?[0]?['description'] ?? '';
      final emoji = _weatherEmoji(item['weather']?[0]?['id'] ?? 0);
      final wd    = weekdays[dt.weekday % 7];
      buf.writeln('$emoji ${entry.key} ($wd): $temp°C, $desc');
    }

    return buf.toString().trim();
  }

  String _weatherEmoji(int id) {
    if (id >= 200 && id < 300) return '⛈';
    if (id >= 300 && id < 400) return '🌦';
    if (id >= 500 && id < 600) return '🌧';
    if (id >= 600 && id < 700) return '❄️';
    if (id >= 700 && id < 800) return '🌫';
    if (id == 800)             return '☀️';
    if (id <= 802)             return '⛅';
    return '☁️';
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
