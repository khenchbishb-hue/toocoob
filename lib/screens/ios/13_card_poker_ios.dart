import 'package:flutter/material.dart';
import 'ios_placeholder.dart';

class CardPokerPageIOS extends StatelessWidget {
  const CardPokerPageIOS({super.key, required this.selectedUserIds});

  final List<String> selectedUserIds;

  @override
  Widget build(BuildContext context) =>
      const IOSPlaceholderPage(title: '13 модны покер');
}
