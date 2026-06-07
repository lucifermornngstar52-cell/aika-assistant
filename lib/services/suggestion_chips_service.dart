import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// SuggestionChipsService — быстрые chips-подсказки после ответа ассистента.
/// Вдохновлено Google Assistant Desktop Client suggestion area (MIT).
///
/// После каждого ответа показывает 2-4 контекстных подсказки
/// которые пользователь может нажать для продолжения диалога.

class SuggestionChip {
  final String label;
  final String query; // что будет отправлено при нажатии
  SuggestionChip({required this.label, required this.query});
}

class SuggestionChipsService {
  static final SuggestionChipsService _i = SuggestionChipsService._();
  factory SuggestionChipsService() => _i;
  SuggestionChipsService._();

  // ──────────────── ГЕНЕРАЦИЯ ЧИПСОВ ────────────────

  /// Возвращает контекстные чипсы на основе ответа ассистента
  List<SuggestionChip> getSuggestionsForResponse(String response) {
    final r = response.toLowerCase();

    // Погода
    if (_has(r, ['погода', 'температура', 'градус', 'дождь', 'солнце', 'облачно'])) {
      return [
        SuggestionChip(label: '🌡 На завтра', query: 'Какая погода будет завтра?'),
        SuggestionChip(label: '👕 Что надеть', query: 'Что мне надеть сегодня?'),
        SuggestionChip(label: '🌍 В другом городе', query: 'Погода в Москве'),
      ];
    }

    // Музыка
    if (_has(r, ['музыка', 'трек', 'песня', 'включила', 'spotify', 'играет'])) {
      return [
        SuggestionChip(label: '⏭ Следующий', query: 'Следующий трек'),
        SuggestionChip(label: '⏸ Пауза', query: 'Поставь на паузу'),
        SuggestionChip(label: '🎵 Что играет', query: 'Что сейчас играет?'),
      ];
    }

    // Таймер / напоминание
    if (_has(r, ['таймер', 'напоминание', 'напомнила', 'поставила', 'минут', 'сработал'])) {
      return [
        SuggestionChip(label: '⏰ Ещё раз', query: 'Поставь ещё один таймер'),
        SuggestionChip(label: '🗒 Мои напоминания', query: 'Покажи мои напоминания'),
        SuggestionChip(label: '❌ Отмени', query: 'Отмени таймер'),
      ];
    }

    // Список покупок
    if (_has(r, ['список покупок', 'добавила', 'купи', 'шоплист'])) {
      return [
        SuggestionChip(label: '📋 Показать список', query: 'Покажи список покупок'),
        SuggestionChip(label: '➕ Добавить ещё', query: 'Добавь в список покупок'),
        SuggestionChip(label: '🗑 Очистить', query: 'Очисти список покупок'),
      ];
    }

    // Список дел
    if (_has(r, ['список дел', 'добавила в дела', 'задача'])) {
      return [
        SuggestionChip(label: '📝 Все дела', query: 'Покажи список дел'),
        SuggestionChip(label: '➕ Ещё задачу', query: 'Добавь в список дел'),
        SuggestionChip(label: '🗑 Очистить дела', query: 'Очисти список дел'),
      ];
    }

    // Шаги / активность
    if (_has(r, ['шагов', 'шаги', 'км', 'ккал', 'прошла'])) {
      return [
        SuggestionChip(label: '🔄 Обновить', query: 'Сколько я прошёл шагов?'),
        SuggestionChip(label: '🎯 Цель', query: 'Поставь цель на 10000 шагов'),
      ];
    }

    // Календарь
    if (_has(r, ['событий', 'встреча', 'календарь', 'расписание', 'добавила'])) {
      return [
        SuggestionChip(label: '📅 Завтра', query: 'Что у меня завтра?'),
        SuggestionChip(label: '➕ Новое событие', query: 'Добавь встречу'),
        SuggestionChip(label: '📆 На неделю', query: 'Мои события на неделю'),
      ];
    }

    // Контакт найден
    if (_has(r, ['контакт', 'нашла', 'номер', 'телефон'])) {
      return [
        SuggestionChip(label: '📞 Позвонить', query: 'Позвони этому человеку'),
        SuggestionChip(label: '💬 Написать', query: 'Напиши СМС'),
      ];
    }

    // Буфер обмена
    if (_has(r, ['буфер', 'скопировала', 'clipboard'])) {
      return [
        SuggestionChip(label: '📋 Что в буфере', query: 'Что в буфере?'),
        SuggestionChip(label: '🗑 Очистить', query: 'Очисти буфер'),
      ];
    }

    // Дефолтные универсальные
    return [
      SuggestionChip(label: '🌤 Погода', query: 'Какая сегодня погода?'),
      SuggestionChip(label: '📋 Список дел', query: 'Покажи список дел'),
      SuggestionChip(label: '⏰ Таймер', query: 'Поставь таймер на 10 минут'),
    ];
  }

  bool _has(String text, List<String> words) =>
      words.any((w) => text.contains(w));
}

// ──────────────── ВИДЖЕТ ────────────────

class SuggestionChipsWidget extends StatelessWidget {
  final List<SuggestionChip> chips;
  final void Function(String query) onChipTap;

  const SuggestionChipsWidget({
    Key? key,
    required this.chips,
    required this.onChipTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final chip = chips[i];
          return GestureDetector(
            onTap: () => onChipTap(chip.query),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AikaTheme.neonBlue.withOpacity(0.4),
                  width: 1,
                ),
              ),
              child: Text(
                chip.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
