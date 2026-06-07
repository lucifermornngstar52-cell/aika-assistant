---
name: DeviceService executeAction() map
description: Все ACTION теги которые умеет выполнять DeviceService и как добавлять новые.
---

# DeviceService ACTION handlers

## Новые ACTION теги (добавлены)

### Яркость
`brightness_max`, `brightness_min`, `brightness_50`, `brightness_auto`, `brightness_N` (любой %)

### Беспроводные сети
`open_wifi`, `open_bluetooth`, `open_airplane_mode`, `open_hotspot`, `open_dnd`, `open_power_save`

### Системные действия
`lock_screen` (globalAction 8), `power_menu` (globalAction 12), `close_app`, `open_dialer`, `open_messages`, `open_clock`

### Поиск и навигация
`youtube_search_X`, `maps_route_X`, `maps_search_X` (X — слова через _)

### Приложения (extraApps map)
`open_drive`, `open_photos`, `open_play_store`, `open_viber`, `open_skype`, `open_firefox`, `open_opera`, `open_twitch`, `open_tinder`, `open_duolingo`, `open_uber`, `open_yandex_taxi`, `open_sber`, `open_tinkoff`, `open_avito`, `open_ozon`, `open_wildberries`, `open_ok`, `open_gosuslugi`, `open_yandex_music`, `open_yandex_browser`, `open_signal`

### Громкость %
`volume_N` (например `volume_50` → 50%)

### Погода
`get_weather` → открывает weather.com

## Структура executeAction()
1. what_on_screen → AccessibilityService
2. describe_screen / smart_tap / smart_do → GeminiComputerUseService
3. maps_route_*, maps_search_*, youtube_search_* → launchUrl
4. brightness_* → MethodChannel setBrightness или Settings
5. open_wifi/bt/airplane/hotspot/dnd/power_save → AndroidIntent Settings
6. lock_screen/power_menu/close_app → MethodChannel globalAction
7. open_dialer/messages/clock/get_weather → launchPackage / launchUrl
8. volume_N → VolumeController.setVolume()
9. extraApps map → launchPackage
10. switch(action) → flashlight, volume_up/down/mute/max, battery, music, nav, screenshot

**Why:** постепенное добавление блоков if/switch — проще поддерживать чем один giant switch.
