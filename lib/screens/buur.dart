import 'package:flutter/material.dart';

class BuurPage extends StatelessWidget {
  const BuurPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Буур'),
        elevation: 0,
      ),
      body: const Center(
        child: Text('Буур'),
      ),
    );
  }
}
