---
name: Aika project architecture
description: Flutter/Android аниме AI ассистент — ключевые файлы, архитектура, технологический стек.
---

# Айка — архитектура проекта

## Стек
- Flutter 3.0+ / Android (Kotlin native code)
- Gemini 2.0 Flash + GPT-4o-mini (двойной AI)
- Live2D аватар через PIXI.js в WebView
- STT: flutter_speech_to_text, TTS: edge_tts (Microsoft Neural)

## Лендинг (веб-превью)
- `server.js` — Node.js, port 5000 (workflow: "Start application")
- `web/index.html` — на русском, описывает Flutter/Android проект

## Ключевые сервисы
- `lib/services/voice_command_processor.dart` — 150+ команд без AI (NEW)
- `lib/services/phone_control_service.dart` — legacy звонки/SMS/навигация
- `lib/services/ai_service.dart` — Gemini+OpenAI, 60+ ACTION тегов
- `lib/services/device_service.dart` — выполнение ACTION тегов из AI ответов
- `lib/services/wake_word_service.dart` — бесконечное прослушивание "Айка"
- `lib/services/aika_automation_service.dart` — сложные макросы и игровой мониторинг
- `lib/screens/main_screen.dart` — главный экран, _sendMessage() — точка сборки всего

## Порядок обработки команды в _sendMessage()
1. IMAGE_GENERATED (специальный случай)
2. **VoiceCommandProcessor** (150+ оффлайн команд) — NEW
3. PhoneControlService (legacy)
4. ShoplistService
5. ClipboardService
6. ContactsService
7. CalendarService
8. ... другие сервисы
9. AI (Gemini/OpenAI) — если ничего не сработало

## MethodChannel
`com.aika.assistant/screen_reader` — brightness, nav back/home/recents, lock, screenshot, globalAction
