import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/ai_service.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});
  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _geminiCtrl   = TextEditingController();
  final _groqCtrl     = TextEditingController();
  final _claudeCtrl   = TextEditingController();
  final _deepseekCtrl = TextEditingController();
  final _perplexCtrl  = TextEditingController();
  final _braveCtrl    = TextEditingController();

  String _selectedModel = 'auto';
  bool _webSearch = true;
  bool _loading = true;
  int _maxTokens = 1024;

  final _models = {
    'auto':        '🧠 Авто (умный роутинг)',
    'gemini_pro':  '✨ Gemini 2.5 Flash Pro',
    'gemini_flash':'🚀 Gemini 2.0 Flash (быстрый)',
    'groq':        '⚡ Groq gpt-oss-120b (бесплатно)',
    'claude':      '🤖 Claude Haiku (Anthropic)',
    'deepseek':    '🧬 Deepseek Chat (дёшево)',
    'perplexity':  '🌐 Perplexity (AI + веб)',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
            _geminiCtrl.text   = prefs.getString('gemini_key')    ?? '';
      _groqCtrl.text     = prefs.getString('groq_key')      ?? '';
      _claudeCtrl.text   = prefs.getString('claude_key')    ?? '';
      _deepseekCtrl.text = prefs.getString('deepseek_key')  ?? '';
      _perplexCtrl.text  = prefs.getString('perplexity_key')?? '';
      _braveCtrl.text    = prefs.getString('brave_key')     ?? '';
      _selectedModel     = prefs.getString('ai_model')      ?? 'auto';
      _webSearch         = prefs.getBool('ai_web_search')   ?? true;
      _maxTokens         = prefs.getInt('ai_max_tokens')    ?? 1024;
      _loading = false;
    });

    // Применяем сохранённые ключи в сервис
    _applyKeys();
  }

  void _applyKeys() {
    AiService.setGeminiKey(_geminiCtrl.text.trim());
    AiService.setGroqKey(_groqCtrl.text.trim());
    AiService.setClaudeKey(_claudeCtrl.text.trim());
    AiService.setDeepseekKey(_deepseekCtrl.text.trim());
    AiService.setPerplexityKey(_perplexCtrl.text.trim());
    AiService.setPreferredModel(_selectedModel);
    AiService.setWebSearch(_webSearch);
    AiService.setMaxTokens(_maxTokens);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_key',    _geminiCtrl.text.trim());
    await prefs.setString('groq_key',      _groqCtrl.text.trim());
    await prefs.setString('claude_key',    _claudeCtrl.text.trim());
    await prefs.setString('deepseek_key',  _deepseekCtrl.text.trim());
    await prefs.setString('perplexity_key',_perplexCtrl.text.trim());
    await prefs.setString('brave_key',     _braveCtrl.text.trim());
    await prefs.setString('ai_model',      _selectedModel);
    await prefs.setBool('ai_web_search',   _webSearch);
    await prefs.setInt('ai_max_tokens',    _maxTokens);

    _applyKeys();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('✅ AI настройки сохранены'),
        backgroundColor: AikaTheme.neonBlue.withOpacity(0.85),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AikaTheme.background,
        body: Center(child: CircularProgressIndicator(color: AikaTheme.neonBlue)),
      );
    }

    // Статус подключения
    final connected = AiService.connectedServices;

    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: AikaTheme.neonBlue, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('AI ДВИГАТЕЛИ', style: TextStyle(
          color: AikaTheme.neonBlue, fontSize: 16,
          fontWeight: FontWeight.bold, letterSpacing: 2,
        )),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _save,
            child: Text('Сохранить', style: TextStyle(color: AikaTheme.neonBlue, fontSize: 15)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ── Статус подключений ─────────────────────────────────────
          _sectionHeader('📡 СТАТУС'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AikaTheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: connected.entries.map((e) => _statusChip(e.key, e.value)).toList(),
            ),
          ),

          const SizedBox(height: 16),

          // ── Модель ────────────────────────────────────────────────
          _sectionHeader('🧠 МОДЕЛЬ'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AikaTheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: DropdownButton<String>(
              value: _selectedModel,
              isExpanded: true,
              dropdownColor: AikaTheme.surface,
              underline: const SizedBox(),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              items: _models.entries.map((e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, style: const TextStyle(color: Colors.white)),
              )).toList(),
              onChanged: (v) => setState(() => _selectedModel = v!),
            ),
          ),

          const SizedBox(height: 8),
          _infoCard(
            '🧠 Авто-роутинг',
            'Умный выбор модели:\n'
            '• Быстрые команды → Groq (мгновенно)\n'
            '• Сложные вопросы → GPT-4o\n'
            '• Актуальные данные → Perplexity\n'
            '• Творчество → Claude',
          ),

          const SizedBox(height: 16),

          // ── Веб-поиск ─────────────────────────────────────────────
          _sectionHeader('🌐 ВЕБ-ПОИСК'),
          _switchTile(
            'Веб-поиск (DuckDuckGo)',
            'AI получает актуальные данные из интернета\n(погода, новости, курсы — без API ключа)',
            _webSearch,
            (v) => setState(() => _webSearch = v),
          ),

          const SizedBox(height: 16),

          // ── Токены ─────────────────────────────────────────────────
          _sectionHeader('📏 ДЛИНА ОТВЕТА'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AikaTheme.surface, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Максимум токенов: $_maxTokens',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                Slider(
                  value: _maxTokens.toDouble(),
                  min: 256, max: 4096,
                  divisions: 15,
                  activeColor: AikaTheme.neonBlue,
                  inactiveColor: Colors.white12,
                  label: '$_maxTokens',
                  onChanged: (v) => setState(() => _maxTokens = v.round()),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('256 (быстро)', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    Text('4096 (подробно)', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── API Ключи ─────────────────────────────────────────────
          _sectionHeader('🔑 API КЛЮЧИ'),

          _keyCard('Google Gemini', _geminiCtrl, 'AIza...', '🟢 бесплатно: до 1500 запросов/день\naistudio.google.com/apikey'),
          _keyCard('Groq (Llama 3.3-70B)', _groqCtrl, 'gsk_...', '🟢 БЕСПЛАТНО: 30 req/мин, нет лимита/день\nconsole.groq.com'),
          _keyCard('Anthropic Claude', _claudeCtrl, 'sk-ant-...', '🟡 бесплатно: есть trial\nconsole.anthropic.com'),
          _keyCard('Deepseek', _deepseekCtrl, 'sk-...', '🟢 очень дёшево: \$0.01 за 1M токенов\nplatform.deepseek.com'),
          _keyCard('Perplexity (AI+Web)', _perplexCtrl, 'pplx-...', '🟡 бесплатно: trial\nperplexity.ai/settings/api'),
          _keyCard('Brave Search', _braveCtrl, 'BSA...', '🟢 бесплатно: 2000 запросов/месяц\napi.search.brave.com'),

          const SizedBox(height: 24),

          _infoCard('💡 Рекомендация',
            'Для максимального результата:\n'
            '1. Groq — получить бесплатно (console.groq.com)\n'
            '2. Gemini — бесплатно в Google AI Studio\n\n'
            'Groq — основная модель (бесплатно, быстро, gpt-oss-120b)'),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(title, style: TextStyle(
      color: AikaTheme.neonBlue.withOpacity(0.8),
      fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2,
    )),
  );

  Widget _statusChip(String name, bool connected) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: connected ? Colors.green.withOpacity(0.15) : Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: connected ? Colors.green.withOpacity(0.5) : Colors.white12,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(connected ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 10, color: connected ? Colors.green : Colors.white30),
        const SizedBox(width: 4),
        Text(name, style: TextStyle(
          color: connected ? Colors.green : Colors.white30,
          fontSize: 11, fontWeight: FontWeight.w500,
        )),
      ],
    ),
  );

  Widget _keyCard(String label, TextEditingController ctrl, String hint, String info) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AikaTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600,
          )),
          const SizedBox(height: 4),
          Text(info, style: const TextStyle(
            color: Colors.white38, fontSize: 10, height: 1.5,
          )),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            obscureText: true,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste, color: Colors.white24, size: 16),
                onPressed: () {}, // paste hint
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (ctrl.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 12),
                  const SizedBox(width: 4),
                  Text('Ключ установлен', style: const TextStyle(
                    color: Colors.green, fontSize: 11,
                  )),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _switchTile(String title, String subtitle, bool value, Function(bool) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AikaTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.4)),
            ]),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AikaTheme.neonBlue,
          ),
        ],
      ),
    );
  }

  Widget _infoCard(String title, String text) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AikaTheme.neonBlue.withOpacity(0.07),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(
          color: AikaTheme.neonBlue, fontSize: 12, fontWeight: FontWeight.bold,
        )),
        const SizedBox(height: 6),
        Text(text, style: const TextStyle(color: Colors.white60, fontSize: 11, height: 1.5)),
      ],
    ),
  );
}
