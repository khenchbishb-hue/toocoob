import 'package:flutter/material.dart';
import 'package:toocoob/widgets/unified_game_app_bar.dart';

class OtherGamePage extends StatelessWidget {
  const OtherGamePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: UnifiedGameAppBar(
        title: const Text('Бусад тоглоом'),
      ),
      body: const Center(
        child: Text('Бусад тоглоом'),
      ),
    );
  }
}
