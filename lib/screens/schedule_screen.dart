import 'package:flutter/material.dart';
import '../services/schedule_service.dart';
import '../theme/app_theme.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> with SingleTickerProviderStateMixin {
  final _service = ScheduleService();
  late TabController _tabs;
  List<ScheduleEvent> _todayEvents = [];
  List<ScheduleEvent> _tomorrowEvents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    final tom = now.add(const Duration(days: 1));
    final tomStr = '${tom.year}-${tom.month.toString().padLeft(2,'0')}-${tom.day.toString().padLeft(2,'0')}';
    final t = await _service.getEvents(date: todayStr);
    final tm = await _service.getEvents(date: tomStr);
    setState(() { _todayEvents = t; _tomorrowEvents = tm; _loading = false; });
  }

  Future<void> _addEventDialog() async {
    final titleCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    int hour = TimeOfDay.now().hour;
    int minute = 0;
    bool tomorrow = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AikaTheme.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('➕ Новое событие', style: TextStyle(color: Colors.white)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: titleCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Название события',
                hintStyle: TextStyle(color: Colors.white38),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AikaTheme.neonBlue)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AikaTheme.neonPink)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Заметка (необязательно)',
                hintStyle: TextStyle(color: Colors.white38),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AikaTheme.neonBlue)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AikaTheme.neonPink)),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Время: ', style: TextStyle(color: Colors.white70)),
              TextButton(
                onPressed: () async {
                  final t = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay(hour: hour, minute: minute),
                    builder: (c, child) => Theme(
                      data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AikaTheme.neonBlue)),
                      child: child!,
                    ),
                  );
                  if (t != null) setS(() { hour = t.hour; minute = t.minute; });
                },
                child: Text(
                  '${hour.toString().padLeft(2,'0')}:${minute.toString().padLeft(2,'0')}',
                  style: const TextStyle(color: AikaTheme.neonBlue, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ]),
            Row(children: [
              const Text('Завтра', style: TextStyle(color: Colors.white70)),
              Switch(
                value: tomorrow,
                activeColor: AikaTheme.neonPink,
                onChanged: (v) => setS(() => tomorrow = v),
              ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AikaTheme.neonBlue),
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                final now = DateTime.now();
                final base = tomorrow ? now.add(const Duration(days: 1)) : now;
                final dateStr = '${base.year}-${base.month.toString().padLeft(2,'0')}-${base.day.toString().padLeft(2,'0')}';
                await _service.addEvent(ScheduleEvent(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  title: titleCtrl.text.trim(),
                  hour: hour, minute: minute,
                  date: dateStr,
                  note: noteCtrl.text.trim(),
                ));
                Navigator.pop(ctx);
                _load();
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: AikaTheme.background,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white70), onPressed: () => Navigator.pop(context)),
        title: const Text('📅 Расписание', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AikaTheme.neonBlue,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          tabs: const [Tab(text: 'Сегодня'), Tab(text: 'Завтра')],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AikaTheme.neonBlue,
        onPressed: _addEventDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AikaTheme.neonBlue))
          : TabBarView(
              controller: _tabs,
              children: [
                _buildEventList(_todayEvents),
                _buildEventList(_tomorrowEvents),
              ],
            ),
    );
  }

  Widget _buildEventList(List<ScheduleEvent> events) {
    if (events.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('📭', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 12),
        const Text('Нет событий', style: TextStyle(color: Colors.white70, fontSize: 18)),
        const SizedBox(height: 8),
        Text('Нажми + или скажи Айке\n"добавь событие в 15:00"',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 13)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      itemBuilder: (ctx, i) {
        final e = events[i];
        return Dismissible(
          key: Key(e.id),
          direction: DismissDirection.endToStart,
          onDismissed: (_) async { await _service.deleteEvent(e.id); _load(); },
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.delete, color: Colors.red),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AikaTheme.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.25)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AikaTheme.neonBlue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(e.timeStr, style: const TextStyle(color: AikaTheme.neonBlue, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                if (e.note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(e.note, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ])),
            ]),
          ),
        );
      },
    );
  }
}
