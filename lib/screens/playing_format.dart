import 'package:flutter/material.dart';
import 'kinds_of_game.dart';

class PlayingFormatPage extends StatefulWidget {
  const PlayingFormatPage({
    super.key,
    required this.selectedUserIds,
    this.currentUserId,
    this.canManageGames = false,
  });

  final List<String> selectedUserIds;
  final String? currentUserId;
  final bool canManageGames;

  @override
  State<PlayingFormatPage> createState() => _PlayingFormatPageState();
}

class _PlayingFormatPageState extends State<PlayingFormatPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Буцах',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Image.asset(
            'assets/buttons/back.png',
            width: 24,
            height: 24,
            fit: BoxFit.contain,
          ),
        ),
        title: const Text('Тоглолтын хэлбэр'),
        elevation: 0,
      ),
      body: Row(
        children: [
          Expanded(
            child: _buildFormatButton(
              context,
              'Олон\nтөрөлт',
              Colors.deepPurple,
              'assets/all kinds.jpg',
              format: 'multi',
            ),
          ),
          Expanded(
            child: _buildFormatButton(
              context,
              'Нэг төрлөөр\nтойрох',
              Colors.blue,
              'assets/a kind.jpg',
              format: 'single',
            ),
          ),
          Expanded(
            child: _buildFormatButton(
              context,
              'Галзуу\nганц',
              Colors.deepOrange,
              'assets/one time.jpg',
              format: 'crazy',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatButton(
    BuildContext context,
    String title,
    Color color,
    String? imagePath, {
    required String format,
  }) {
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
                  selectedUserIds: widget.selectedUserIds,
                  playingFormat: format,
                  currentUserId: widget.currentUserId,
                  canManageGames: widget.canManageGames,
                ),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                if (imagePath != null)
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Image.asset(
                        imagePath,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                Expanded(
                  flex: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.3),
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
