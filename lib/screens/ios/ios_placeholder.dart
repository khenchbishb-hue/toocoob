import 'package:flutter/material.dart';

/// Temporary landing page while the native iOS flow is rebuilt from scratch.
class IOSPlaceholderPage extends StatelessWidget {
  const IOSPlaceholderPage({super.key, this.title = 'ТооцооБ'});

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(
          child: Text(
            'iOS хувилбар бэлтгэгдэж байна.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}
