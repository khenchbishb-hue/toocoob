import 'package:flutter/material.dart';
import 'package:toocoob/widgets/unified_game_app_bar.dart';

class CaiXuraaxPage extends StatelessWidget {
  const CaiXuraaxPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: UnifiedGameAppBar(
        title: const Text('Цай хураах'),
      ),
      body: const Center(
        child: Text('Цай хураах'),
      ),
    );
  }
}
