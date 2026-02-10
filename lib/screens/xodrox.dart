import 'package:flutter/material.dart';

class HodrokhPage extends StatelessWidget {
  const HodrokhPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ходрох'),
        elevation: 0,
      ),
      body: const Center(
        child: Text('Ходрох'),
      ),
    );
  }
}
