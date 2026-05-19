import 'dart:math';
import 'package:flutter/material.dart';
import '../services/currency_service.dart';
import '../theme/app_theme.dart';

class CurrencyScreen extends StatefulWidget {
  const CurrencyScreen({Key? key}) : super(key: key);
  @override
  State<CurrencyScreen> createState() => _CurrencyScreenState();
}

class _CurrencyScreenState extends State<CurrencyScreen> {
  final CurrencyService _service = CurrencyService();
  List<CurrencyRate> _rates = [];
  bool _isLoading = true;
  String? _error;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final rates = await _service.getRates();
      setState(() { _rates = rates; _isLoading = false; _lastUpdated = DateTime.now(); });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: AikaTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Курсы валют',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AikaTheme.neonBlue),
            onPressed: _load,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            // Статус бар
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AikaTheme.neonBlue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.currency_exchange, color: AikaTheme.neonBlue, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    _lastUpdated != null
                        ? 'Обновлено: ${_lastUpdated!.hour.toString().padLeft(2,'0')}:${_lastUpdated!.minute.toString().padLeft(2,'0')}'
                        : 'Курсы к рублю (RUB)',
                    style: TextStyle(color: AikaTheme.neonBlue, fontSize: 13),
                  ),
                  const Spacer(),
                  Text('open.er-api.com',
                      style: const TextStyle(color: Colors.white24, fontSize: 10)),
                ],
              ),
            ),
            // Список
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: AikaTheme.neonBlue))
                  : _error != null
                      ? _ErrorView(error: _error!, onRetry: _load)
                      : ListView.separated(
                          itemCount: _rates.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _CurrencyCard(rate: _rates[i]),
                        ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ── Карточка ────────────────────────────────────────────────────────────────
class _CurrencyCard extends StatelessWidget {
  final CurrencyRate rate;
  const _CurrencyCard({required this.rate});

  // Генерируем псевдо-историю на основе текущего курса (±3%) для визуала
  // Реальная история требует отдельного API — добавим на следующем шаге
  List<double> _fakeHistory() {
    final r = Random(rate.code.codeUnits.fold<int>(0, (a, b) => a + b));
    final base = rate.rateToRub;
    return List.generate(7, (i) {
      final delta = (r.nextDouble() - 0.48) * base * 0.06;
      return base + delta * (i / 6);
    });
  }

  Color get _color {
    switch (rate.code) {
      case 'USD': return const Color(0xFF4CAF50);
      case 'EUR': return const Color(0xFF2196F3);
      case 'GBP': return const Color(0xFF9C27B0);
      case 'CNY': return const Color(0xFFFF5722);
      case 'KZT': return const Color(0xFF00BCD4);
      case 'BTC': return const Color(0xFFF9A825);
      default:    return const Color(0xFF64B5F6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = _fakeHistory();
    final isUp = history.last >= history.first;
    final changeStr = (((history.last - history.first) / history.first) * 100)
        .toStringAsFixed(2);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Флаг / иконка
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(rate.flag,
                      style: TextStyle(fontSize: rate.code == 'BTC' ? 20 : 26)),
                ),
              ),
              const SizedBox(width: 14),
              // Название
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rate.code,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                    Text(rate.name,
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              // Курс + изменение
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    rate.code == 'BTC'
                        ? '${rate.rateToRub.toStringAsFixed(0)} ₽'
                        : '${rate.rateToRub.toStringAsFixed(2)} ₽',
                    style: TextStyle(
                        color: _color, fontWeight: FontWeight.bold, fontSize: 19),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                        color: isUp ? Colors.green : Colors.redAccent,
                        size: 16,
                      ),
                      Text(
                        '${isUp ? '+' : ''}$changeStr%',
                        style: TextStyle(
                          color: isUp ? Colors.green : Colors.redAccent,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Мини-график
          SizedBox(
            height: 36,
            child: CustomPaint(
              size: const Size(double.infinity, 36),
              painter: _SparklinePainter(values: history, color: _color, isUp: isUp),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sparkline painter ───────────────────────────────────────────────────────
class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final bool isUp;

  const _SparklinePainter({required this.values, required this.color, required this.isUp});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final minV = values.reduce(min);
    final maxV = values.reduce(max);
    final range = maxV - minV == 0 ? 1.0 : maxV - minV;

    final lineColor = isUp ? const Color(0xFF4CAF50) : Colors.redAccent;

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - ((values[i] - minV) / range) * size.height * 0.85 - 2;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Заливка
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [lineColor.withOpacity(0.25), lineColor.withOpacity(0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill,
    );

    // Линия
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Точка на конце
    final lastX = size.width;
    final lastY = size.height -
        ((values.last - minV) / range) * size.height * 0.85 - 2;
    canvas.drawCircle(Offset(lastX, lastY), 3.5,
        Paint()..color = lineColor..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values;
}

// ── Error view ──────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          const Text('Ошибка загрузки',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 8),
          Text(error,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF64B5F6).withOpacity(0.2),
              side: const BorderSide(color: Color(0xFF64B5F6)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: const Text('Повторить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
