import 'package:flutter/foundation.dart';

import 'overlay_service.dart';
import 'aika_log_service.dart';

/// Майнкрафт-рецепты: офлайн-база рецептов и советов по выживанию.
///
/// Работает без интернета и без AI: любой вопрос «как скрафтить X»
/// закрывается мгновенно из локальной базы. Если оверлей включён —
/// рецепт показывается карточкой прямо поверх игры, чтобы не сворачивать
/// Майнкрафт.
class MinecraftRecipeService {
  MinecraftRecipeService._();
  static final MinecraftRecipeService instance = MinecraftRecipeService._();

  /// Пытается обработать текст как команду Майнкрафт-пилота.
  /// Возвращает ответ или null (не команда → дальше обычный AI).
  Future<String?> tryHandle(String text) async {
    final t = _norm(text);

    // «закрой рецепт / убери подсказку»
    if ((t.contains('закрой') || t.contains('убери') || t.contains('скрой')) &&
        (t.contains('рецепт') || t.contains('подсказк') || t.contains('карточку'))) {
      await OverlayService().hideTip();
      return 'Закрыла карточку ✓';
    }

    // Чек-лист первого дня / выживания
    if ((t.contains('первый день') || t.contains('выживани') || t.contains('чеклист')) &&
        (t.contains('майнкрафт') || t.contains('minecraft') || t.contains('начат'))) {
      final tips = _checklist;
      _maybeShowTip('Первый день в Майнкрафте', tips.first, seconds: 60);
      return tips.join('\n');
    }

    // Рецепт: «как скрафтить X», «рецепт X», «что нужно для X»...
    final wanted = _extractItem(text);
    if (wanted != null) {
      final recipe = _findRecipe(wanted);
      AikaLogService.log('recipes', 'запрос «$wanted» → ${recipe?.title ?? 'нет в базе'}');
      if (recipe != null) {
        final answer = _formatRecipe(recipe);
        _maybeShowTip(recipe.title, answer, seconds: 45);
        return answer;
      }
      // Рецепта в базе нет — вернём null, пусть отвечает AI,
      // но подскажем, что пилот знает.
      return null;
    }
    return null;
  }

  // ── База рецептов ─────────────────────────────────────────────────

  static const _tools = <_McRecipe>[
    _McRecipe(
      title: 'Деревянная кирка',
      keywords: ['кирка', 'кирку', 'кирки', 'деревянная кирка', 'деревянную кирку'],
      ingredients: ['3 доски', '2 палки'],
      steps: ['Открой верстак', '3 доски в верхний ряд', '2 палки по центру под ними'],
    ),
    _McRecipe(
      title: 'Каменная кирка',
      keywords: ['каменная кирка', 'каменную кирку'],
      ingredients: ['3 булыжника', '2 палки'],
      steps: ['На верстаке: 3 булыжника в верхний ряд', '2 палки по центру под ними'],
    ),
    _McRecipe(
      title: 'Железная кирка',
      keywords: ['железная кирка', 'железную кирку'],
      ingredients: ['3 железных слитка', '2 палки'],
      steps: ['Железную руду переплавь в печке', '3 слитка в верхний ряд верстака', '2 палки под ними'],
    ),
    _McRecipe(
      title: 'Алмазная кирка',
      keywords: ['алмазная кирка', 'алмазную кирку'],
      ingredients: ['3 алмаза', '2 палки'],
      steps: ['Алмазы добывай железной киркой+', '3 алмаза в верхний ряд верстака', '2 палки под ними'],
    ),
    _McRecipe(
      title: 'Меч (любой)',
      keywords: ['меч', 'меча', 'мечу', 'мечи'],
      ingredients: ['2 единицы материала (доски/булыжник/железо/алмаз/незерит)', '1 палка'],
      steps: ['На верстаке: 2 материала в столбик', 'Палка под ними'],
    ),
    _McRecipe(
      title: 'Топор (любой)',
      keywords: ['топор', 'топора', 'топору'],
      ingredients: ['3 материала', '2 палки'],
      steps: ['Материалы: 2 сверху, 1 сбоку от верхней', '2 палки по центру'],
    ),
    _McRecipe(
      title: 'Лопата (любая)',
      keywords: ['лопата', 'лопату', 'лопаты', 'лопатка'],
      ingredients: ['1 материал', '2 палки'],
      steps: ['1 материал сверху', '2 палки под ним столбиком'],
    ),
    _McRecipe(
      title: 'Мотыга (любая)',
      keywords: ['мотыга', 'мотыгу', 'мотыги', 'сапка'],
      ingredients: ['2 материала', '2 палки'],
      steps: ['2 материала в верхнем ряду', '2 палки под левым из них'],
    ),
  ];

