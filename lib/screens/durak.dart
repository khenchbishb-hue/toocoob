import 'package:flutter/material.dart';

class DurakPage extends StatelessWidget {
  const DurakPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Дурак'),
        elevation: 0,
      ),
      body: const Center(
        child: Text('Дурак'),
      ),
    );
  }
}
