import 'package:flutter/material.dart';
import '../utils/saved_game_sessions_repository.dart';
import '../utils/saved_game_summary.dart';

/// null cancels selection, an empty string starts fresh, otherwise a saved ID.
Future<String?> showSavedGamePrompt(BuildContext context,
    List<SavedGameSession> sessions) => showDialog<String>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Дуусаагүй хадгалсан тоглолт байна'),
    content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Эдгээр тоглогчийн өмнөх тоглолтыг үргэлжлүүлэх үү, шинээр тоглох уу?'),
        for (final session in sessions) Card(child: Padding(
          padding: const EdgeInsets.all(12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(session.gameLabel, style: Theme.of(context).textTheme.titleMedium),
              Text('Сүүлд хадгалсан: ${_date(session.updatedAt)}'),
              const SizedBox(height: 8),
              Text(savedGameSummary(session)),
              const SizedBox(height: 8),
              FilledButton(onPressed: () => Navigator.pop(context, session.id),
                child: const Text('Үргэлжлүүлэх')),
            ],
          ),
        )),
      ],
    ))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Буцах')),
      TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Шинээр тоглох')),
    ],
  ),
);

String _date(DateTime value) {
  final d = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
