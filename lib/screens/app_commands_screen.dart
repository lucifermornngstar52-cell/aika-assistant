import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/game_music_service.dart';
import '../theme/app_theme.dart';

class AppCommandsScreen extends StatefulWidget {
  const AppCommandsScreen({Key? key}) : super(key: key);

  @override
  State<AppCommandsScreen> createState() => _AppCommandsScreenState();
}

class _AppCommandsScreenState extends State<AppCommandsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // ── Voice → App tab ─────────────────────────────
  static const _platform = MethodChannel('com.aika.assistant/apps');
  List<Map<String, String>> _installedApps = [];
  List<Map<String, String>> _filteredApps = [];
  bool _appsLoading = true;
  final _searchController = TextEditingController();
  final _commandController = TextEditingController();
  Map<String, String> _voiceCommands = {}; // trigger -> packageName
  Map<String, String> _appNames = {};       // packageName -> label

  // ── Game Music tab ──────────────────────────────
  bool _gameMusicEnabled = false;
  String _selectedPlayer = 'com.spotify.music';
  List<String> _userGamePkgs = [];
  final _customGameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadVoiceCommands();
    _loadInstalledApps();
    _loadGameMusicSettings();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    _commandController.dispose();
    _customGameController.dispose();
    super.dispose();
  }

  // ─── Voice commands ─────────────────────────────────────────────

  Future<void> _loadVoiceCommands() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('app_voice_commands') ?? '{}';
    setState(() => _voiceCommands = Map<String, String>.from(json.decode(raw)));
  }

  Future<void> _saveVoiceCommands() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_voice_commands', json.encode(_voiceCommands));
  }

  Future<void> _loadInstalledApps() async {
    try {
      final result = await _platform.invokeMethod<List>('getInstalledApps');
      if (result != null) {
        final apps = result.map<Map<String, String>>((e) => {
          'package': e['package']?.toString() ?? '',
          'label': e['label']?.toString() ?? '',
        }).where((a) => a['package']!.isNotEmpty).toList();
        apps.sort((a, b) => (a['label'] ?? '').compareTo(b['label'] ?? ''));
        setState(() {
          _installedApps = apps;
          _filteredApps = apps;
          _appsLoading = false;
          for (final a in apps) {
            _appNames[a['package']!] = a['label']!;
          }
        });
      }
    } catch (_) {
      // Fallback: use known apps list
      final fallback = [
        {'package': 'com.spotify.music', 'label': 'Spotify'},
        {'package': 'org.telegram.messenger', 'label': 'Telegram'},
        {'package': 'com.whatsapp', 'label': 'WhatsApp'},
        {'package': 'com.google.android.youtube', 'label': 'YouTube'},
        {'package': 'com.supercell.brawlstars', 'label': 'Brawl Stars'},
        {'package': 'com.instagram.android', 'label': 'Instagram'},
        {'package': 'com.vkontakte.android', 'label': 'VK'},
        {'package': 'com.google.android.apps.maps', 'label': 'Maps'},
      ];
      setState(() {
        _installedApps = fallback;
        _filteredApps = fallback;
        _appsLoading = false;
        for (final a in fallback) {
          _appNames[a['package']!] = a['label']!;
        }
      });
    }
  }

  void _filterApps(String query) {
    setState(() {
      _filteredApps = _installedApps
          .where((a) => (a['label'] ?? '').toLowerCase().contains(query.toLowerCase()) ||
              (a['package'] ?? '').toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  void _showAddCommandDialog(Map<String, String> app) {
    _commandController.clear();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AikaTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Команда для ${app['label']}',
          style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Что сказать Айке чтобы открыть это приложение?',
              style: TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: _commandController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'например: "открой игру" или "бравл"',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                filled: true,
                fillColor: AikaTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.3)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final cmd = _commandController.text.trim().toLowerCase();
              if (cmd.isNotEmpty) {
                setState(() => _voiceCommands[cmd] = app['package']!);
                _saveVoiceCommands();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('✓ Теперь скажи "$cmd" чтобы открыть ${app['label']}'),
                  backgroundColor: const Color(0xFF4CAF50),
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AikaTheme.neonBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Сохранить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ─── Game Music ──────────────────────────────────────────────────

  Future<void> _loadGameMusicSettings() async {
    final enabled = await GameMusicService.isEnabled();
    final player = await GameMusicService.getPlayer();
    final games = await GameMusicService.getUserGames();
    setState(() {
      _gameMusicEnabled = enabled;
      _selectedPlayer = player;
      _userGamePkgs = games;
    });
  }

  // ─── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AikaTheme.background,
      appBar: AppBar(
        backgroundColor: AikaTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('⚡ Команды приложений',
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AikaTheme.neonBlue,
          labelColor: AikaTheme.neonBlue,
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(text: '🎙 Голос → Приложение'),
            Tab(text: '🎮 Музыка в играх'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_buildVoiceTab(), _buildGameMusicTab()],
      ),
    );
  }

  Widget _buildVoiceTab() {
    return Column(
      children: [
        // Existing commands
        if (_voiceCommands.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AikaTheme.neonBlue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Твои команды:', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._voiceCommands.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('"${e.key}" → ${_appNames[e.value] ?? e.value}',
                          style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() => _voiceCommands.remove(e.key));
                          _saveVoiceCommands();
                        },
                        child: const Icon(Icons.close, color: Colors.white30, size: 16),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ],

        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: _filterApps,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Поиск приложения...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
              filled: true,
              fillColor: AikaTheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),

        // App list
        Expanded(
          child: _appsLoading
              ? const Center(child: CircularProgressIndicator(color: AikaTheme.neonBlue))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filteredApps.length,
                  itemBuilder: (ctx, i) {
                    final app = _filteredApps[i];
                    final pkg = app['package']!;
                    final label = app['label']!;
                    final hasCommand = _voiceCommands.containsValue(pkg);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      leading: CircleAvatar(
                        backgroundColor: AikaTheme.neonBlue.withOpacity(0.12),
                        child: Text(label.isNotEmpty ? label[0].toUpperCase() : '?',
                          style: const TextStyle(color: AikaTheme.neonBlue, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: hasCommand
                          ? Text(
                              _voiceCommands.entries
                                  .where((e) => e.value == pkg)
                                  .map((e) => '"${e.key}"')
                                  .join(', '),
                              style: TextStyle(color: AikaTheme.neonBlue.withOpacity(0.8), fontSize: 11),
                            )
                          : null,
                      trailing: IconButton(
                        icon: Icon(
                          hasCommand ? Icons.edit_outlined : Icons.add_circle_outline,
                          color: hasCommand ? AikaTheme.neonBlue : Colors.white38,
                          size: 22,
                        ),
                        onPressed: () => _showAddCommandDialog(app),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildGameMusicTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Enable toggle
          _card(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Автомузыка в играх', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text('Музыка запускается автоматически', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
                Switch(
                  value: _gameMusicEnabled,
                  onChanged: (v) async {
                    await GameMusicService.setEnabled(v);
                    setState(() => _gameMusicEnabled = v);
                  },
                  activeColor: AikaTheme.neonBlue,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Player selection
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Музыкальный плеер', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ...GameMusicService.availablePlayers.entries.map((e) => RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: e.key,
                  groupValue: _selectedPlayer,
                  activeColor: AikaTheme.neonBlue,
                  title: Text(e.value, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  onChanged: (v) async {
                    if (v != null) {
                      await GameMusicService.setPlayer(v);
                      setState(() => _selectedPlayer = v);
                    }
                  },
                )),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Known games
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Игры (встроенный список)', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Эти игры определяются автоматически:', style: TextStyle(color: Colors.white38, fontSize: 11)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: GameMusicService.knownGames.values.map((name) => Chip(
                    label: Text(name, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    backgroundColor: AikaTheme.neonBlue.withOpacity(0.1),
                    side: BorderSide(color: AikaTheme.neonBlue.withOpacity(0.2)),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Custom game packages
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Добавить свою игру', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Введи package name (найди в настройках приложения)', style: TextStyle(color: Colors.white38, fontSize: 11)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customGameController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'com.example.mygame',
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                          filled: true,
                          fillColor: AikaTheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final pkg = _customGameController.text.trim();
                        if (pkg.isNotEmpty) {
                          await GameMusicService.addGame(pkg);
                          _customGameController.clear();
                          setState(() => _userGamePkgs = [..._userGamePkgs, pkg]);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AikaTheme.neonBlue,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 18),
                    ),
                  ],
                ),
                if (_userGamePkgs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ..._userGamePkgs.map((pkg) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(pkg, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.white30, size: 18),
                      onPressed: () async {
                        await GameMusicService.removeGame(pkg);
                        setState(() => _userGamePkgs.remove(pkg));
                      },
                    ),
                  )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AikaTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AikaTheme.neonBlue.withOpacity(0.15)),
      ),
      child: child,
    );
  }
}
