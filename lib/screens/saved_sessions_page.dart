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
  static const Color _bg = Color(0xFF071325);
  static const Color _panel = Color(0xFF10233F);
  static const Color _text = Color(0xFFEAF2FF);
  static const Color _muted = Color(0xFF9DB2D4);

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

  Future<void> _confirmDelete(SavedGameSession session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Тоглолт устгах уу?'),
        content: Text('${session.gameLabel} тоглолтын хадгалалтыг устгана.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Болих'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Устгах'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await _delete(session.id);
  }

  String _fmt(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final latest = _sessions.isEmpty ? null : _sessions.first;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text(
          'ХАДГАЛСАН ТОГЛОЛТУУД',
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            fontSize: 16,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? const Center(
                  child: Text(
                    'Хадгалсан тоглолт алга байна.',
                    style: TextStyle(color: _muted),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF184A7A), Color(0xFF0F2B4C)],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Сэргээх төв',
                            style: TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Нийт хадгалалт: ${_sessions.length}',
                            style: const TextStyle(color: _text),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            latest == null
                                ? 'Сүүлд шинэчлэгдсэн: -'
                                : 'Сүүлд шинэчлэгдсэн: ${_fmt(latest.updatedAt)}',
                            style: const TextStyle(color: _muted),
                          ),
                        ],
                      ),
                    ),
                    ..._sessions.map(_buildSessionCard),
                  ],
                ),
    );
  }

  Widget _buildSessionCard(SavedGameSession s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x2A7AB8FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.gameLabel,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _chip(
                s.gameKey,
                bg: const Color(0xFF1D4ED8),
                fg: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                'Тоглогч: ${s.selectedUserIds.length}',
                bg: const Color(0xFF163C63),
                fg: _text,
              ),
              _chip(
                'Үүссэн: ${_fmt(s.createdAt)}',
                bg: const Color(0xFF163C63),
                fg: _muted,
              ),
              _chip(
                'Сүүлд: ${_fmt(s.updatedAt)}',
                bg: const Color(0xFF163C63),
                fg: const Color(0xFF86EFAC),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmDelete(s),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Устгах'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFCA5A5),
                    side: const BorderSide(color: Color(0xFF7F1D1D)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(s),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Үргэлжлүүлэх'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
