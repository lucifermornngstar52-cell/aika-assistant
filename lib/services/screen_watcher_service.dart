import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'aika_self_learning_service.dart';
import 'aika_game_helper_service.dart';
import 'aika_zone_watcher_service.dart';

typedef ScreenReactionCallback = void Function(String reaction, String overlayState);

class ScreenWatcherService {
  static const _channel      = MethodChannel('com.aika.assistant/screen');
  static const _eventChannel = EventChannel('com.aika.assistant/screen_events');

  static String _currentPackage = '';
  static String _currentLabel   = '';
  static StreamSubscription? _sub;
  static String _lastReactedPackage = '';
  static DateTime? _lastReactionTime;
  static const _cooldown = Duration(seconds: 20);
  static final _rnd = Random();

  static Map<String, String>? getCurrentAppInfo() {
    if (_currentPackage.isEmpty) return null;
    return {'package': _currentPackage, 'label': _currentLabel};
  }

  static String get currentPackage => _currentPackage;
  static String get currentLabel   => _currentLabel;

  static void startWatching({ScreenReactionCallback? onReaction}) {
    _sub?.cancel();
    _sub = _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      final pkg   = (event['package'] ?? '') as String;
      final label = (event['label']   ?? '') as String;
      if (pkg.isEmpty) return;
      _currentPackage = pkg;
      _currentLabel   = label;
      if (onReaction == null) return;
      final now = DateTime.now();
      final isSamePkg = pkg == _lastReactedPackage;
      final cooldownExpired = _lastReactionTime == null ||
          now.difference(_lastReactionTime!) > _cooldown;
      if (!isSamePkg || cooldownExpired) {
        AikaSelfLearningService.recordAction(type: 'app_open', value: label);
        AikaGameHelperService.setCurrentGame(_detectGamePkg(pkg));
        final result = _buildReaction(pkg, label);
        if (result != null) {
          _lastReactedPackage = pkg;
          _lastReactionTime   = now;
          onReaction(result.$1, result.$2);
        }
      }
    }, onError: (_) {});
  }

  static void stopWatching() { _sub?.cancel(); _sub = null; }

  static Future<bool> isAccessibilityEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
    } catch (_) { return false; }
  }

  static Future<void> openAccessibilitySettings() async {
    try { await _channel.invokeMethod('openAccessibilitySettings'); } catch (_) {}
  }

  // Правильный случайный выбор через Random
  static String _pick(List<String> phrases) {
    return phrases[_rnd.nextInt(phrases.length)];
  }

  /// Возвращает (текст, overlayState) или null
  static (String, String)? _buildReaction(String pkg, String label) {
    switch (pkg) {

      // ── WhatsApp ──────────────────────────────────────────────────────
      case 'com.whatsapp':
        return (_pick([
          'WhatsApp открыт 💬 Не забудь ответить всем!',
          'О, ватсап! Кто там пишет интересного? 😏',
          'WhatsApp — давай отвечай, не заставляй людей ждать 😄',
          'Ватсап открылся... Надеюсь там не рабочий чат в 12 ночи 😅',
          'Так, WhatsApp. Сначала важные, потом групповые чаты 😄',
        ]), 'telegram');

      // ── Telegram ─────────────────────────────────────────────────────
      case 'org.telegram.messenger':
      case 'org.telegram.messenger.web':
        return (_pick([
          'Телеграм открыт 📨 Там что-то важное?',
          'О, телеграм! Много непрочитанных? 😄',
          'Телеграм — надеюсь не спам от ботов!',
          'Телеграм! Каналы или личка?',
          'Открываем телеграм... Ну что там интересного? 👀',
        ]), 'telegram');

      // ── Instagram ────────────────────────────────────────────────────
      case 'com.instagram.android':
        return (_pick([
          'Инстаграм 📸 Листаем ленту?',
          'Инста открыт. Что интересного нашёл?',
          'Инстаграм — только не залипни на 2 часа! 😄',
          'О, Инстаграм! Сторис или рилсы? 🎬',
          'Инста! Ставить лайки или выкладывать что-то? 📸',
        ]), 'greeting');

      // ── VK ───────────────────────────────────────────────────────────
      case 'com.vkontakte.android':
        return (_pick([
          'ВКонтакте открыл 🎵 Музыку или ленту?',
          'О, ВК! Что смотрим сегодня?',
          'ВКонтакте — видосы, музыка или переписка?',
          'ВК открыт! Мемы или новости? 😄',
          'О, ВКонтакте! Не видела тебя там давно 👀',
        ]), 'vk');

      // ── Discord ──────────────────────────────────────────────────────
      case 'com.discord':
        return (_pick([
          'Discord 🎧 В игре или общаешься?',
          'Дискорд открыт. Какой сервер?',
          'Discord! Голосовой чат или текст? 🎮',
          'О, дискорд! Там уже кто-то в войсе? 🎧',
          'Дискорд — ладно, скажи если нужна помощь 🎮',
        ]), 'greeting');

      // ── Viber ────────────────────────────────────────────────────────
      case 'com.viber.voip':
        return (_pick([
          'Вайбер открыт. Не забудь ответить!',
          'О, Вайбер! Кто там?',
          'Viber! Звонок или сообщение?',
          'Вайбер открылся 📲 Что пишут?',
          'Viber — давно им не пользовалась 😄',
        ]), 'greeting');

      // ── Одноклассники ────────────────────────────────────────────────
      case 'ru.ok.android':
        return (_pick([
          'Одноклассники 🐦 Кому привет пишем?',
          'ОК открыт! Что нового в ленте?',
          'Одноклассники — привет из 2010-х 😄',
          'ОК.ру! Игры или общение?',
          'Одноклассники открылись 👋',
        ]), 'greeting');

      // ── Snapchat ─────────────────────────────────────────────────────
      case 'com.snapchat.android':
        return (_pick([
          'Снэпчат! 👻 Что за снэп пришёл?',
          'Snapchat открыт. Стрик не потеряй! 🔥',
          'Снэпчат! Фото или видео шлём? 📸',
          'О, Snapchat! Там что-то исчезающее? 👻',
          'Снэпчат — осторожно, стрик! 🔥',
        ]), 'greeting');

      // ── Twitter / X ──────────────────────────────────────────────────
      case 'com.twitter.android':
      case 'com.X.android':
        return (_pick([
          'Twitter / X открыт 🐦 Что в трендах?',
          'Твиттер! Что пишут сегодня?',
          'X открыт. Читаем или постим? ✍️',
          'Твиттер — там сейчас точно что-то горячее 🔥',
          'О, Х! Посмотри что в топе! 👀',
        ]), 'greeting');

      // ── YouTube ──────────────────────────────────────────────────────
      case 'com.google.android.youtube':
        return (_pick([
          'YouTube открыл ▶️ Что смотришь?',
          'Ютуб! Обучение или просто отдыхаем? 😄',
          'YouTube — только не застрянь на рекомендациях 😄',
          'О, Ютуб! Что за видео сегодня? 🎬',
          'YouTube открылся! Скажи если хочешь что-то найти 🔍',
        ]), 'youtube');

      // ── TikTok ───────────────────────────────────────────────────────
      case 'com.zhiliaoapp.musically':
      case 'com.ss.android.ugc.trill':
        return (_pick([
          'ТикТок? Осторожно, там время исчезает 😄',
          'О, тикток! Уже час прошёл? 😄',
          'ТикТок открыт! Не пропади 😏',
          'Тикток... ладно, 5 минут и хватит, да? 😄',
          'О, рилсы и тикток! Что за тренды сегодня? 🕺',
        ]), 'dance');

      // ── Netflix ──────────────────────────────────────────────────────
      case 'com.netflix.mediaclient':
        return (_pick([
          'Netflix 🍿 Кино или сериал?',
          'Нетфликс! Что смотрим сегодня?',
          'Netflix — один эпизод, обещаешь? 😄',
          'Нетфликс открыт! Уже выбрал что смотреть? 🎬',
          'О, нетфликс! Скажи название — порекомендую 🍿',
        ]), 'youtube');

      // ── Twitch ───────────────────────────────────────────────────────
      case 'tv.twitch.android.app':
        return (_pick([
          'Twitch 🎮 Кого смотришь?',
          'О, твич! Стримы или турниры?',
          'Twitch открыт! Какой канал? 🎮',
          'Твич! Там сейчас кто онлайн? 👀',
          'Twitch — донатить или просто смотреть? 😄',
        ]), 'youtube');

      // ── Spotify ──────────────────────────────────────────────────────
      case 'com.spotify.music':
        return (_pick([
          'Spotify 🎵 Что слушаем?',
          'Спотифай! Хочешь я потанцую? 💃',
          'Музыка — это хорошо! Что за плейлист? 🎵',
          'Spotify открыт! Настроение какое? Подберу плейлист 🎧',
          'О, спотифай! Новые релизы смотришь или старое? 🎵',
        ]), 'music');

      // ── YouTube Music ────────────────────────────────────────────────
      case 'com.google.android.apps.youtube.music':
        return (_pick([
          'YouTube Music 🎵 Что в плейлисте?',
          'Ютуб Мьюзик! Что слушаем? 🎵',
          'YouTube Music открыт 🎧',
          'Музыка от ютуба! Хороший выбор 🎵',
          'YouTube Music — скажи жанр, найду что-нибудь 🎶',
        ]), 'music');

      // ── Яндекс Музыка ────────────────────────────────────────────────
      case 'ru.yandex.music':
        return (_pick([
          'Яндекс Музыка 🎵 Хороший вкус!',
          'Яндекс.Музыка открыта! Что играет? 🎵',
          'О, Яндекс Музыка! Какое настроение? 🎧',
          'Яндекс Музыка — мой фаворит среди стримингов 😄',
          'Музычка! Что слушаем сегодня? 🎵',
        ]), 'music');

      // ── VK Музыка ────────────────────────────────────────────────────
      case 'com.vk.music':
        return (_pick([
          'VK Музыка 🎵 Что слушаем?',
          'ВК Музыка открыта! Хороший плейлист? 🎶',
          'О, музыка из ВК! Что за трек? 🎵',
          'VK Music — скажи исполнителя, найду похожее 🎵',
          'Музычка от ВК! Включаем 🎧',
        ]), 'music');

      // ── SoundCloud ───────────────────────────────────────────────────
      case 'com.soundcloud.android':
        return (_pick([
          'SoundCloud 🎵 Независимая музыка!',
          'Саундклауд! Новые треки ищем? 🎵',
          'SoundCloud открыт — там всегда что-то интересное 🎶',
          'О, саундклауд! Следишь за андеграундом? 🎵',
          'SoundCloud — хорошее место для новых открытий 🎧',
        ]), 'music');

      // ── Kaspi ────────────────────────────────────────────────────────
      case 'kz.kaspi.mobile':
        return (_pick([
          'Kaspi открыт 💳 Переводим или платим?',
          'О, каспи! Что за операция? 💰',
          'Kaspi — осторожно с расходами 😄💳',
          'Каспи открылся! Надеюсь приходы, а не расходы 😏',
          'Kaspi Pay! Быстрый перевод? 💸',
        ]), 'thinking');

      // ── 2GIS ─────────────────────────────────────────────────────────
      case 'ru.dublgis.dgismobile':
        return (_pick([
          '2ГИС открыт 🗺️ Куда идём?',
          'О, 2ГИС! Ищем место или маршрут? 📍',
          '2GIS — нашёл куда добраться? 🗺️',
          'Двагис открылся! Что ищем? 📍',
          '2ГИС: скажи куда — помогу найти маршрут 🗺️',
        ]), 'thinking');

      // ── Google Maps ──────────────────────────────────────────────────
      case 'com.google.android.apps.maps':
        return (_pick([
          'Google Maps 🗺️ Куда едем?',
          'Карты открыты! Маршрут уже построен? 📍',
          'Google Maps — далеко собрался? 🗺️',
          'Карты! Пешком, на машине или транспорте? 🚗',
          'Google Maps открыт. Пробки проверяем? 🚦',
        ]), 'thinking');

      // ── Яндекс Карты ─────────────────────────────────────────────────
      case 'ru.yandex.yandexmaps':
      case 'ru.yandex.traffic':
        return (_pick([
          'Яндекс Карты 🗺️ Пробки смотришь?',
          'Яндекс.Карты! Куда едем? 🚗',
          'Карты открыты — маршрут строим? 📍',
          'Яндекс Карты! Надеюсь без пробок 😄🚦',
          'Яндекс.Карты открыты. Такси или сам? 🗺️',
        ]), 'thinking');

      // ── Zoom ─────────────────────────────────────────────────────────
      case 'us.zoom.videomeetings':
        return (_pick([
          'Zoom 📹 Встреча сейчас?',
          'О, зум! Рабочая конференция? 💼',
          'Zoom открыт — фон красивый поставь 😄📹',
          'Зум! Надеюсь не "можете меня слышать?" 😄🎤',
          'Zoom — скажи если нужна помощь перед звонком 📹',
        ]), 'thinking');

      // ── Google Meet ──────────────────────────────────────────────────
      case 'com.google.android.apps.meetings':
        return (_pick([
          'Google Meet 📹 Звонок начинается?',
          'Meet открыт! Встреча сейчас? 💼',
          'Google Meet — удачи на звонке! 📹',
          'О, Meet! Рабочее или учёба? 📹',
          'Google Meet открыт. Камеру включаем? 🎥',
        ]), 'thinking');

      // ── Shazam ───────────────────────────────────────────────────────
      case 'com.shazam.android':
        return (_pick([
          'Shazam! 🎵 Опознаём песню?',
          'О, шазам! Что за трек поймал? 🎶',
          'Shazam открыт — музыку распознаём! 🎵',
          'Шазам! Хорошая песня попалась? 🎵',
          'Shazam — скажи если не нашёл, помогу искать 🎶',
        ]), 'music');

      // ── Google Docs / Drive ──────────────────────────────────────────
      case 'com.google.android.apps.docs':
        return (_pick([
          'Google Docs 📝 Работаем?',
          'Документы. Пишем что-то важное? ✍️',
          'Google Docs открыт! Нужна помощь с текстом? 📝',
          'О, доки! Что пишем? Могу помочь сформулировать 📝',
          'Google Docs — скажи если нужен черновик 📄',
        ]), 'thinking');

      case 'com.google.android.apps.drive':
        return (_pick([
          'Google Drive ☁️ Файлы ищем?',
          'Диск открыт! Что загружаем? ☁️',
          'Google Drive — нашёл нужный файл? 📁',
          'О, Google Drive! Загружаем или скачиваем? ☁️',
          'Гугл диск открыт 📂',
        ]), 'thinking');

      // ── Microsoft Office ─────────────────────────────────────────────
      case 'com.microsoft.office.word':
        return (_pick([
          'Word открыт 📝 Нужна помощь с текстом?',
          'Microsoft Word! Что пишем? ✍️',
          'Word открылся — скажи если нужен шаблон 📄',
          'О, ворд! Работа или учёба? 📝',
          'Microsoft Word — помогу с оформлением если надо ✍️',
        ]), 'thinking');

      case 'com.microsoft.office.excel':
        return (_pick([
          'Excel открыт 📊 Таблицы делаем?',
          'О, эксель! Что считаем? 📊',
          'Microsoft Excel — могу помочь с формулами 📊',
          'Excel открыт. Сложная таблица? Спрашивай 📊',
          'О, Excel! Данные или формулы? 📊',
        ]), 'thinking');

      // ── Google Classroom / Duolingo ──────────────────────────────────
      case 'com.google.android.apps.classroom':
        return (_pick([
          'Google Classroom 📚 Учимся!',
          'О, классрум! Задание сдаём? 📝',
          'Google Classroom открыт — что за предмет? 📚',
          'Учёба! Молодец что занимаешься 📚',
          'Классрум! Дедлайн скоро? 😄📝',
        ]), 'happy');

      case 'com.duolingo':
        return (_pick([
          'Duolingo 🦜 Молодец, учишь язык!',
          'О, дуолинго! Какой язык? 🌍',
          'Duolingo открыт — не нарушай стрик! 🔥',
          'Дуолинго! Уже сколько дней подряд? 🎯',
          'О, Duolingo! Я болею за тебя! 🦜🔥',
        ]), 'happy');

      // ── Камера ───────────────────────────────────────────────────────
      case 'com.android.camera':
      case 'com.android.camera2':
      case 'com.samsung.android.camera':
      case 'com.google.android.GoogleCamera':
        return (_pick([
          'Камера открыта 📸 Что снимаем?',
          'О, фотоаппарат! Что за кадр? 📸',
          'Камера! Скажи если нужен совет по съёмке 📷',
          'Фотографируем! Улыбнись 😄📸',
          'Камера открылась — творческий режим? 📷',
        ]), 'greeting');

      // ── Настройки ────────────────────────────────────────────────────
      case 'com.android.settings':
      case 'com.samsung.android.settings':
        return (_pick([
          'Настройки открыты ⚙️ Что настраиваем?',
          'О, настройки! Что-то не работает? 🔧',
          'Settings — скажи если нужна помощь ⚙️',
          'Настройки! Что ищем? 🔧',
          'Настройки открылись — могу помочь найти нужный пункт ⚙️',
        ]), 'thinking');

      // ── Калькулятор ──────────────────────────────────────────────────
      case 'com.android.calculator2':
      case 'com.samsung.android.calculator':
        return (_pick([
          'Калькулятор 🔢 Что считаем?',
          'О, считаем! Могу помочь с математикой 🧮',
          'Калькулятор открыт — сложные вычисления? 🔢',
          'Считаем! Скажи мне число — посчитаю быстрее 😄',
          'Калькулятор! Что за задача? 🔢',
        ]), 'thinking');

      // ── Яндекс / Chrome / Firefox — молчим ───────────────────────────
      case 'com.android.chrome':
      case 'org.mozilla.firefox':
      case 'com.yandex.browser':
      case 'com.opera.browser':
        return null;

      // ── Gmail / Почта ────────────────────────────────────────────────
      case 'com.google.android.gm':
        return (_pick([
          'Gmail открыт 📧 Важные письма есть?',
          'О, почта! Что там прилетело? 📬',
          'Gmail — проверяем входящие? 📧',
          'Gmail открылся! Спам или что-то важное? 📧',
          'О, Gmail! Не забудь ответить на срочное ✉️',
        ]), 'telegram');

      // ── Игры ─────────────────────────────────────────────────────────
      case 'com.mojang.minecraftpe':
        return (_pick([
          'Майнкрафт! 🏗️ Что строим? Скажи если нужна помощь!',
          'О, Майнкрафт! Выживание или творческий? 🪨',
          'Майнкрафт запущен! Могу помочь с постройками — спрашивай 🏠',
          'Minecraft! Какой биом? Мне интересно 😄🌍',
          'Майнкрафт! Нашёл алмазы уже? 💎',
        ]), 'happy');

      case 'com.pubg.imobile':
      case 'com.tencent.ig':
        return (_pick([
          'PUBG! 🎯 Удачи в матче!',
          'Пубж запущен! Ни пуха! 🎮',
          'PUBG! Нужна помощь — скажи! 🎯',
          'О, PUBG Mobile! Топ-1 сегодня! 🏆',
          'Пубж! Скажи "следи за экраном" если хочешь подсказки 🎯',
        ]), 'happy');

      case 'com.genshin.impact':
      case 'com.miHoYo.GenshinImpact':
        return (_pick([
          'Геншин! ⚔️ Фарм артефактов или сюжет?',
          'Genshin Impact! Надеюсь стамина полная 😄',
          'Геншин открылся! Какой персонаж сейчас? ⚔️',
          'О, Genshin! Баннер хороший? 🌟',
          'Геншин! Не трать примогемы зря 😄💎',
        ]), 'happy');

      case 'com.supercell.brawlstars':
        return (_pick([
          'Brawl Stars! 🥊 Ни пуха в матче!',
          'О, Бравл! Какой боец? 🥊',
          'Brawl Stars запущен! Скоро сезон заканчивается? 🏆',
          'Бравл Старс! Трофеи качаем? 🥊',
          'Brawl Stars! Новый бравлер есть? 🎮',
        ]), 'happy');

      case 'com.supercell.clashofclans':
        return (_pick([
          'Clash of Clans! 🏰 Атакуем или строим?',
          'О, КоК! Ресурсы собираем? 🏰',
          'Clash of Clans — ратуша какого уровня? 🏰',
          'КоК открылся! Клан-война? ⚔️',
          'Clash of Clans! Скажи если нужен совет по атаке 🏰',
        ]), 'happy');

      case 'com.supercell.clashroyale':
        return (_pick([
          'Clash Royale! 👑 На арену!',
          'О, Роял! Какая колода сейчас? 🃏',
          'Clash Royale — лига какая? 👑',
          'КР открылся! Битва за трофеи? ⚔️',
          'Clash Royale! Удачи в матче! 🃏',
        ]), 'happy');

      case 'com.roblox.client':
        return (_pick([
          'Roblox! 🎮 Какая игра сегодня?',
          'О, Роблокс! Что играем? 🎮',
          'Roblox открыт! Со своими или один? 🎮',
          'Роблокс! Там столько игр — что выбрал? 🎮',
          'Roblox! Скажи если нужны советы 🎮',
        ]), 'happy');

      case 'com.vkontakte.android.vkvideo':
      case 'com.vk.video':
        return (_pick([
          'VK Видео! 🎬 Что сегодня смотрим?',
          'Видос от ВК! 🍿 Выбрал что-то интересное?',
          'ВК Видео открыт! Чилл-вечер? 😎',
          'VK Видео — рекомендации хорошие? 🎬',
          'О, ВК видео! Скажи тему — найду что-нибудь интересное 🎬',
        ]), 'youtube');

      // ── VLC / MX Player ──────────────────────────────────────────────
      case 'org.videolan.vlc':
      case 'com.mxtech.videoplayer.ad':
      case 'com.mxtech.videoplayer.pro':
        return (_pick([
          'Видеоплеер запущен 🎬 Приятного просмотра!',
          'О, плеер открыт! Что смотрим? 🎬',
          'Кино начинается! Попкорн готов? 🍿',
          'Видеоплеер! Сериал или фильм? 🎬',
          'VLC открыт! Локальный файл? 🎬',
        ]), 'youtube');

      default:
        if (_isGamePackage(pkg, label)) {
          return (_pick([
            'Игра запущена 🎮 Скажи "помоги в игре" если нужен совет!',
            'Играем! Ни пуха! 🎮 Я рядом если что.',
            'О, игра! Удачи! Слежу за тобой 🎮',
            'Игра открылась! Какая? 🎮',
            'Геймер! 🎮 Скажи если нужна помощь — подскажу!',
          ]), 'happy');
        }
        return null;
    }
  }

  static bool _isGamePackage(String pkg, String label) {
    final keywords = ['game', 'games', 'play', 'clash', 'pubg', 'brawl', 'arena', 'mobile'];
    final lower = pkg.toLowerCase();
    return keywords.any((k) => lower.contains(k));
  }

  static String? _detectGamePkg(String pkg) {
    final p = pkg.toLowerCase();
    if (p.contains('minecraft') || p.contains('mojang')) return 'Minecraft';
    if (p.contains('pubg') || p.contains('tencent.ig')) return 'PUBG';
    if (p.contains('genshin') || p.contains('mihoyo')) return 'Genshin Impact';
    if (p.contains('roblox')) return 'Roblox';
    if (p.contains('brawl')) return 'Brawl Stars';
    if (p.contains('royale')) return 'Clash Royale';
    if (p.contains('clash')) return 'Clash';
    if (_isGamePackage(p, '')) return 'Unknown Game';
    return null;
  }
}
