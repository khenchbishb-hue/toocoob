import 'package:flutter/material.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';

class SavedSessionsPage extends StatefulWidget {
  const SavedSessionsPage({super.key});

  @override
  State<SavedSessionsPage> createState() => _SavedSessionsPageState();
}

class _SavedSessionsPageState extends State<SavedSessionsPage> {
  final SavedGameSessionsRepository _repo = SavedGameSessionsRepository();
  bool _loading = true;
  List<SavedGameSession> _sessions = <SavedGameSession>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await _repo.loadSessions();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  Future<void> _delete(String id) async {
    await _repo.removeById(id);
    await _load();
  }

  String _fmt(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сүүлд тоглосон'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? const Center(child: Text('Хадгалсан тоглолт алга байна.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final s = _sessions[index];
                    return Card(
                      child: ListTile(
                        title: Text(s.gameLabel),
                        subtitle: Text(
                          'Тоглогч: ${s.selectedUserIds.length} | Сүүлд: ${_fmt(s.updatedAt)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Устгах',
                              onPressed: () => _delete(s.id),
                              icon: const Icon(Icons.delete_outline),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(s),
                              child: const Text('Үргэлжлүүлэх'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
