import 'package:flutter/material.dart';
import 'ios_placeholder.dart';

class KindsOfGamePageIOS extends StatelessWidget {
  const KindsOfGamePageIOS({
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
      const IOSPlaceholderPage(title: 'Тоглоом сонгох');
}
