import 'package:flutter/material.dart';
import 'kinds_of_game.dart';

class PlayingFormatPage extends StatelessWidget {
  const PlayingFormatPage({super.key, required this.selectedUserIds});

  final List<String> selectedUserIds;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Тоглолтын хэлбэр'),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(
              child: _buildFormatButton(
                context,
                'Олон төрөлт',
                Colors.deepPurple,
                'assets/all kinds.jpg',
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _buildFormatButton(
                context,
                'Нэг төрлөөр тойрох',
                Colors.blue,
                'assets/a kind.jpg',
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _buildFormatButton(
                context,
                'Галзуу ганц',
                Colors.deepOrange,
                'assets/one time.jpg',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatButton(
    BuildContext context,
    String title,
    Color color,
    String? imagePath,
  ) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => KindsOfGamePage(
                  selectedUserIds: selectedUserIds,
                ),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                if (imagePath != null)
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Image.asset(
                        imagePath,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                Expanded(
                  flex: 3,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 50,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
