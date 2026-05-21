import 'schedule_service.dart';

class BriefingService {

  /// Утренний брифинг — погода + мотивация
  Future<String> getMorningBriefing({String city = ''}) async {
    final now = DateTime.now();
    final greeting = _getGreeting(now.hour);
    final dayName = _getDayName(now.weekday);
    final dateStr = '\${now.day} \${_getMonthName(now.month)}';

    final buf = StringBuffer();
    buf.writeln('\$greeting! 🌸');
    buf.writeln('Сегодня \$dayName, \$dateStr.');
    buf.writeln('');

    try {
      // Погода (заглушка — можно подключить API)
      if (city.isNotEmpty) {
        buf.writeln('🌤 Погода в \$city: данные недоступны.');
      }
    } catch (e) {
      buf.writeln('☁️ Погоду не удалось получить.');
      buf.writeln('');
    }

    // Мотивация
    buf.writeln(_getMotivation(now.weekday));

    // Расписание на сегодня
    try {
      final schedule = ScheduleService();
      final events = await schedule.getEvents(date: _todayStr());
      if (events.isNotEmpty) {
        buf.writeln('');
        buf.writeln('📅 Твой план на сегодня:');
        for (final e in events) {
          buf.writeln('  • \${e.timeStr} — \${e.title}');
        }
      }
    } catch (_) {}

    return buf.toString().trim();
  }

  String _todayStr() {
    final n = DateTime.now();
    final mm = n.month.toString().padLeft(2, '0');
    final dd = n.day.toString().padLeft(2, '0');
    return '${n.year}-$mm-$dd';
  }

  String _getGreeting(int hour) {
    if (hour < 6) return 'Доброй ночи';
    if (hour < 12) return 'Доброе утро';
    if (hour < 17) return 'Добрый день';
    if (hour < 22) return 'Добрый вечер';
    return 'Доброй ночи';
  }

  String _getDayName(int weekday) {
    const days = ['понедельник','вторник','среда','четверг','пятница','суббота','воскресенье'];
    return days[(weekday - 1).clamp(0, 6)];
  }

  String _getMonthName(int month) {
    const months = ['января','февраля','марта','апреля','мая','июня',
                    'июля','августа','сентября','октября','ноября','декабря'];
    return months[(month - 1).clamp(0, 11)];
  }

  String _getMotivation(int weekday) {
    const motivations = [
      'Понедельник — начало новой недели. Заряжайся! 💪',
      'Вторник — самый продуктивный день. Вперёд! 🚀',
      'Среда — половина недели позади. Ты справляешься отлично! ⚡',
      'Четверг — финишная прямая! Ещё немного 🎯',
      'Пятница! Лёгкого дня и хороших выходных! 🎉',
      'Суббота — твой день. Отдыхай или делай что нравится 😊',
      'Воскресенье — перезарядка перед новой неделей ✨',
    ];
    return motivations[(weekday - 1).clamp(0, 6)];
  }

  /// Проверяем — это запрос на брифинг?
  bool isBriefingRequest(String text) {
    final t = text.toLowerCase();
    return t.contains('брифинг') ||
        t.contains('что пришло пока') ||
        t.contains('расскажи утром') ||
        t.contains('утренний обзор') ||
        t.contains('доброе утро айка') ||
        (t.contains('что сегодня') && t.contains('утро')) ||
        t.contains('как дела сегодня') ||
        t.contains('что нового сегодня');
  }
}

