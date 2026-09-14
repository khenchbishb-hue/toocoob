import 'package:flutter/material.dart';
import '../utils/saved_game_sessions_repository.dart';
import '13_card_poker.dart';
import '5_card_texas.dart';
import 'muushig.dart';
import 'buur.dart';
import '108.dart';
import 'xodrox.dart';
import 'nvx_shaxax.dart';
import 'durak.dart';
import '501.dart';
import 'canasta.dart';
import 'kinds_of_game.dart';
Widget? buildSavedGamePage(SavedGameSession saved, {String? currentUserId, bool canManageGames = false, String playingFormat = 'single'}) {
    Widget? page;
    switch (saved.gameKey) {
      case '13_card_poker':
        page = ThirteenCardPokerScreen(
          gameType: '13 МОДНЫ ПОКЕР',
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          currentRegistrarUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'canasta':
        page = CanastaPage(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          playingFormat: playingFormat,
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'durak':
        page = DurakPage(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          playingFormat: playingFormat,
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'xodrox':
        page = HodrokhPage(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'card_texas':
        page = CardTexasPage(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'nvx_shaxax':
        page = NyxShaxaxPage(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'buur':
        page = BuurPage(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'game108':
        page = Game108Page(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'muushig':
        page = MuushigPage(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'game501':
        page = Game501Page(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'multi_format':
        page = KindsOfGamePage(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          playingFormat: 'multi',
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      default: return null;
    }
    return page;
}
