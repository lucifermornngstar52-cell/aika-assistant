import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class WeatherData {
  final String city;
  final String country;
  final double temp;
  final double feelsLike;
  final double tempMin;
  final double tempMax;
  final String description;
  final int humidity;
  final double windSpeed;
  final int weatherId;
  final int sunrise;
  final int sunset;
  final int pressure;
  final double? visibility;

  WeatherData({
    required this.city,
    required this.country,
    required this.temp,
    required this.feelsLike,
    required this.tempMin,
    required this.tempMax,
    required this.description,
    required this.humidity,
    required this.windSpeed,
    required this.weatherId,
    required this.sunrise,
    required this.sunset,
    required this.pressure,
    this.visibility,
  });
}

class ForecastDay {
  final DateTime date;
  final double tempMin;
  final double tempMax;
  final String description;
  final int weatherId;
  final double windSpeed;
  final int humidity;

  ForecastDay({
    required this.date,
    required this.tempMin,
    required this.tempMax,
    required this.description,
    required this.weatherId,
    required this.windSpeed,
    required this.humidity,
  });
}

class WeatherService {
  static const String _owmKey  = '30b398816f9dc8ec92454b67c2172c31';
  static const String _owmBase = 'https://api.openweathermap.org/data/2.5';

  // ── GPS → город ──────────────────────────────────────────────────────────
  Future<String> _resolveCity(String city) async {
    if (city.isNotEmpty) return city;
    // 1. Попробуем GPS
    try {
      final gpsCity = await _cityByGps();
      if (gpsCity.isNotEmpty) return gpsCity;
    } catch (_) {}
    // 2. Fallback по IP
    return await _cityByIp();
  }

  Future<String> _cityByGps() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return '';

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return '';
    }
    if (permission == LocationPermission.deniedForever) return '';

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 8),
      ),
    );

    // Reverse geocode через OWM
    final url = '$_owmBase/weather?lat=${pos.latitude}&lon=${pos.longitude}'
        '&appid=$_owmKey&units=metric&lang=ru';
    final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
    if (resp.statusCode == 200) {
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      return data['name'] ?? '';
    }
    return '';
  }

  Future<String> _cityByIp() async {
    try {
      final resp = await http
          .get(Uri.parse('http://ip-api.com/json/?fields=city'))
          .timeout(const Duration(seconds: 5));
      final data = jsonDecode(resp.body);
      return data['city'] ?? 'Almaty';
    } catch (_) {
      return 'Almaty';
    }
  }

  // ── Текущая погода (WeatherData объект) ──────────────────────────────────
  Future<WeatherData?> getCurrentWeatherData({String city = ''}) async {
    try {
      final resolved = await _resolveCity(city);
      final url = '$_owmBase/weather?q=${Uri.encodeComponent(resolved)}'
          '&appid=$_owmKey&units=metric&lang=ru';
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final d = jsonDecode(utf8.decode(resp.bodyBytes));
      return WeatherData(
        city:        d['name'] ?? resolved,
        country:     d['sys']?['country'] ?? '',
        temp:        (d['main']?['temp'] as num?)?.toDouble() ?? 0,
        feelsLike:   (d['main']?['feels_like'] as num?)?.toDouble() ?? 0,
        tempMin:     (d['main']?['temp_min'] as num?)?.toDouble() ?? 0,
        tempMax:     (d['main']?['temp_max'] as num?)?.toDouble() ?? 0,
        description: d['weather']?[0]?['description'] ?? '',
        humidity:    d['main']?['humidity'] ?? 0,
        windSpeed:   (d['wind']?['speed'] as num?)?.toDouble() ?? 0,
        weatherId:   d['weather']?[0]?['id'] ?? 800,
        sunrise:     d['sys']?['sunrise'] ?? 0,
        sunset:      d['sys']?['sunset'] ?? 0,
        pressure:    d['main']?['pressure'] ?? 0,
        visibility:  (d['visibility'] as num?)?.toDouble(),
      );
    } catch (e) {
      debugPrint('[Weather] error: $e');
      return null;
    }
  }

  // ── Прогноз 5 дней (список ForecastDay) ──────────────────────────────────
  Future<List<ForecastDay>> getForecastData({String city = ''}) async {
    try {
      final resolved = await _resolveCity(city);
      final url = '$_owmBase/forecast?q=${Uri.encodeComponent(resolved)}'
          '&appid=$_owmKey&units=metric&lang=ru&cnt=40';
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final list = data['list'] as List<dynamic>;

      final Map<String, List<dynamic>> byDay = {};
      for (final item in list) {
        final dt  = DateTime.fromMillisecondsSinceEpoch((item['dt'] as int) * 1000);
        final key = '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
        byDay.putIfAbsent(key, () => []).add(item);
      }

      final result = <ForecastDay>[];
      for (final entry in byDay.entries.take(5)) {
        final items   = entry.value;
        final temps   = items.map((i) => (i['main']?['temp'] as num?)?.toDouble() ?? 0).toList();
        final mid     = items.length ~/ 2;
        final midItem = items[mid];
        result.add(ForecastDay(
          date:        DateTime.parse(entry.key),
          tempMin:     temps.reduce((a, b) => a < b ? a : b),
          tempMax:     temps.reduce((a, b) => a > b ? a : b),
          description: midItem['weather']?[0]?['description'] ?? '',
          weatherId:   midItem['weather']?[0]?['id'] ?? 800,
          windSpeed:   (midItem['wind']?['speed'] as num?)?.toDouble() ?? 0,
          humidity:    midItem['main']?['humidity'] ?? 0,
        ));
      }
      return result;
    } catch (e) {
      debugPrint('[Weather] forecast error: $e');
      return [];
    }
  }

  // ── Текстовый ответ для чата ─────────────────────────────────────────────
  Future<String> getWeather({String city = ''}) async {
    final data = await getCurrentWeatherData(city: city);
    if (data == null) return '❌ Не удалось получить погоду. Проверь интернет.';
    final emoji = weatherEmoji(data.weatherId);
    return '$emoji ${data.city}\n'
        '🌡 ${data.temp.round()}°C (ощущается ${data.feelsLike.round()}°C)\n'
        '☁️ ${_cap(data.description)}\n'
        '💧 Влажность: ${data.humidity}%\n'
        '💨 Ветер: ${data.windSpeed.toStringAsFixed(1)} м/с';
  }

  Future<String> getForecast({String city = ''}) async {
    final days = await getForecastData(city: city);
    if (days.isEmpty) return '❌ Не удалось получить прогноз.';
    final resolved = days.isNotEmpty ? '' : city;
    final buf = StringBuffer('📅 Прогноз:\n');
    final weekdays = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];
    for (final d in days) {
      final wd = weekdays[d.date.weekday % 7];
      final emoji = weatherEmoji(d.weatherId);
      buf.writeln('$emoji $wd ${d.date.day}.${d.date.month.toString().padLeft(2,'0')}: '
          '${d.tempMin.round()}…${d.tempMax.round()}°C, ${d.description}');
    }
    return buf.toString().trim();
  }

  // ── Определяем является ли запрос погодным ────────────────────────────────
  static bool isWeatherRequest(String text) {
    final t = text.toLowerCase();
    return t.contains('погод') || t.contains('weather') ||
        t.contains('температур') || t.contains('прогноз') ||
        t.contains('дождь') || t.contains('снег') || t.contains('жарк') ||
        t.contains('холодно') || t.contains('как на улице') ||
        t.contains('что с погодой') || t.contains('тепло ли');
  }

  static String weatherEmoji(int id) {
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
