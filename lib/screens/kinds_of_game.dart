import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '13_card_poker.dart';
import 'ios/13_card_poker_ios.dart';
import '5_card_texas.dart';
import 'muushig.dart';
import 'buur.dart';
import '108.dart';
import 'xodrox.dart';
import 'nvx_shaxax.dart';
import 'durak.dart';
import '501.dart';
import 'canasta.dart';
import 'cai_xuraax.dart';
import 'other_game.dart';

class KindsOfGamePage extends StatelessWidget {
  const KindsOfGamePage({super.key, required this.selectedUserIds});

  final List<String> selectedUserIds;

  @override
  Widget build(BuildContext context) {
    final List<String> games = [
      '13 модны\nпокер',
      '5 модны\nТехас',
      'Муушиг',
      'Буур',
      '108',
      'Ходрох',
      'Нүх\nшахах',
      'Дурак',
      '501',
      'Канастер',
      'Цай\nхураах',
      '...'
    ];

    final List<String> gameImages = [
      'assets/13.jpg',
      'assets/5.jpg',
      'assets/muushig.jpg',
      'assets/buur.jpg',
      'assets/108.jpg',
      'assets/21.jpg', // Ходрох
      'assets/nvx.jpg',
      'assets/durak.jpg',
      'assets/501.jpg',
      'assets/canasta.jpg',
      'assets/daaluu.jpg', // Цай хураах
      '', // ... товчинд зураг байхгүй
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Тоглолтын төрөл'),
        elevation: 0,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1,
        ),
        itemCount: games.length,
        itemBuilder: (context, index) {
          final hasImage = gameImages[index].isNotEmpty;

          return Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.deepPurple,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  _navigateToGame(context, index);
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: hasImage
                      ? Column(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Padding(
                                padding: const EdgeInsets.all(6.0),
                                child: Image.asset(
                                  gameImages[index],
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.3),
                                      Colors.black.withOpacity(0.7),
                                    ],
                                  ),
                                ),
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Padding(
                                    padding: const EdgeInsets.all(6.0),
                                    child: Text(
                                      games[index],
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.3),
                                Colors.black.withOpacity(0.7),
                              ],
                            ),
                          ),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.all(6.0),
                              child: Text(
                                games[index],
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _navigateToGame(BuildContext context, int index) {
    Widget? page;
    switch (index) {
      case 0:
        page = !kIsWeb && Platform.isIOS
            ? CardPokerPageIOS(selectedUserIds: selectedUserIds)
            : CardPokerPage(selectedUserIds: selectedUserIds);
        break;
      case 1:
        page = const CardTexasPage();
        break;
      case 2:
        page = const MuushigPage();
        break;
      case 3:
        page = const BuurPage();
        break;
      case 4:
        page = const Game108Page();
        break;
      case 5:
        page = const HodrokhPage();
        break;
      case 6:
        page = const NyxShaxaxPage();
        break;
      case 7:
        page = const DurakPage();
        break;
      case 8:
        page = const Game501Page();
        break;
      case 9:
        page = const CanastaPage();
        break;
      case 10:
        page = const CaiXuraaxPage();
        break;
      case 11:
        page = const OtherGamePage();
        break;
    }

    if (page != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => page!),
      );
    }
  }
}