  static const _base = <_McRecipe>[
    _McRecipe(
      title: 'Верстак',
      keywords: ['верстак', 'верстака', 'крафт', 'крафта', 'crafting'],
      ingredients: ['4 доски (любого дерева)'],
      steps: ['Сделай доски из бревна', '4 доски квадратом 2×2 в инвентаре'],
    ),
    _McRecipe(
      title: 'Палки',
      keywords: ['палк', 'палки', 'палку', 'stick', 'палочка'],
      ingredients: ['2 доски'],
      steps: ['2 доски столбиком в инвентаре → 4 палки'],
    ),
    _McRecipe(
      title: 'Печка',
      keywords: ['печк', 'печка', 'печь', 'furnace'],
      ingredients: ['8 булыжника'],
      steps: ['На верстаке: булыжник по кругу', 'Центр пустой'],
    ),
    _McRecipe(
      title: 'Сундук',
      keywords: ['сундук', 'сундука', 'сундучок', 'chest'],
      ingredients: ['8 досок'],
      steps: ['На верстаке: доски по кругу', 'Центр пустой'],
    ),
    _McRecipe(
      title: 'Кровать',
      keywords: ['кроват', 'кровать', 'bed', 'спат'],
      ingredients: ['3 доски', '3 блока шерсти (один цвет)'],
      steps: ['Шерсть с овец: ножницами или рукой', 'Доски в нижний ряд, шерсть в верхний'],
    ),
    _McRecipe(
      title: 'Факелы',
      keywords: ['факел', 'факелы', 'факелов', 'torch', 'свет'],
      ingredients: ['1 палка', '1 уголь'],
      steps: ['Уголь: каменная кирка по угольной руде', 'Уголь над палкой → 4 факела'],
    ),
    _McRecipe(
      title: 'Дверь',
      keywords: ['двер', 'дверь', 'двери', 'door'],
      ingredients: ['6 досок'],
      steps: ['6 досок: 2 столбика по 3 высотой'],
    ),
    _McRecipe(
      title: 'Лестница',
      keywords: ['лестниц', 'лестница', 'лестницу'],
      ingredients: ['7 палок'],
      steps: ['Палки в форме лестницы: по диагонали, углы пустые'],
    ),
    _McRecipe(
      title: 'Забор',
      keywords: ['забор', 'забора', 'fence'],
      ingredients: ['4 доски', '2 палки'],
      steps: ['Палки в средний ряд', 'Доски сверху и снизу'],
    ),
    _McRecipe(
      title: 'Лодка',
      keywords: ['лодк', 'лодка', 'лодку', 'boat'],
      ingredients: ['5 досок'],
      steps: ['5 досок: нижний ряд + боковые в среднем ряду', 'Вершина пустая'],
    ),
    _McRecipe(
      title: 'Хлеб',
      keywords: ['хлеб', 'хлеба', 'bread'],
      ingredients: ['3 пшеницы'],
      steps: ['Пшеницу с грядок (семена из травы)', '3 пшеницы в ряд на верстаке'],
    ),
    _McRecipe(
      title: 'Стол зачарований',
      keywords: ['стол зачаровани', 'зачаровани', 'enchanted', 'энчант', 'зачаровать'],
      ingredients: ['1 обсидиан (×4)', '2 алмаза', '1 книга'],
      steps: ['Обсидиан — алмазной киркой по лаве+воде', 'Книга: 3 бумаги + 1 кожа', 'Алмазы по бокам, книга сверху, обсидиан снизу'],
    ),
    _McRecipe(
      title: 'Наковальня',
      keywords: ['наковальн', 'наковальня', 'anvil'],
      ingredients: ['31 железный слиток (3 блока + 4 слитка)'],
      steps: ['3 железных блока в верхний ряд', 'Слиток по центру + 2 по бокам снизу'],
    ),
    _McRecipe(
      title: 'Зельеварка (варочная стойка)',
      keywords: ['зельеварк', 'варочная', 'зель', 'алхими', 'potion'],
      ingredients: ['1 бушующий стержень', '3 булыжника'],
      steps: ['Стержень у ифритов в Незере', 'Стержень сверху, булыжник снизу по кругу'],
    ),
    _McRecipe(
      title: 'Глаз Эндера',
      keywords: ['глаз эндера', 'эндер', 'крепость', 'эндер глаз', 'ender'],
      ingredients: ['эндер-жемчуг', 'огненный порошок'],
      steps: ['Жемчуг с эндерменов ночью', 'Порошок из стержня ифрита', 'Смешай на верстаке'],
    ),
    _McRecipe(
      title: 'Портал в Незер',
      keywords: ['незер', 'ад', 'портал', 'nether'],
      ingredients: ['10 обсидиана', 'огниво (кремень + железо)'],
      steps: ['Рамка 4×5 из обсидиана (углы не нужны)', 'Подожги огнивом низ рамки', 'Стой в фиолетовом — телепорт!'],
    ),
    _McRecipe(
      title: 'Огниво',
      keywords: ['огнив', 'огниво', 'кремень', 'flint'],
      ingredients: ['кремень', 'железный слиток'],
      steps: ['Кремень копай гравий (шанс 10%)', 'Кремень + железо на верстаке'],
    ),
    _McRecipe(
      title: 'Компас',
      keywords: ['компас', 'compass'],
      ingredients: ['4 железных слитка', '1 красная пыль'],
      steps: ['Пыль в центр, слитки по кругу', 'Указывает на точку спавна'],
    ),
    _McRecipe(
      title: 'Карта',
      keywords: ['карт', 'карта', 'map'],
      ingredients: ['8 бумаги', '1 компас'],
      steps: ['Бумага из тростника', 'Компас в центр, бумага по кругу'],
    ),
    _McRecipe(
      title: 'Удочка',
      keywords: ['удочк', 'удочка', 'рыб', 'fishing'],
      ingredients: ['3 палки', '2 нити'],
      steps: ['Нить с пауков', '2 палки по диагонали + 1 сверху, нити слева'],
    ),
    _McRecipe(
      title: 'Вагонетка',
      keywords: ['вагонетк', 'вагонетка', 'minecart', 'рельс'],
      ingredients: ['5 железных слитков'],
      steps: ['Слитки буквой U (низ + бока)'],
    ),
    _McRecipe(
      title: 'Золотое яблоко',
      keywords: ['золотое яблоко', 'golden apple', 'золотое'],
      ingredients: ['1 яблоко', '8 золотых слитков'],
      steps: ['Яблоки с дубов', 'Яблоко в центр, золото по кругу'],
    ),
    _McRecipe(
      title: 'Якорь возрождения',
      keywords: ['якорь', 'respawn', 'спавн в незере'],
      ingredients: ['6 плачущего обсидиана', '3 светокамня'],
      steps: ['Плачущий обсидиан: синий кри́стал + обсидиан', 'Верх/низ — светокамень, середина — обсидиан', 'Заряжается светокамнем'],
    ),
    _McRecipe(
      title: 'Маяк',
      keywords: ['маяк', 'beacon'],
      ingredients: ['3 обсидиана', '5 стекла', '1 звезда Незера'],
      steps: ['Звезда — с Иссушителя', 'Стекло сверху, звезда в центр, обсидиан снизу', 'Поставь на пирамиду из железа/золота/алмазов'],
    ),
    _McRecipe(
      title: 'Котёл',
      keywords: ['котёл', 'котле', 'cauldron'],
      ingredients: ['7 железных слитков'],
      steps: ['Слитки буквой U на верстаке'],
    ),
  ];

