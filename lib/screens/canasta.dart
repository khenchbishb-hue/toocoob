import 'package:flutter/material.dart';

class CanastaPage extends StatelessWidget {
  const CanastaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Канастер'),
        elevation: 0,
      ),
      body: const Center(
        child: Text('Канастер'),
      ),
    );
  }
}
