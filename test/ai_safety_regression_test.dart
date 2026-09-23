import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aika_assistant/services/memory_service.dart';
import 'package:aika_assistant/services/conversation_history_service.dart';
import 'package:aika_assistant/services/ai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('chat_history JSON is the sole conversation source and keeps roles', () async {
    SharedPreferences.setMockInitialValues({
      'chat_history': jsonEncode([
        {'id': '1', 'role': 'user', 'content': 'первый'},
        {'id': '2', 'role': 'aika', 'content': 'ответ'},
        {'id': '3', 'role': 'user', 'content': 'последний'},
      ]),
      'conversation_history': <String>['user: устаревшее'],
    });
    final history = await MemoryService().getHistory();
    expect(history, ['user: первый', 'assistant: ответ', 'user: последний']);
    final navigation = ConversationHistoryService();
    await navigation.initialize();
    expect(navigation.navigatePrev(''), 'последний');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('aivora_conv_history_v1'), isFalse);
    await MemoryService().clearHistory();
    expect(await MemoryService().getHistory(), isEmpty);
  });

  test('parses all text blocks after reasoning without exposing ACTION', () {
    final response = {
      'choices': [
        {'message': {'content': [
          {'type': 'reasoning', 'text': 'скрытое рассуждение'},
          {'type': 'tool_use', 'text': 'вызов инструмента'},
          {'type': 'text', 'text': 'Первая часть [ACTION:lock_screen]'},
          {'type': 'text', 'text': 'Вторая часть'},
        ]}},
      ],
    };
    expect(AiService.extractGroqContent(response), 'Первая часть\nВторая часть');
  });

  test('ignores malformed choices and reports an invalid response', () {
    expect(AiService.extractGroqContent({'choices': [null, 7,
      {'message': {'content': [{'type': 'text', 'text': 'Ответ'}]}}]}), 'Ответ');
    expect(() => AiService.extractGroqContent({'choices': [
      {'message': {'content': [{'type': 'reasoning', 'text': 'секрет'}]}}
    ]}), throwsFormatException);
    expect(() => AiService.extractGroqContent({'choices': 'не список'}),
        throwsFormatException);
  });

  test('current message appears once, latest history retained, aika is assistant', () {
    final history = <String>[];
    for (var i = 1; i <= 26; i++) {
      history.add('user: вопрос $i');
      history.add('aika: ответ $i');
    }
    history.add('user: вопрос 27');
    final recent = AiService.recentHistory(history, 'вопрос 27');
    expect(recent.length, 20);
    expect(recent.first, {'role': 'user', 'content': 'вопрос 17'});
    expect(recent.last, {'role': 'assistant', 'content': 'ответ 26'});
    expect(recent.where((m) => m['content'] == 'вопрос 27'), isEmpty);
    expect(AiService.recentHistory(['user: повтор', 'user: повтор'], 'повтор'),
        [{'role': 'user', 'content': 'повтор'}]);
  });

  test('web search year rolls forward without hardcoded 2025 or 2026', () {
    expect(AiService.shouldSearchWeb('события 2027 года', year: 2027), isTrue);
    expect(AiService.shouldSearchWeb('события 2028 года', year: 2028), isTrue);
    expect(AiService.shouldSearchWeb('события 2025 года', year: 2027), isFalse);
  });

}
