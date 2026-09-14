import 'package:flutter/material.dart';
import 'ios_placeholder.dart';

class PlayingFormatPageIOS extends StatelessWidget {
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
  Widget build(BuildContext context) =>
      const IOSPlaceholderPage(title: 'Тоглолтын хэлбэр');
}
