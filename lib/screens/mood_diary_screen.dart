import 'package:flutter/material.dart';
import '../services/mood_diary_service.dart';
import '../theme/app_theme.dart';

class MoodDiaryScreen extends StatefulWidget {
  const MoodDiaryScreen({Key? key}) : super(key: key);

  @override
  State<MoodDiaryScreen> createState() => _MoodDiaryScreenState();
}

class _MoodDiaryScreenState extends State<MoodDiaryScreen> {
  final _service = MoodDiaryService();
  List<Map> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _service.getEntries();
    setState(() {
      _entries = entries.reversed.toList();
      _loading = false;
    });
  }

  double get _avgScore {
    if (_entries.isEmpty) return 0;
    final week = _entries.where((e) {
      final d = DateTime.parse(e['date']);
      return DateTime.now().difference(d).inDays <= 7;
    }).toList();
    if (week.isEmpty) return 0;
    return week.map((e) => (e['score'] as num).toDouble()).reduce((a, b) => a + b) / week.length;
  }

  String _moodEmoji(int score) {
    if (score >= 9) return '🌟';
    if (score >= 7) return '😊';
    if (score >= 5) return '😐';
    if (score >= 3) return '😔';
    return '😢';
  }

  Color _moodColor(int score) {
    if (score >= 8) return const Color(0xFF4CAF50);
    if (score >= 6) return AikaTheme.neonBlue;
    if (score >= 4) return Colors.orange;
    return Colors.redAccent;
  }

  String _formatDate(String iso) {
    final d = DateTime.parse(iso);
    final now = DateTime.now();
    if (d.day == now.day && d.month == now.month) return 'Сегодня';
    if (d.day == now.day - 1 && d.month == now.month) return 'Вчера';
    return '${d.day}.${d.month}.${d.year}';
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
        title: const Text(
          '📖 Дневник настроения',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AikaTheme.neonBlue))
          : _entries.isEmpty
              ? _buildEmpty()
              : Column(
                  children: [
                    _buildStats(),
                    Expanded(child: _buildList()),
                  ],
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('😶', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          const Text(
            'Пока нет записей',
            style: TextStyle(color: Colors.white70, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Скажи Айке "моё настроение хорошее"\nили "настроение: отлично"',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final avg = _avgScore;
    final emoji = avg >= 8 ? '🌟' : avg >= 6 ? '😊' : avg >= 4 ? '😐' : avg > 0 ? '😔' : '—';
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AikaTheme.neonBlue.withOpacity(0.2), AikaTheme.neonPink.withOpacity(0.1)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem(emoji, avg > 0 ? '${avg.toStringAsFixed(1)}/10' : '—', 'За неделю'),
          _statItem('📊', '${_entries.length}', 'Всего записей'),
          _statItem('📅', _entries.isNotEmpty ? _formatDate(_entries.first['date']) : '—', 'Последняя'),
        ],
      ),
    );
  }

  Widget _statItem(String emoji, String value, String label) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _entries.length,
      itemBuilder: (ctx, i) {
        final e = _entries[i];
        final score = (e['score'] as num).toInt();
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AikaTheme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _moodColor(score).withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Text(_moodEmoji(score), style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e['mood'] ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(e['date']),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _moodColor(score).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$score/10',
                  style: TextStyle(color: _moodColor(score), fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
