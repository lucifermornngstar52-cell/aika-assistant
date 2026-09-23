import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aika_assistant/services/memory_service.dart';
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

}
