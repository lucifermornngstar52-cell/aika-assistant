import 'dart:convert';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Автоматически запускает музыку при открытии игр.
/// Пользователь выбирает: какой музыкальный плеер и какие игры триггерят.
class GameMusicService {
  static const _keyEnabled     = 'game_music_enabled';
  static const _keyPlayer      = 'game_music_player';
  static const _keyGameList    = 'game_music_game_packages';
  static const _keyLastPlayed  = 'game_music_last_played';

  static const Map<String, String> availablePlayers = {
    'com.spotify.music':                    'Spotify',
    'com.google.android.apps.youtube.music':'YouTube Music',
    'ru.yandex.music':                      'Яндекс Музыка',
    'com.vk.vkplay':                        'VK Музыка',
    'com.soundcloud.android':               'SoundCloud',
  };

  // Известные игровые пакеты (встроенный список)
  static const Map<String, String> knownGames = {
    'com.supercell.brawlstars':             'Brawl Stars',
    'com.supercell.clashofclans':           'Clash of Clans',
    'com.supercell.clashroyale':            'Clash Royale',
    'com.tencent.ig':                       'PUBG Mobile',
    'com.pubg.krmobile':                    'PUBG Mobile KR',
    'com.garena.game.freefire':             'Free Fire',
    'com.activision.callofduty.shooter':    'Call of Duty Mobile',
    'com.roblox.client':                    'Roblox',
    'com.mojang.minecraftpe':               'Minecraft',
    'com.innersloth.spacemafia':            'Among Us',
    'com.YoStarEN.Arknights':              'Arknights',
    'com.miHoYo.GenshinImpact':            'Genshin Impact',
    'com.mobile.legends':                   'Mobile Legends',
    'com.vng.mlbbvn':                       'Mobile Legends VN',
    'jp.konami.pesam':                      'eFootball',
    'com.ea.game.nfs14_row':               'Need for Speed',
    'com.games.uno':                        'UNO!',
    'com.king.candycrushsaga':             'Candy Crush',
    'com.dts.freefireth':                   'Free Fire TH',
  };

  static bool _initialized = false;
  static String? _lastTriggeredPkg;
  static DateTime? _lastTriggerTime;
  static const _cooldown = Duration(minutes: 10);

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);
  }

  static Future<String> getPlayer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPlayer) ?? 'com.spotify.music';
  }

  static Future<void> setPlayer(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPlayer, packageName);
  }

  /// Возвращает список пакетов игр выбранных пользователем
  static Future<List<String>> getUserGames() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyGameList) ?? '[]';
    return List<String>.from(json.decode(raw));
  }

  static Future<void> addGame(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getUserGames();
    if (!list.contains(packageName)) {
      list.add(packageName);
      await prefs.setString(_keyGameList, json.encode(list));
    }
  }

  static Future<void> removeGame(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getUserGames();
    list.remove(packageName);
    await prefs.setString(_keyGameList, json.encode(list));
  }

  /// Вызывается из ScreenWatcher когда меняется приложение
  static Future<String?> onAppChanged(String packageName) async {
    if (!await isEnabled()) return null;

    final userGames = await getUserGames();
    final allTriggerPkgs = {
      ...knownGames.keys,
      ...userGames,
    };

    if (!allTriggerPkgs.contains(packageName)) return null;

    // Cooldown — не спамим
    final now = DateTime.now();
    if (_lastTriggeredPkg == packageName &&
        _lastTriggerTime != null &&
        now.difference(_lastTriggerTime!) < _cooldown) {
      return null;
    }

    _lastTriggeredPkg = packageName;
    _lastTriggerTime = now;

    final player = await getPlayer();
    final playerName = availablePlayers[player] ?? 'плеер';
    final gameName = knownGames[packageName] ?? packageName.split('.').last;

    // Запускаем плеер
    await _launchApp(player);

    return '🎮 $gameName запущена! Включаю $playerName 🎵';
  }

  static Future<void> _launchApp(String packageName) async {
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: packageName,
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    } catch (_) {}
  }

  /// Парсим голосовую команду для настройки
  static Future<String?> tryParseCommand(String text) async {
    final t = text.toLowerCase();

    if (t.contains('включи автомузыку') || t.contains('музыка в играх') ||
        t.contains('автоматически музыку') || t.contains('авто музыку')) {
      await setEnabled(true);
      final player = await getPlayer();
      final name = availablePlayers[player] ?? 'Spotify';
      return '🎵 Автомузыка в играх включена! Буду запускать $name когда ты заходишь в игру.';
    }

    if (t.contains('выключи автомузыку') || t.contains('отключи музыку в играх')) {
      await setEnabled(false);
      return '🔇 Автомузыка отключена.';
    }

    return null;
  }
}
