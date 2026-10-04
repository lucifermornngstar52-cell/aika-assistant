import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../services/app_alias_service.dart';
import '../services/app_launcher_service.dart';

/// ════════════════════════════════════════════════════════════════════════════
/// AppAliasesScreen кастомные команды приложений.
/// Пара «команда → приложение»: например, «музон» → Яндекс Музыка.
/// После этого «вруби музон» / «открой музон» открывает приложение.
/// ════════════════════════════════════════════════════════════════════════════
class AppAliasesScreen extends StatefulWidget {
 const AppAliasesScreen({super.key});
 @override
 State<AppAliasesScreen> createState() => _AppAliasesScreenState();
}

class _AppAliasesScreenState extends State<AppAliasesScreen> {
 List<AppAlias> _aliases = [];
 List<Map<String, String>> _apps = [];
 bool _loading = true;

 @override
 void initState() {
 super.initState();
 _load();
 }

 Future<void> _load() async {
 final aliases = await AppAliasService.getAll();
 final apps = await AppLauncherService.getInstalledApps();
 if (!mounted) return;
 setState(() {
 _aliases = aliases;
 _apps = apps;
 _loading = false;
 });
 }

 Future<void> _openEditor({AppAlias? existing}) async {
 final cmdCtrl = TextEditingController(text: existing?.cmd?? '');
 String? selectedPkg = existing?.package;
 final searchCtrl = TextEditingController();

 await showModalBottomSheet(
 context: context,
 isScrollControlled: true,
 backgroundColor: AikaTheme.surface,
 shape: const RoundedRectangleBorder(
 borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
),
 builder: (ctx) => StatefulBuilder(
 builder: (ctx, setSheet) => Padding(
 padding: EdgeInsets.only(
 left: 18, right: 18, top: 18,
 bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
),
 child: Column(
 mainAxisSize: MainAxisSize.min,
 crossAxisAlignment: CrossAxisAlignment.start,
 children: [
 Text(existing == null? 'НОВАЯ КОМАНДА': 'ИЗМЕНИТЬ КОМАНДУ',
 style: TextStyle(
 color: AikaTheme.accent, fontSize: 13,
 fontWeight: FontWeight.w700, letterSpacing: 2)),
 const SizedBox(height: 14),
 Text('Слово или фраза',
 style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
 const SizedBox(height: 6),
 TextField(
 controller: cmdCtrl,
 style: const TextStyle(color: Colors.white),
 decoration: InputDecoration(
 hintText: 'например: музон',
 hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
 filled: true,
 fillColor: const Color(0xFF16161C),
 border: OutlineInputBorder(
 borderRadius: BorderRadius.circular(10),
 borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
 focusedBorder: OutlineInputBorder(
 borderRadius: BorderRadius.circular(10),
 borderSide: BorderSide(color: AikaTheme.accent)),
),
),
 const SizedBox(height: 14),
 Text('Приложение',
 style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
 const SizedBox(height: 6),
 TextField(
 controller: searchCtrl,
 style: const TextStyle(color: Colors.white),
 onChanged: (_) => setSheet(() {}),
 decoration: InputDecoration(
 hintText: 'поиск по установленным',
 prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.4), size: 20),
 hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
 filled: true,
 fillColor: const Color(0xFF16161C),
 border: OutlineInputBorder(
 borderRadius: BorderRadius.circular(10),
 borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
),
),
 const SizedBox(height: 10),
 SizedBox(
 height: 260,
 child: ListView(
 children: _filteredApps(searchCtrl.text).map((app) {
 final selected = selectedPkg == app['package'];
 return ListTile(
 dense: true,
 title: Text(app['label']?? '',
 style: TextStyle(
 color: selected? AikaTheme.accent: Colors.white,
 fontSize: 14,
 fontWeight: selected? FontWeight.w600: FontWeight.w400)),
 subtitle: Text(app['package']?? '',
 style: TextStyle(
 color: Colors.white.withOpacity(0.25), fontSize: 10)),
 trailing: selected
? const Icon(Icons.check, size: 18, color: AikaTheme.accent)
: null,
 onTap: () => setSheet(() => selectedPkg = app['package']),
);
 }).toList(),
),
),
 const SizedBox(height: 12),
 SizedBox(
 width: double.infinity,
 child: ElevatedButton(
 style: ElevatedButton.styleFrom(
 backgroundColor: AikaTheme.accent,
 foregroundColor: Colors.white,
 padding: const EdgeInsets.symmetric(vertical: 13),
 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
),
 onPressed: () async {
 final cmd = cmdCtrl.text.trim().toLowerCase();
 if (cmd.isEmpty || selectedPkg == null) return;
 final label = _apps
.firstWhere((a) => a['package'] == selectedPkg)['label']!;
 await AppAliasService.upsert(
 AppAlias(cmd: cmd, package: selectedPkg!, label: label));
 if (ctx.mounted) Navigator.pop(ctx);
 await _load();
 },
 child: const Text('Сохранить'),
),
),
 ],
),
),
),
);
 }

 List<Map<String, String>> _filteredApps(String query) {
 final q = query.toLowerCase().trim();
 final list = _apps.where((a) => (a['label']?? '').isNotEmpty).toList()
..sort((a, b) => (a['label']?? '').toLowerCase().compareTo((b['label']?? '').toLowerCase()));
 if (q.isEmpty) return list;
 return list
.where((a) =>
 (a['label']?? '').toLowerCase().contains(q) ||
 (a['package']?? '').toLowerCase().contains(q))
.toList();
 }

 @override
 Widget build(BuildContext context) {
 return Scaffold(
 appBar: AppBar(
 // Прозрачный: сквозь него виден переливающийся дым SmokeBackground
 backgroundColor: Colors.transparent,
 elevation: 0,
 title: Text('КОМАНДЫ ПРИЛОЖЕНИЙ',
 style: TextStyle(color: AikaTheme.accent, fontWeight: FontWeight.bold, letterSpacing: 2)),
),
 floatingActionButton: FloatingActionButton.extended(
 onPressed: () => _openEditor(),
 backgroundColor: AikaTheme.accent.withOpacity(0.2),
 foregroundColor: Colors.white,
 icon: const Icon(Icons.add, size: 20),
 label: const Text('Добавить'),
),
 body: _loading
? const Center(child: CircularProgressIndicator(color: AikaTheme.accent))
: _aliases.isEmpty
? Center(
 child: Column(
 mainAxisAlignment: MainAxisAlignment.center,
 children: [
 Icon(Icons.bolt_outlined,
 size: 42, color: Colors.white.withOpacity(0.15)),
 const SizedBox(height: 12),
 Text('Команд пока нет',
 style: TextStyle(
 color: Colors.white.withOpacity(0.5),
 fontSize: 15, fontWeight: FontWeight.w600)),
 const SizedBox(height: 6),
 SizedBox(
 width: 280,
 child: Text(
 'Создай пару «команда приложение». '
 'Например: музон → Яндекс Музыка. '
 'После этого «вруби музон» откроет плеер.',
 textAlign: TextAlign.center,
 style: TextStyle(
 color: Colors.white.withOpacity(0.3), fontSize: 12, height: 1.5),
),
),
 ],
),
)
: ListView.builder(
 padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
 itemCount: _aliases.length,
 itemBuilder: (_, i) {
 final a = _aliases[i];
 return Container(
 margin: const EdgeInsets.only(bottom: 10),
 padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
 decoration: BoxDecoration(
 color: AikaTheme.surface.withOpacity(0.6),
 borderRadius: BorderRadius.circular(12),
 border: Border.all(color: Colors.white.withOpacity(0.06)),
),
 child: Row(
 children: [
 Container(
 width: 38,
 height: 38,
 alignment: Alignment.center,
 decoration: BoxDecoration(
 color: AikaTheme.accent.withOpacity(0.12),
 borderRadius: BorderRadius.circular(9),
),
 child: const Icon(Icons.bolt,
 size: 18, color: AikaTheme.accent),
),
 const SizedBox(width: 12),
 Expanded(
 child: Column(
 crossAxisAlignment: CrossAxisAlignment.start,
 children: [
 Text('«${a.cmd}»',
 style: const TextStyle(
 color: Colors.white,
 fontSize: 14, fontWeight: FontWeight.w600)),
 Text(a.label,
 style: TextStyle(
 color: Colors.white.withOpacity(0.4), fontSize: 11)),
 ],
),
),
 IconButton(
 icon: const Icon(Icons.edit_outlined,
 size: 18, color: Colors.white38),
 onPressed: () => _openEditor(existing: a),
),
 IconButton(
 icon: const Icon(Icons.delete_outline,
 size: 18, color: Colors.white38),
 onPressed: () async {
 await AppAliasService.remove(a.cmd);
 await _load();
 },
),
 ],
),
);
 },
),
);
 }
}
