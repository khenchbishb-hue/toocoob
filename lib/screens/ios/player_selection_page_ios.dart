import 'package:flutter/material.dart';
import 'ios_placeholder.dart';

class PlayerSelectionPageIOS extends StatelessWidget {
  const PlayerSelectionPageIOS({
    super.key,
    this.isAdmin = false,
    this.excludedUserIds = const [],
    this.isAddingMode = false,
    this.currentUserId,
    this.canManageGames = false,
    this.resetOwnedActiveTablesOnOpen = false,
  });

  final bool isAdmin;
  final List<String> excludedUserIds;
  final bool isAddingMode;
  final String? currentUserId;
  final bool canManageGames;
  final bool resetOwnedActiveTablesOnOpen;

  @override
  Widget build(BuildContext context) =>
      const IOSPlaceholderPage(title: 'Тоглогч сонгох');
}