  static const _checklist = <String>[
    '⛏️ Первый день в Майнкрафте:',
    '1. Дерево: 3-5 брёвен',
    '2. Верстак + деревянная кирка',
    '3. Камень: 20+ булыжника → каменные инструменты',
    '4. Еда: убей 2-3 коровы/овцы',
    '5. Уголь для факелов (или charcoal из брёвен в печке)',
    '6. Дом: землянка или дупло в холме, дверь + факелы',
    '7. Кровать из шерсти — иначе фантомы!',
    '8. Не копай прямо вниз и прямо вверх 🙃',
  ];

  // ── Поиск и парсинг ────────────────────────────────────────────────

  static List<_McRecipe> get allRecipes => [..._base, ..._tools];

  static String _norm(String s) =>
      s.toLowerCase().replaceAll('ё', 'е').trim();

  static String? _extractItem(String text) {
    final t = _norm(text);
    const triggers = [
      'как скрафтить', 'как скрафтить', 'крафт ', 'рецепт', 'что нужно для',
      'из чего сделать', 'как сделать', 'как получить', 'как построить в майнкрафте',
    ];
    for (final trig in triggers) {
      final i = t.indexOf(trig);
      if (i >= 0) {
        var item = t.substring(i + trig.length).trim();
        // хвостовые вопросы отрезаем
        for (final stop in [' в майнкрафте', ' в minecraft', '?', '!']) {
          item = item.replaceAll(stop, '');
        }
        item = item.trim();
        if (item.length >= 3) return item;
      }
    }
    return null;
  }

