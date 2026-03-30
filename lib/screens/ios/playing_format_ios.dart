import 'package:flutter/material.dart';
import 'kinds_of_game_ios.dart';

class PlayingFormatPageIOS extends StatefulWidget {
  const PlayingFormatPageIOS({
    super.key,
    required this.selectedUserIds,
    this.currentUserId,
    this.canManageGames = false,
  });

  final List<String> selectedUserIds;
  final String? currentUserId;
  final bool canManageGames;

  @override
  State<PlayingFormatPageIOS> createState() => _PlayingFormatPageIOSState();
}

class _PlayingFormatPageIOSState extends State<PlayingFormatPageIOS> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Буцах',
          icon: Image.asset(
            'assets/buttons/back.png',
            width: 24,
            height: 24,
            fit: BoxFit.contain,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Тоглолтын хэлбэр'),
        elevation: 0,
        actions: [
          TextButton.icon(
            icon: Image.asset(
              'assets/buttons/back.png',
              width: 18,
              height: 18,
              fit: BoxFit.contain,
            ),
            label: const Text(
              'Буцах',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Expanded(
                child: _buildFormatButton(
                  context,
                  'Олон\nтөрөлт',
                  Colors.deepPurple,
                  'assets/all kinds.jpg',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _buildFormatButton(
                  context,
                  'Нэг төрлөөр\nтойрох',
                  Colors.blue,
                  'assets/a kind.jpg',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _buildFormatButton(
                  context,
                  'Галзуу\nганц',
                  Colors.deepOrange,
                  'assets/one time.jpg',
                ),
              ),
            ],
          ),
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
                builder: (context) => KindsOfGamePageIOS(
                  selectedUserIds: widget.selectedUserIds,
                  currentUserId: widget.currentUserId,
                  canManageGames: widget.canManageGames,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                if (imagePath != null)
                  Expanded(
                    flex: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
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
                        topRight: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.black.withOpacity(0.3),
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
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
