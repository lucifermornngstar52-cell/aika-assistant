import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/edge_tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

/// Каталог бесплатных системных голосов Google TTS (EdgeTTS мёртв 
/// Microsoft закрыл бесплатный доступ). Экран оформлен карточками
/// в стиле Microsoft Voice Gallery: голоса разделены на мужские
/// и женские, у каждого имя, язык и кнопка прослушивания.

class _VoiceInfo {
 final String name; // системный id голоса
 final String label; // отображаемое имя
 final String locale;
 final String gender; // 'female' | 'male'
 final String desc; // язык/характер
 final String emoji;
 const _VoiceInfo(this.name, this.label, this.locale, this.gender, this.desc, this.emoji);
}

const _curatedVoices = <_VoiceInfo>[
 // ── Женские ──────────────────────────────────────────────────────────
 // ФИКС: ru-ru-x-ruf-local — МУЖСКОЙ голос (проверено на слух), раньше
 // ошибочно числился женским («Ника»). Теперь это Питер.
 _VoiceInfo('ru-ru-x-ruc-local', 'Астра', 'ru-RU', 'female', 'Русский · тёплый', ''),
 _VoiceInfo('en-gb-x-gbs-network', 'Элла', 'en-GB', 'female', 'Английский · Британия', ''),
 _VoiceInfo('en-au-x-auc-network', 'Стелла', 'en-AU', 'female', 'Английский · Австралия', ''),
 // ── Мужские ──────────────────────────────────────────────────────────
 _VoiceInfo('ru-ru-x-ruf-network', 'Дмитрий', 'ru-RU', 'male', 'Русский · уверенный', ''),
 _VoiceInfo('ru-ru-x-ruf-local', 'Питер', 'ru-RU', 'male', 'Русский · низкий', ''),
 _VoiceInfo('ru-ru-x-rud-local', 'Тим', 'ru-RU', 'male', 'Русский · спокойный', ''),
];

class SettingsVoiceScreen extends StatefulWidget {
 const SettingsVoiceScreen({super.key});
 @override
 State<SettingsVoiceScreen> createState() => _SettingsVoiceScreenState();
}

class _SettingsVoiceScreenState extends State<SettingsVoiceScreen> {
 final FlutterTts _tts = FlutterTts();
 double _rate = 0.5, _pitch = 1.0, _volume = 1.0;
 String? _selectedVoice;
 bool _loading = true;
 String? _previewingVoice;

 @override
 void initState() {
 super.initState();
 _load();
 }

 Future<void> _load() async {
 final prefs = await SharedPreferences.getInstance();
 // Только системный Google TTS — бесплатный и всегда доступный.
 await prefs.setString('tts_engine', 'system');
 EdgeTtsService().setTtsEngine('system');
 try { await _tts.setEngine('com.google.android.tts'); } catch (_) {}
 final savedVoice = prefs.getString('tts_voice');
 if (savedVoice!= null && savedVoice.isNotEmpty) {
 _selectedVoice = savedVoice;
 final v = _byId(savedVoice);
 if (v!= null) {
 await _tts.setVoice({'name': v.name, 'locale': v.locale});
 }
 }
 if (mounted) {
 setState(() {
 _rate = prefs.getDouble('tts_rate')?? 0.5;
 _pitch = prefs.getDouble('tts_pitch')?? 1.0;
 _volume = prefs.getDouble('tts_volume')?? 1.0;
 if (_selectedVoice == null) {
 _selectedVoice = _curatedVoices.first.name;
 }
 _loading = false;
 });
 }
 }

 _VoiceInfo? _byId(String id) {
 for (final v in _curatedVoices) {
 if (v.name == id) return v;
 }
 return null;
 }

