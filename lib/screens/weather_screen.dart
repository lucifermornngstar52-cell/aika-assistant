import 'package:flutter/material.dart';
import '../services/weather_service.dart';
import '../theme/app_theme.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});
  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> with SingleTickerProviderStateMixin {
  final _service = WeatherService();
  final _cityController = TextEditingController();

  WeatherData? _current;
  List<ForecastDay> _forecast = [];
  bool _loading = true;
  String? _error;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _load({String city = ''}) async {
    setState(() { _loading = true; _error = null; });
    _animCtrl.reset();
    try {
      final cur  = await _service.getCurrentWeatherData(city: city);
      final fore = await _service.getForecastData(city: city);
      setState(() {
        _current  = cur;
        _forecast = fore;
        _loading  = false;
        if (cur == null) _error = 'Не удалось получить погоду';
      });
      if (cur != null) _animCtrl.forward();
    } catch (e) {
      setState(() { _loading = false; _error = 'Ошибка: $e'; });
    }
  }

  Color _bgColor(int id) {
    if (id >= 200 && id < 300) return const Color(0xFF1a1a3e);
    if (id >= 300 && id < 600) return const Color(0xFF1e2d3d);
    if (id >= 600 && id < 700) return const Color(0xFF2d3561);
    if (id >= 700 && id < 800) return const Color(0xFF2a2a3d);
    if (id == 800)             return const Color(0xFF0d1b3e);
    return const Color(0xFF1a2640);
  }

  String _formatTime(int unix) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    return '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    final id = _current?.weatherId ?? 800;
    final bg = _bgColor(id);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Погода', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w300, letterSpacing: 1)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () => _load(city: _cityController.text.trim()),
          ),
        ],
      ),
      body: Column(
        children: [
          // Поиск города
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _cityController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Введи город или оставь пустым (GPS)',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onSubmitted: (v) => _load(city: v.trim()),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _load(city: _cityController.text.trim()),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AikaTheme.neonBlue.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.5)),
                  ),
                  child: const Icon(Icons.my_location, color: AikaTheme.neonBlue, size: 20),
                ),
              ),
            ]),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AikaTheme.neonBlue))
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                    : FadeTransition(
                        opacity: _fadeAnim,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildCurrentCard(),
                              const SizedBox(height: 16),
                              _buildDetailsRow(),
                              const SizedBox(height: 16),
                              _buildForecastCard(),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentCard() {
    final w = _current!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(children: [
        // Город
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.location_on, color: AikaTheme.neonBlue, size: 16),
          const SizedBox(width: 4),
          Text('${w.city}, ${w.country}',
              style: const TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 20),
        // Большая температура
        Text(WeatherService.weatherEmoji(w.weatherId),
            style: const TextStyle(fontSize: 72)),
        const SizedBox(height: 8),
        Text('${w.temp.round()}°C',
            style: const TextStyle(color: Colors.white, fontSize: 64,
                fontWeight: FontWeight.w200, letterSpacing: -2)),
        Text(_cap(w.description),
            style: const TextStyle(color: Colors.white60, fontSize: 16)),
        const SizedBox(height: 8),
        Text('Ощущается ${w.feelsLike.round()}°C  •  ${w.tempMin.round()}°/${w.tempMax.round()}°',
            style: const TextStyle(color: Colors.white38, fontSize: 13)),
      ]),
    );
  }

  Widget _buildDetailsRow() {
    final w = _current!;
    final items = [
      ('💧', 'Влажность', '${w.humidity}%'),
      ('💨', 'Ветер', '${w.windSpeed.toStringAsFixed(1)} м/с'),
      ('🔵', 'Давление', '${w.pressure} гПа'),
      ('🌅', 'Восход', _formatTime(w.sunrise)),
      ('🌇', 'Закат', _formatTime(w.sunset)),
      if (w.visibility != null)
        ('👁', 'Видимость', '${(w.visibility! / 1000).toStringAsFixed(1)} км'),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((item) => _detailChip(item.$1, item.$2, item.$3)).toList(),
    );
  }

  Widget _detailChip(String emoji, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ]),
    );
  }

  Widget _buildForecastCard() {
    if (_forecast.isEmpty) return const SizedBox();
    final weekdays = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Прогноз на 5 дней',
            style: TextStyle(color: Colors.white60, fontSize: 13, letterSpacing: 0.5)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            children: _forecast.asMap().entries.map((entry) {
              final i = entry.key;
              final d = entry.value;
              final wd = weekdays[d.date.weekday % 7];
              final dayStr = '${d.date.day}.${d.date.month.toString().padLeft(2,'0')}';
              final isLast = i == _forecast.length - 1;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(children: [
                      SizedBox(
                        width: 50,
                        child: Text('$wd $dayStr',
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ),
                      const SizedBox(width: 12),
                      Text(WeatherService.weatherEmoji(d.weatherId),
                          style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(_cap(d.description),
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text('${d.tempMin.round()}°',
                          style: const TextStyle(color: Colors.white38, fontSize: 14)),
                      const SizedBox(width: 4),
                      const Text('—', style: TextStyle(color: Colors.white24, fontSize: 12)),
                      const SizedBox(width: 4),
                      Text('${d.tempMax.round()}°',
                          style: const TextStyle(color: Colors.white, fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  if (!isLast) Divider(height: 1, color: Colors.white.withOpacity(0.05)),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
