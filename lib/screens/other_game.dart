import 'package:flutter/material.dart';

class OtherGamePage extends StatelessWidget {
  const OtherGamePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Бусад тоглоом'),
        elevation: 0,
      ),
      body: const Center(
        child: Text('Бусад тоглоом'),
      ),
    );
  }
}