 /// Прослушать конкретный голос (кнопка ▶ на карточке).
 Future<void> _previewVoice(_VoiceInfo v) async {
 if (_previewingVoice!= null) return;
 setState(() => _previewingVoice = v.name);
 try {
 await _tts.setSpeechRate(_rate);
 await _tts.setPitch(_pitch);
 await _tts.setVolume(_volume);
 await _tts.setVoice({'name': v.name, 'locale': v.locale});
 await _tts.speak('Привет! Так будет звучать голос «${v.label}».');
 } catch (_) {
 } finally {
 if (mounted) setState(() => _previewingVoice = null);
 }
 }

 /// Выбор голоса: тап по карточке — выбираем и сразу сохраняем.
 Future<void> _selectVoice(_VoiceInfo v) async {
 setState(() => _selectedVoice = v.name);
 try {
 await _tts.setVoice({'name': v.name, 'locale': v.locale});
 } catch (_) {}
 final prefs = await SharedPreferences.getInstance();
 await prefs.setString('tts_engine', 'system');
 await prefs.setString('tts_voice', v.name);
 }

 Future<void> _previewSelected() async {
 final v = _byId(_selectedVoice?? '')?? _curatedVoices.first;
 await _previewVoice(v);
 }

 Future<void> _save() async {
 final prefs = await SharedPreferences.getInstance();
 await prefs.setString('tts_engine', 'system');
 await prefs.setDouble('tts_rate', _rate);
 await prefs.setDouble('tts_pitch', _pitch);
 await prefs.setDouble('tts_volume', _volume);
 EdgeTtsService().setTtsEngine('system');
 if (_selectedVoice!= null) {
 await prefs.setString('tts_voice', _selectedVoice!);
 final v = _byId(_selectedVoice!);
 if (v!= null) {
 await _tts.setVoice({'name': v.name, 'locale': v.locale});
 }
 }
 if (mounted) {
 ScaffoldMessenger.of(context).showSnackBar(SnackBar(
 content: const Text('Сохранено'),
 backgroundColor: AikaTheme.neonBlue.withOpacity(0.8),
 behavior: SnackBarBehavior.floating,
));
 Navigator.pop(context);
 }
 }

