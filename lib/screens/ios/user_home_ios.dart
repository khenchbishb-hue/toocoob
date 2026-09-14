import 'package:flutter/material.dart';
import 'ios_placeholder.dart';

class UserHomeIOS extends StatelessWidget {
  const UserHomeIOS({super.key, required this.userId, required this.username});

  final String userId;
  final String username;

  @override
  Widget build(BuildContext context) => const IOSPlaceholderPage();
}
