import 'dart:math';

/// Мини-игры голосом для Айки
class GameService {
  final _rng = Random();

  // ── Загадай число ─────────────────────────────────────────────
  int? _secretNumber;
  int? _guessMin;
  int? _guessMax;
  int _guessAttempts = 0;
  bool _guessActive = false;

  // ── Игра в слова ──────────────────────────────────────────────
  bool _wordsActive = false;
  String _lastWord = '';
  final List<String> _usedWords = [];

  bool get isGameActive => _guessActive || _wordsActive;

  /// Проверяем — это игровая фраза?
  String? tryHandleGame(String text) {
    final t = text.toLowerCase().trim();

    // Запуск "загадай число"
    if (!isGameActive &&
        (t.contains('загадай число') || t.contains('загадай цифру') ||
         t.contains('игра числа') || t.contains('сыграем в числа'))) {
      return _startGuessGame();
    }

    // Запуск "игра в слова"
    if (!isGameActive &&
        (t.contains('сыграем в слова') || t.contains('игра в слова') ||
         t.contains('давай в слова') || t.contains('играем в слова'))) {
      return _startWordsGame();
    }

    // Ход в игре угадай число
    if (_guessActive) {
      final num = _extractNumber(t);
      if (num != null) return _makeGuess(num);
      if (t.contains('стоп') || t.contains('хватит') || t.contains('сдаюсь')) {
        return _stopGame();
      }
      return 'Называй число от $_guessMin до $_guessMax!';
    }

    // Ход в игре слова
    if (_wordsActive) {
      if (t.contains('стоп') || t.contains('хватит') || t.contains('сдаюсь')) {
        return _stopGame();
      }
      return _playWord(t.trim());
    }

    return null;
  }

  String _startGuessGame() {
    _guessMin = 1;
    _guessMax = 100;
    _secretNumber = _rng.nextInt(100) + 1;
    _guessAttempts = 0;
    _guessActive = true;
    return 'Загадала число от 1 до 100! Угадывай 🎯';
  }

  String _makeGuess(int n) {
    if (_secretNumber == null) return 'Игра не начата';
    _guessAttempts++;
    if (n == _secretNumber) {
      _guessActive = false;
      final secret = _secretNumber!;
      _secretNumber = null;
      return 'Правильно! Загадала $secret, ты угадал за $_guessAttempts попыток! 🎉';
    } else if (n < _secretNumber!) {
      _guessMax = n - 1 < _guessMax! ? _guessMax : null;
      return 'Больше! (попытка $_guessAttempts)';
    } else {
      return 'Меньше! (попытка $_guessAttempts)';
    }
  }

  String _startWordsGame() {
    _wordsActive = true;
    _usedWords.clear();
    const startWords = ['апельсин', 'арбуз', 'аист', 'акула'];
    _lastWord = startWords[_rng.nextInt(startWords.length)];
    _usedWords.add(_lastWord);
    return 'Играем в слова! Я начну: $_lastWord\nТвоё слово должно начинаться на "${_lastWord[_lastWord.length - 1].toUpperCase()}"';
  }

  String _playWord(String word) {
    // Убираем лишние символы
    final w = word.replaceAll(RegExp(r'[^а-яёa-z\s]', caseSensitive: false), '').trim();
    if (w.isEmpty) return 'Называй слово!';

    final expectedLetter = _lastWord[_lastWord.length - 1];
    if (!w.startsWith(expectedLetter)) {
      return 'Слово должно начинаться на "${expectedLetter.toUpperCase()}"! Попробуй ещё раз.';
    }
    if (_usedWords.contains(w)) {
      return 'Слово "$w" уже было! Придумай другое.';
    }

    _usedWords.add(w);
    _lastWord = w;

    // Айка придумывает ответ
    final aikaWord = _findWordStartingWith(w[w.length - 1]);
    if (aikaWord == null) {
      _wordsActive = false;
      return 'Не могу придумать слово на "${w[w.length - 1].toUpperCase()}"... Ты победил! 🏆';
    }
    _usedWords.add(aikaWord);
    _lastWord = aikaWord;
    return 'Хорошо! Моё слово: $aikaWord\nТвоё слово на "${aikaWord[aikaWord.length - 1].toUpperCase()}"';
  }

  String? _findWordStartingWith(String letter) {
    final words = {
      'а': ['апельсин','астра','акула','автобус','арфа'],
      'б': ['банан','белка','буря','бобёр','берег'],
      'в': ['волк','ворона','вилка','весна','вода'],
      'г': ['гора','гроза','груша','горилла','гитара'],
      'д': ['дерево','дельфин','дождь','дорога','дыня'],
      'е': ['ель','ежевика','езда'],
      'ё': ['ёж','ёлка'],
      'ж': ['жираф','жук','жара','журавль'],
      'з': ['заяц','зебра','зима','звезда','земля'],
      'и': ['иволга','игла','икра','ирис'],
      'й': ['йогурт'],
      'к': ['кот','кит','клён','корень','крот'],
      'л': ['лиса','лев','луна','лимон','лось'],
      'м': ['медведь','мышь','море','меч','мята'],
      'н': ['норка','ночь','небо','нектар','нерпа'],
      'о': ['орёл','овца','остров','облако','оса'],
      'п': ['пчела','паук','пальма','персик','пума'],
      'р': ['рысь','роза','река','рыба','радуга'],
      'с': ['слон','сова','снег','сосна','сурок'],
      'т': ['тигр','туча','тюлень','тропик','трава'],
      'у': ['утка','улитка','уголь','уж'],
      'ф': ['фиалка','феникс','форель'],
      'х': ['хомяк','хвост','хурма','хорёк'],
      'ц': ['цапля','цветок','цунами'],
      'ч': ['чайка','черепаха','чернила','чиж'],
      'ш': ['шакал','шторм','шмель','шиповник'],
      'щ': ['щука','щегол','щавель'],
      'э': ['эму','экватор','эхо'],
      'ю': ['юла','юг','юрта'],
      'я': ['ягуар','ярость','яблоко','ягода'],
    };

    final candidates = words[letter] ?? [];
    final available = candidates.where((w) => !_usedWords.contains(w)).toList();
    if (available.isEmpty) return null;
    return available[_rng.nextInt(available.length)];
  }

  String _stopGame() {
    _guessActive = false;
    _wordsActive = false;
    _secretNumber = null;
    _usedWords.clear();
    return 'Игра остановлена. Было весело! 😄';
  }

  int? _extractNumber(String text) {
    // Пробуем как цифры
    final match = RegExp(r'\d+').firstMatch(text);
    if (match != null) return int.tryParse(match.group(0)!);
    // Пробуем словами (базово)
    const nums = {
      'один':1,'два':2,'три':3,'четыре':4,'пять':5,
      'шесть':6,'семь':7,'восемь':8,'девять':9,'десять':10,
      'двадцать':20,'тридцать':30,'сорок':40,'пятьдесят':50,
      'шестьдесят':60,'семьдесят':70,'восемьдесят':80,'девяносто':90,'сто':100,
    };
    for (final e in nums.entries) {
      if (text.contains(e.key)) return e.value;
    }
    return null;
  }
}