 @override
 Widget build(BuildContext context) {
 return Scaffold(
 backgroundColor: const Color(0xFF0F0F0F),
 appBar: AppBar(
 backgroundColor: Colors.transparent,
 elevation: 0,
 leading: IconButton(
 icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
 onPressed: () => Navigator.pop(context),
),
 title: const Text('Голоса', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
 actions: [
 TextButton(onPressed: _save,
 child: Text('Сохранить', style: TextStyle(color: AikaTheme.neonBlue, fontSize: 15))),
 ],
),
 body: _loading
? Center(child: CircularProgressIndicator(color: AikaTheme.neonBlue))
: ListView(
 padding: const EdgeInsets.all(20),
 children: [
 _section(' ЖЕНСКИЕ ГОЛОСА'),
 _genderGrid('female'),
 const SizedBox(height: 18),
 _section(' МУЖСКИЕ ГОЛОСА'),
 _genderGrid('male'),
 const SizedBox(height: 18),
 _section('ПАРАМЕТРЫ ГОЛОСА'),
 _card(Column(children: [
 _slider('Скорость речи', _rate, 0.25, 1.5, (v) => setState(() => _rate = v)),
 _slider('Высота голоса', _pitch, 0.5, 2.0, (v) => setState(() => _pitch = v)),
 _slider('Громкость', _volume, 0.0, 1.0, (v) => setState(() => _volume = v)),
 ])),
 const SizedBox(height: 10),
 GestureDetector(
 onTap: _previewSelected,
 child: Container(
 padding: const EdgeInsets.symmetric(vertical: 13),
 alignment: Alignment.center,
 decoration: BoxDecoration(
 color: AikaTheme.neonBlue.withOpacity(0.12),
 borderRadius: BorderRadius.circular(12),
 border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.4)),
),
 child: Text(' Проверить голос',
 style: TextStyle(color: AikaTheme.neonBlue, fontSize: 13, fontWeight: FontWeight.w600)),
),
),
 const SizedBox(height: 24),
 ],
),
);
 }

 Widget _section(String text) => Padding(
 padding: const EdgeInsets.only(bottom: 10, left: 4),
 child: Text(text, style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2)),
);

 /// Сетка карточек голосов (2 в ряд) — как в Microsoft Voice Gallery.
 Widget _genderGrid(String gender) {
 final voices = _curatedVoices.where((v) => v.gender == gender).toList();
 return GridView.count(
 crossAxisCount: 2,
 shrinkWrap: true,
 physics: const NeverScrollableScrollPhysics(),
 mainAxisSpacing: 10,
 crossAxisSpacing: 10,
 childAspectRatio: 1.55,
 children: voices.map(_voiceCard).toList(),
);
 }

 Widget _voiceCard(_VoiceInfo v) {
 final selected = _selectedVoice == v.name;
 final previewing = _previewingVoice == v.name;
 return GestureDetector(
 onTap: () => _selectVoice(v),
 child: Container(
 padding: const EdgeInsets.all(12),
 decoration: BoxDecoration(
 gradient: selected
? LinearGradient(
 begin: Alignment.topLeft,
 end: Alignment.bottomRight,
 colors: [AikaTheme.neonBlue.withOpacity(0.18), Colors.transparent],
)
: null,
 color: selected? null: const Color(0xFF1C1C1E),
 borderRadius: BorderRadius.circular(14),
 border: Border.all(
 color: selected? AikaTheme.neonBlue: Colors.white.withOpacity(0.06),
 width: selected? 1.5: 1,
),
),
 child: Column(
 crossAxisAlignment: CrossAxisAlignment.start,
 children: [
 Row(
 children: [
 Container(
 width: 34,
 height: 34,
 alignment: Alignment.center,
 decoration: BoxDecoration(
 shape: BoxShape.circle,
 color: (v.gender == 'female'? Colors.pinkAccent: Colors.cyanAccent)
.withOpacity(0.15),
),
 child: Text(
 v.label.isNotEmpty? v.label.substring(0, 1): 'Г',
 style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white70),
),
),
 const SizedBox(width: 8),
 Expanded(
 child: Text(v.label,
 overflow: TextOverflow.ellipsis,
 style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
),
 if (selected)
 const Icon(Icons.check_circle, color: AikaTheme.neonBlue, size: 17),
 ],
),
 const Spacer(),
 Text(v.desc, style: const TextStyle(color: Colors.white54, fontSize: 11)),
 const SizedBox(height: 8),
 Align(
 alignment: Alignment.centerRight,
 child: _previewButton(v, previewing),
),
 ],
),
),
);
 }

 Widget _previewButton(_VoiceInfo v, bool previewing) => GestureDetector(
 onTap: () => _previewVoice(v),
 child: Container(
 padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
 decoration: BoxDecoration(
 color: AikaTheme.neonBlue.withOpacity(0.14),
 borderRadius: BorderRadius.circular(20),
 border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.35)),
),
 constraints: const BoxConstraints(minHeight: 26, minWidth: 56),
 alignment: Alignment.center,
 child: previewing
? const SizedBox(
 width: 14, height: 14,
 child: CircularProgressIndicator(strokeWidth: 2, color: AikaTheme.neonBlue))
: const Row(mainAxisSize: MainAxisSize.min, children: [
 Icon(Icons.play_arrow, size: 14, color: AikaTheme.neonBlue),
 SizedBox(width: 3),
 Text('Слушать', style: TextStyle(color: AikaTheme.neonBlue, fontSize: 11)),
 ]),
),
);

 Widget _card(Widget child) => Container(
 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
 decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(14)),
 child: child,
);

 Widget _slider(String label, double val, double min, double max, ValueChanged<double> cb) =>
 Column(children: [
 Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
 Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
 Text(val.toStringAsFixed(2), style: TextStyle(color: AikaTheme.neonBlue, fontSize: 13)),
 ]),
 Slider(value: val, min: min, max: max,
 activeColor: AikaTheme.neonBlue,
 inactiveColor: Colors.white12,
 onChanged: cb),
 const SizedBox(height: 4),
 ]);
}
