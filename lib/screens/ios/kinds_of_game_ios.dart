import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../13_card_poker.dart';
import '13_card_poker_ios.dart';
import '../5_card_texas.dart';
import '../muushig.dart';
import '../buur.dart';
import '../108.dart';
import '../xodrox.dart';
import '../nvx_shaxax.dart';
import '../durak.dart';
import '../501.dart';
import '../canasta.dart';
import '../cai_xuraax.dart';
import '../other_game.dart';

class KindsOfGamePageIOS extends StatelessWidget {
  const KindsOfGamePageIOS({super.key, required this.selectedUserIds});

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
      'assets/21.jpg',
      'assets/nvx.jpg',
      'assets/durak.jpg',
      'assets/501.jpg',
      'assets/canasta.jpg',
      'assets/daaluu.jpg',
      '',
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Тоглолтын төрөл'),
        elevation: 0,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            label: const Text('Буцах', style: TextStyle(color: Colors.white, fontSize: 14)),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1,
          ),
          itemCount: games.length,
          itemBuilder: (context, index) {
            final hasImage = gameImages[index].isNotEmpty;

            return Container(
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
                  borderRadius: BorderRadius.circular(12),
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
                                  padding: const EdgeInsets.all(8.0),
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
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(6.0),
                                      child: Text(
                                        games[index],
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 14,
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
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(6.0),
                                child: Text(
                                  games[index],
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
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
      ),
    );
  }

  void _navigateToGame(BuildContext context, int index) {
    Widget? page;
    switch (index) {
      case 0:
        // Use iOS version for 13 card poker on iOS, web version otherwise
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
