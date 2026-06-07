---
name: Voice command pipeline
description: Как VoiceCommandProcessor интегрирован и как расширять список команд.
---

# Голосовой процессор (VoiceCommandProcessor)

## Файл
`lib/services/voice_command_processor.dart` — ~980 строк, синглтон

## Интеграция
- Импорт добавлен в `main_screen.dart`
- Поле: `final VoiceCommandProcessor _voiceProcessor = VoiceCommandProcessor();`
- `_voiceProcessor.init()` вызывается в `_initServices()`
- Вызов в `_sendMessage()` — ДО PhoneControlService, возвращает `VoiceCmdResult?`
- Если `action == 'dance'` — триггерит танцевальную анимацию Айки

## Категории (150+ команд)
1. Фонарик (вкл/выкл/переключить)
2. Громкость (%, громче/тише, mute, max)
3. Яркость (%, авто, max/min, ярче/темнее)
4. Wi-Fi, Bluetooth (→ системные настройки)
5. Авиарежим, горячая точка, DND, экономия энергии
6. Батарея (level + charging state)
7. Скриншот (через Accessibility globalAction 9)
8. Камера (фото, видео)
9. Навигация (назад, домой, недавние, закрыть app)
10. Блокировка экрана (globalAction 8), меню питания (globalAction 12)
11. 50+ приложений по таблице _knownApps
12. Поиск Google
13. YouTube поиск
14. Google Maps маршрут/поиск
15. Звонки, SMS
16. Таймер (AndroidIntent + парсинг ч/мин/сек)
17. Будильник (AndroidIntent + парсинг H:MM)
18. Напоминания (SharedPreferences хранилище)
19. Погода (WeatherService.getWeather() → String)
20. Дата/Время (локально)
21. Настройки системы (звук, дисплей, GPS, приложения)
22. Калькулятор, диктофон, уведомления, Wikipedia, переводчик
23. Танец ("потанцуй" → action: 'dance')

## Добавление новой команды
Добавить `if (_has(t, [...ключевые_слова...])) { ... return VoiceCmdResult.ok('...'); }` в `process()`.

**Why:** оффлайн обработка без AI — мгновенный ответ, экономит API запросы.
