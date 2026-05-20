import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  static const String _apiKey = String.fromEnvironment(
    'OPENWEATHER_API_KEY',
    defaultValue: '30b398816f9dc8ec92454b67c2172c31',
  );
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';

  /// Погода по городу (или текущая по IP если city пустой)
  Future<String> getWeather({String city = ''}) async {
    try {
      final String url;
      if (city.isNotEmpty) {
        url = '$_baseUrl/weather?q=${Uri.encodeComponent(city)}&appid=$_apiKey&units=metric&lang=ru';
      } else {
        // Определяем город по IP через ip-api.com (бесплатно, без ключа)
        final ipResp = await http
            .get(Uri.parse('http://ip-api.com/json/?fields=city'))
            .timeout(const Duration(seconds: 5));
        final ipData = jsonDecode(ipResp.body);
        final detectedCity = ipData['city'] ?? 'Moscow';
        url = '$_baseUrl/weather?q=${Uri.encodeComponent(detectedCity)}&appid=$_apiKey&units=metric&lang=ru';
      }

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return 'Не удалось получить погоду (${response.statusCode})';
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return _formatWeather(data);
    } catch (e) {
      return 'Ошибка получения погоды: $e';
    }
  }

  /// Прогноз на 5 дней (каждые 3 часа → берём по 1 в день)
  Future<String> getForecast({String city = ''}) async {
    try {
      final String resolvedCity;
      if (city.isNotEmpty) {
        resolvedCity = city;
      } else {
        final ipResp = await http
            .get(Uri.parse('http://ip-api.com/json/?fields=city'))
            .timeout(const Duration(seconds: 5));
        resolvedCity = jsonDecode(ipResp.body)['city'] ?? 'Moscow';
      }

      final url =
          '$_baseUrl/forecast?q=${Uri.encodeComponent(resolvedCity)}&appid=$_apiKey&units=metric&lang=ru&cnt=40';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return 'Не удалось получить прогноз (${response.statusCode})';
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return _formatForecast(data, resolvedCity);
    } catch (e) {
      return 'Ошибка получения прогноза: $e';
    }
  }

  String _formatWeather(Map<String, dynamic> data) {
    final city = data['name'] ?? '';
    final country = data['sys']?['country'] ?? '';
    final temp = (data['main']?['temp'] as num?)?.round() ?? 0;
    final feels = (data['main']?['feels_like'] as num?)?.round() ?? 0;
    final desc = data['weather']?[0]?['description'] ?? '';
    final humidity = data['main']?['humidity'] ?? 0;
    final wind = (data['wind']?['speed'] as num?)?.toStringAsFixed(1) ?? '0';
    final emoji = _weatherEmoji(data['weather']?[0]?['id'] ?? 0);

    return '$emoji $city, $country\n'
        '🌡 $temp°C (ощущается $feels°C)\n'
        '☁️ ${desc[0].toUpperCase()}${desc.substring(1)}\n'
        '💧 Влажность: $humidity%\n'
        '💨 Ветер: $wind м/с';
  }

  String _formatForecast(Map<String, dynamic> data, String city) {
    final list = data['list'] as List<dynamic>;
    final buf = StringBuffer('📅 Прогноз для $city:\n');

    // Берём одну запись в день (по ~12:00)
    final Map<String, dynamic> byDay = {};
    for (final item in list) {
      final dt = DateTime.fromMillisecondsSinceEpoch((item['dt'] as int) * 1000);
      final dateKey = '${dt.day}.${dt.month.toString().padLeft(2, '0')}';
      if (!byDay.containsKey(dateKey) || dt.hour >= 11 && dt.hour <= 14) {
        byDay[dateKey] = item;
      }
    }

    final days = byDay.entries.take(5).toList();
    final weekdays = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];

    for (final entry in days) {
      final item = entry.value;
      final dt = DateTime.fromMillisecondsSinceEpoch((item['dt'] as int) * 1000);
      final temp = (item['main']?['temp'] as num?)?.round() ?? 0;
      final desc = item['weather']?[0]?['description'] ?? '';
      final emoji = _weatherEmoji(item['weather']?[0]?['id'] ?? 0);
      final wd = weekdays[dt.weekday % 7];
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
    if (id == 800) return '☀️';
    if (id == 801 || id == 802) return '⛅';
    if (id > 802) return '☁️';
    return '🌤';
  }
}