  static _McRecipe? _findRecipe(String wanted) {
    final w = _norm(wanted);
    var best = <_McRecipe?>[null, ];
    var bestScore = 0;
    for (final r in allRecipes) {
      for (final kw in r.keywords) {
        final k = _norm(kw);
        if (w.contains(k) || k.contains(w)) {
          // длинное совпадение = точнее
          final score = k.length;
          if (score > bestScore) {
            bestScore = score;
            best[0] = r;
          }
        }
      }
    }
    return best[0];
  }

  static String _formatRecipe(_McRecipe r) {
    final sb = StringBuffer();
    sb.write('⛏️ ${r.title}\n');
    sb.write('Ингредиенты:\n');
    for (final i in r.ingredients) {
      sb.write('• $i\n');
    }
    sb.write('Как сделать:\n');
    for (var i = 0; i < r.steps.length; i++) {
      sb.write('${i + 1}. ${r.steps[i]}\n');
    }
    return sb.toString().trim();
  }

  Future<void> _maybeShowTip(String title, String body, {int seconds = 45}) async {
    try {
      final overlay = OverlayService();
      if (!await overlay.hasPermission()) return;
      final plain = body
          .replaceAll('<b>', '')
          .replaceAll('</b>', '')
          .replaceAll('\n', ' | ');
      await overlay.showTip(title, plain, seconds: seconds);
    } catch (e) {
      debugPrint('[McRecipe] tip failed: $e');
    }
  }
}

class _McRecipe {
  final String title;
  final List<String> keywords;
  final List<String> ingredients;
  final List<String> steps;
  const _McRecipe({
    required this.title,
    required this.keywords,
    required this.ingredients,
    required this.steps,
  });
}
