import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Автоматически запускает музыку при открытии игр.
/// Музыка запускается В ФОНЕ — игра не сворачивается.
class GameMusicService {
  static const _keyEnabled    = 'game_music_enabled';
  static const _keyPlayer     = 'game_music_player';
  static const _keyGameList   = 'game_music_game_packages';
  static const _mediaChannel  = MethodChannel('com.aika.assistant/media');
  static const _audioChannel  = MethodChannel('aika/audio');

  static const Map<String, String> availablePlayers = {
    'com.spotify.music':                    'Spotify',
    'com.google.android.apps.youtube.music':'YouTube Music',
    'ru.yandex.music':                      'Яндекс Музыка',
    'com.vk.vkplay':                        'VK Музыка',
    'com.soundcloud.android':               'SoundCloud',
  };

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
    'jp.konami.pesam':                      'eFootball',
    'com.ea.game.nfs14_row':               'Need for Speed',
    'com.king.candycrushsaga':             'Candy Crush',
    'com.dts.freefireth':                   'Free Fire TH',
    'com.tencent.tmgp.pubgmhd':            'PUBG Mobile HD',
    'com.garena.game.kgth':                'Free Fire TH 2',
  };

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

  static Future<List<String>> getUserGames() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyGameList) ?? '[]';
    return List<String>.from(jsonDecode(raw));
  }

  static Future<void> addGame(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getUserGames();
    if (!list.contains(packageName)) {
      list.add(packageName);
      await prefs.setString(_keyGameList, jsonEncode(list));
    }
  }

  static Future<void> removeGame(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getUserGames();
    list.remove(packageName);
    await prefs.setString(_keyGameList, jsonEncode(list));
  }

  /// Проверяет играет ли сейчас музыка
  static Future<bool> _isMusicPlaying() async {
    try {
      return await _audioChannel.invokeMethod<bool>('isMusicPlaying') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Запускает музыку В ФОНЕ через MediaKey — без открытия UI плеера
  /// Игра остаётся на экране, музыка начинает играть поверх
  static Future<void> _startMusicInBackground(String playerPackage) async {
    try {
      // Сначала пробуем возобновить через media key (не открывает UI)
      final isPlaying = await _isMusicPlaying();
      if (!isPlaying) {
        // Запускаем плеер в фоне через нативный метод
        await _mediaChannel.invokeMethod('startMusicBackground', {
          'package': playerPackage,
        });
      }
    } catch (_) {}
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

    // Cooldown
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

    // Небольшая задержка чтобы игра успела загрузиться
    await Future.delayed(const Duration(seconds: 2));

    // Запускаем музыку в фоне — игра не сворачивается!
    await _startMusicInBackground(player);

    return '🎮 $gameName — включаю $playerName в фоне 🎵';
  }

  static Future<String?> tryParseCommand(String text) async {
    final t = text.toLowerCase();

    if (t.contains('включи автомузыку') || t.contains('музыка в играх') ||
        t.contains('автоматически музыку') || t.contains('авто музыку')) {
      await setEnabled(true);
      final player = await getPlayer();
      final name = availablePlayers[player] ?? 'Spotify';
      return '🎵 Автомузыка включена! Буду запускать $name в фоне когда заходишь в игру.';
    }

    if (t.contains('выключи автомузыку') || t.contains('отключи музыку в играх')) {
      await setEnabled(false);
      return '🔇 Автомузыка отключена.';
    }

    return null;
  }
}
