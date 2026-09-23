import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aika_assistant/services/memory_service.dart';

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

}
