import 'dart:async';

import 'package:flutter/material.dart';
import 'package:toocoob/screens/13_card_poker.dart';
import 'package:toocoob/screens/108.dart';
import 'package:toocoob/screens/5_card_texas.dart';
import 'package:toocoob/screens/501.dart';
import 'package:toocoob/screens/buur.dart';
import 'package:toocoob/screens/canasta.dart';
import 'package:toocoob/screens/cai_xuraax.dart';
import 'package:toocoob/screens/durak.dart';
import 'package:toocoob/screens/muushig.dart';
import 'package:toocoob/screens/nvx_shaxax.dart';
import 'package:toocoob/screens/other_game.dart';
import 'package:toocoob/screens/player_selection_page.dart';
import 'package:toocoob/screens/playing_format.dart';
import 'package:toocoob/screens/xodrox.dart';
import 'package:toocoob/utils/active_tables_repository.dart';
import 'package:toocoob/utils/active_table_route_registry.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';
import 'package:toocoob/widgets/active_table_route_scope.dart';

class UnifiedGameAppBar extends StatelessWidget implements PreferredSizeWidget {
  UnifiedGameAppBar({
    super.key,
    required this.title,
    this.onBack,
    this.onAddPlayer,
    this.onRemovePlayer,
    this.onSave,
    this.onStatistics,
    this.onReport,
    this.onPrint,
    this.onSettings,
    this.onExit,
    this.backgroundColor = const Color(0xFFE7DDD4),
    this.foregroundColor = Colors.black87,
    this.extraActions = const <Widget>[],
    this.currentUserId,
    this.canManageGames = false,
    this.showGlobalTableBar = true,
    this.preferCustomExitAction = false,
  });

  final Widget title;
  final VoidCallback? onBack;
  final VoidCallback? onAddPlayer;
  final VoidCallback? onRemovePlayer;
  final FutureOr<void> Function()? onSave;
  final VoidCallback? onStatistics;
  final VoidCallback? onReport;
  final VoidCallback? onPrint;
  final VoidCallback? onSettings;
  final FutureOr<void> Function()? onExit;
  final Color backgroundColor;
  final Color foregroundColor;
  final List<Widget> extraActions;
  final String? currentUserId;
  final bool canManageGames;
  final bool showGlobalTableBar;
  final bool preferCustomExitAction;
  final SavedGameSessionsRepository _savedSessionsRepo =
      SavedGameSessionsRepository();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      leading: _assetAction(
        context: context,
        assetPath: 'assets/buttons/back.png',
        tooltip: 'Буцах',
        onPressed: () => _handleBackPressed(context),
      ),
      title: _buildTitleWithTableControls(),
      actions: [
        _assetAction(
          context: context,
          assetPath: 'assets/buttons/remove user.png',
          tooltip: 'Тоглогч хасах',
          onPressed: onRemovePlayer,
          unavailableMessage: 'Тоглогч хасах үйлдэл бэлэн биш байна.',
        ),
        _assetAction(
          context: context,
          assetPath: 'assets/buttons/add user.webp',
          tooltip: 'Тоглогч нэмэх',
          onPressed: onAddPlayer,
          unavailableMessage: 'Тоглогч нэмэх үйлдэл бэлэн биш байна.',
        ),
        _AnimatedSaveButton(onSave: onSave),
        _assetAction(
          context: context,
          assetPath: 'assets/buttons/stats.png',
          tooltip: 'Статистик',
          onPressed: onStatistics,
          unavailableMessage: 'Статистик одоогоор бэлэн биш байна.',
        ),
        _assetAction(
          context: context,
          assetPath: 'assets/buttons/report.png',
          tooltip: 'Тайлан',
          onPressed: onReport,
          unavailableMessage: 'Тайлан одоогоор бэлэн биш байна.',
        ),
        _assetAction(
          context: context,
          assetPath: 'assets/buttons/print.png',
          tooltip: 'Хэвлэх',
          onPressed: onPrint,
          unavailableMessage: 'Хэвлэх үйлдэл одоогоор бэлэн биш байна.',
        ),
        _assetAction(
          context: context,
          assetPath: 'assets/buttons/settings.png',
          tooltip: 'Тохиргоо',
          onPressed: onSettings,
          unavailableMessage: 'Тохиргоо одоогоор бэлэн биш байна.',
        ),
        _assetAction(
          context: context,
          assetPath: 'assets/buttons/exit.webp',
          tooltip: 'Гарах',
          onPressed: () => _handleExitPressed(context),
        ),
        ...extraActions,
      ],
    );
  }

  Widget _buildTitleWithTableControls() {
    if (!showGlobalTableBar) return title;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          title,
          const SizedBox(width: 8),
          _GlobalTableBar(
            currentUserId: currentUserId,
            canManageGames: canManageGames,
            reopenTableRoute: _reopenTableRoute,
            persistCurrentTableState: _persistCurrentTableState,
          ),
        ],
      ),
    );
  }

  Future<void> _handleExitPressed(BuildContext context) async {
    if (preferCustomExitAction && onExit != null) {
      await Future.sync(onExit!);
      if (!context.mounted) return;
      await _releaseCurrentActiveTableLock(context);
      return;
    }

    final ownerUserId = currentUserId?.trim();
    final repo = ActiveTablesRepository();

    // If no current owner context is available, fall back to existing behavior.
    if (ownerUserId == null || ownerUserId.isEmpty) {
      if (onExit != null) {
        await Future.sync(onExit!);
        if (!context.mounted) return;
        await _releaseCurrentActiveTableLock(context);
      } else if (context.mounted) {
        Navigator.of(context).maybePop();
      }
      return;
    }

    final ownedTables =
        await repo.fetchActiveTableSummaries(ownerUserId: ownerUserId);

    if (!context.mounted) return;

    if (ownedTables.length <= 1) {
      await repo.releaseOwnedActiveTableLocks(ownerUserId);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true)
          .popUntil((route) => route.isFirst);
      return;
    }

    final action = await showDialog<_ExitAction>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Идэвхтэй ширээнүүд байна'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Эдгээр ширээ идэвхтэй байна:'),
              const SizedBox(height: 8),
              for (final table in ownedTables)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child:
                      Text('• Ширээ ${table.tableNumber}: ${table.gameName}'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ExitAction.close),
              child: const Text('Хаах'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ExitAction.save),
              child: const Text('Хадгалах'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ExitAction.back),
              child: const Text('Буцах'),
            ),
          ],
        );
      },
    );

    if (action == null || !context.mounted) return;

    if (action == _ExitAction.back) {
      await _persistCurrentTableState(context);
      final firstOpen =
          ownedTables.map((table) => 'active-table:${table.id}').firstWhere(
                ActiveTableRouteRegistry.contains,
                orElse: () => '',
              );
      if (firstOpen.isNotEmpty) {
        Navigator.of(context)
            .popUntil((route) => route.settings.name == firstOpen);
      } else {
        await _reopenTableRoute(context, ownedTables.first.id);
      }
      return;
    }

    if (action == _ExitAction.save && onSave != null) {
      await Future.sync(onSave!);
      if (!context.mounted) return;
    }

    await repo.releaseOwnedActiveTableLocks(ownerUserId);
    if (!context.mounted) return;

    Navigator.of(context, rootNavigator: true)
        .popUntil((route) => route.isFirst);
  }

  Future<void> _handleBackPressed(BuildContext context) async {
    await _persistCurrentTableState(context);
    if (!context.mounted) return;

    if (onBack != null) {
      onBack!.call();
      return;
    }

    Navigator.of(context).maybePop();
  }

  String? _currentActiveTableLockId(BuildContext context) {
    final currentRouteName = ModalRoute.of(context)?.settings.name;
    if (currentRouteName == null ||
        !currentRouteName.startsWith('active-table:')) {
      return null;
    }

    final lockId = currentRouteName.substring('active-table:'.length).trim();
    return lockId.isEmpty ? null : lockId;
  }

  Future<void> _releaseCurrentActiveTableLock(BuildContext context) async {
    final lockId = _currentActiveTableLockId(context);
    if (lockId == null) return;

    try {
      await ActiveTablesRepository().releaseActiveTableLock(lockId);
    } catch (_) {
      // Best-effort lock cleanup.
    }
  }

  Future<void> _persistCurrentTableState(BuildContext context) async {
    final currentRouteName = ModalRoute.of(context)?.settings.name;
    if (currentRouteName == null ||
        !currentRouteName.startsWith('active-table:')) {
      return;
    }

    final lockId = currentRouteName.substring('active-table:'.length).trim();
    if (lockId.isEmpty) return;

    if (onSave != null) {
      try {
        await Future.sync(onSave!);
      } catch (_) {
        // Local save failures should not block table navigation.
      }
      if (!context.mounted) return;
    }

    final repo = ActiveTablesRepository();
    ActiveTableDetails? details;
    try {
      details = await repo
          .fetchActiveTableDetails(lockId)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      details = null;
    }
    if (!context.mounted || details == null) return;

    SavedGameSession? latest;
    try {
      // Try to find by exact player set first.
      latest = await _savedSessionsRepo
          .findLatestByGameAndPlayers(
            gameKey: details.gameKey,
            selectedUserIds: details.playerUserIds,
          )
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      latest = null;
    }

    // If player-based lookup fails, fallback to finding most recent session for this game.
    if (latest == null) {
      try {
        final allSessions = await _savedSessionsRepo.loadSessions();
        final gameKey = details.gameKey;
        latest = allSessions.firstWhere(
          (s) => s.gameKey == gameKey,
          orElse: () => null as dynamic,
        ) as SavedGameSession?;
      } catch (_) {
        latest = null;
      }
    }

    final orderedUserIds = _resolveOrderedUserIdsForTable(
      latest,
      fallback: details.playerUserIds,
    );

    try {
      await repo
          .updateActiveTableState(
            lockId,
            savedSessionId: latest?.id,
            playerUserIds: orderedUserIds,
          )
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Remote state sync failures are tolerated to keep switching responsive.
    }
  }

  List<String> _resolveOrderedUserIdsForTable(
    SavedGameSession? latest, {
    required List<String> fallback,
  }) {
    if (latest == null) {
      return List<String>.from(fallback);
    }

    final payload = latest.payload;

    // Order-centric payload used by poker/muushig-like screens.
    final orderedUserNames =
        _readStringList(payload['orderedUserNames'], unique: true);
    if (orderedUserNames.isNotEmpty) {
      return orderedUserNames;
    }

    // Seat-centric payload used by 108-like screens.
    final orderedSeatIds =
        _readUserIdsFromSeatMaps(payload['orderedSeats'], unique: true);
    if (orderedSeatIds.isNotEmpty) {
      return orderedSeatIds;
    }

    // Seat-centric payload used by 501-like screens.
    final seatIds = _readUserIdsFromSeatMaps(payload['seats'], unique: true);
    if (seatIds.isNotEmpty) {
      return seatIds;
    }

    // Fallback to session players and keep original table order as last resort.
    final sessionSelectedIds =
        _readStringList(latest.selectedUserIds, unique: true);
    if (sessionSelectedIds.isNotEmpty) {
      return sessionSelectedIds;
    }

    return List<String>.from(fallback);
  }

  List<String> _readStringList(dynamic source, {bool unique = false}) {
    final list = (source as List<dynamic>? ?? const <dynamic>[])
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    if (!unique) return list;

    final seen = <String>{};
    final ordered = <String>[];
    for (final value in list) {
      if (seen.add(value)) {
        ordered.add(value);
      }
    }
    return ordered;
  }

  List<String> _readUserIdsFromSeatMaps(dynamic seats, {bool unique = false}) {
    final rows = (seats as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);

    final ids = rows
        .map((row) => (row['userId'] as String? ?? '').trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    if (!unique) return ids;

    final seen = <String>{};
    final ordered = <String>[];
    for (final id in ids) {
      if (seen.add(id)) {
        ordered.add(id);
      }
    }
    return ordered;
  }

  Future<bool> _reopenTableRoute(BuildContext context, String lockId) async {
    final repo = ActiveTablesRepository();
    final details = await repo.fetchActiveTableDetails(lockId);
    if (!context.mounted || details == null || details.status != 'active') {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Энэ ширээ идэвхгүй болсон байна.')),
      );
      return false;
    }

    final page = _buildPageForActiveTable(details);
    if (page == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Энэ ширээний тоглоомыг дахин нээх боломжгүй байна.'),
        ),
      );
      return false;
    }

    final routeName = 'active-table:${details.id}';
    await Navigator.push(
      context,
      MaterialPageRoute(
        settings: RouteSettings(name: routeName),
        builder: (_) => ActiveTableRouteScope(
          routeName: routeName,
          child: page,
        ),
      ),
    );
    return true;
  }

  Widget? _buildPageForActiveTable(ActiveTableDetails details) {
    final ids = List<String>.from(details.playerUserIds);
    final isMulti = details.playingFormat == 'multi';
    final initialSavedSessionId = details.savedSessionId;
    switch (details.gameKey) {
      case '13_card_poker':
        return ThirteenCardPokerScreen(
          gameType: '13 МОДНЫ ПОКЕР',
          selectedUserIds: ids,
          currentRegistrarUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: initialSavedSessionId,
          autoReturnOnWinner: isMulti,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
          promptInitialPlayerOrder: false,
        );
      case 'card_texas':
        return CardTexasPage(
          selectedUserIds: ids,
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: initialSavedSessionId,
          autoReturnOnWinner: isMulti,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
        );
      case 'muushig':
        return MuushigPage(
          selectedUserIds: ids,
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: initialSavedSessionId,
          autoReturnOnWinner: isMulti,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
        );
      case 'buur':
        return BuurPage(
          selectedUserIds: ids,
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: initialSavedSessionId,
          autoReturnOnWinner: isMulti,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
        );
      case 'game108':
        return Game108Page(
          selectedUserIds: ids,
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: initialSavedSessionId,
          autoReturnOnWinner: isMulti,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
        );
      case 'xodrox':
        return HodrokhPage(
          selectedUserIds: ids,
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: initialSavedSessionId,
          autoReturnOnWinner: isMulti,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
        );
      case 'nvx_shaxax':
        return NyxShaxaxPage(
          selectedUserIds: ids,
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: initialSavedSessionId,
          autoReturnOnWinner: isMulti,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
        );
      case 'durak':
        return DurakPage(
          selectedUserIds: ids,
          playingFormat: details.playingFormat,
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: initialSavedSessionId,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
        );
      case 'game501':
        return Game501Page(
          selectedUserIds: ids,
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: initialSavedSessionId,
          autoReturnOnWinner: isMulti,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
        );
      case 'canasta':
        return CanastaPage(
          selectedUserIds: ids,
          playingFormat: details.playingFormat,
          currentUserId: currentUserId,
          canManageGames: canManageGames,
          initialSavedSessionId: initialSavedSessionId,
        );
      case 'cai_xuraax':
        return CaiXuraaxPage();
      case 'other_game':
        return OtherGamePage();
      default:
        return null;
    }
  }

  Widget _assetAction({
    required BuildContext context,
    required String assetPath,
    required String tooltip,
    FutureOr<void> Function()? onPressed,
    String? unavailableMessage,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: () async {
        if (onPressed != null) {
          await Future.sync(onPressed);
          return;
        }

        if (!context.mounted) return;

        {
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.showSnackBar(
            SnackBar(
              content: Text(
                  unavailableMessage ?? '$tooltip одоогоор бэлэн биш байна.'),
            ),
          );
        }
      },
      icon: Image.asset(
        assetPath,
        width: 22,
        height: 22,
        fit: BoxFit.contain,
      ),
    );
  }
}

class _AnimatedSaveButton extends StatefulWidget {
  const _AnimatedSaveButton({required this.onSave});

  final FutureOr<void> Function()? onSave;

  @override
  State<_AnimatedSaveButton> createState() => _AnimatedSaveButtonState();
}

class _AnimatedSaveButtonState extends State<_AnimatedSaveButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.5), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.5, end: 1.0), weight: 70),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> flash() async {
    if (mounted) _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Хадгалах',
      onPressed: () async {
        if (widget.onSave != null) {
          await Future.sync(widget.onSave!);
          flash();
          return;
        }
        if (!context.mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Хадгалах үйлдэл бэлэн биш байна.'),
          ),
        );
      },
      icon: ScaleTransition(
        scale: _scale,
        child: Image.asset(
          'assets/buttons/save.png',
          width: 22,
          height: 22,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _GlobalTableBar extends StatelessWidget {
  const _GlobalTableBar({
    required this.currentUserId,
    required this.canManageGames,
    required this.reopenTableRoute,
    required this.persistCurrentTableState,
  });

  final String? currentUserId;
  final bool canManageGames;
  final Future<bool> Function(BuildContext context, String lockId)
      reopenTableRoute;
  final Future<void> Function(BuildContext context) persistCurrentTableState;

  Future<void> _openNewTableSelection(BuildContext context) async {
    try {
      await persistCurrentTableState(context);
    } catch (_) {
      // Ignore and continue opening new table flow.
    }
    if (!context.mounted) return;

    final repo = ActiveTablesRepository();
    final lockedUserIds = await repo.watchActivePlayerUserIds().first;
    final selected = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerSelectionPage(
          isAddingMode: true,
          excludedUserIds: lockedUserIds.toList(),
          currentUserId: currentUserId,
          canManageGames: canManageGames,
        ),
      ),
    );

    if (selected == null || selected.isEmpty || !context.mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayingFormatPage(
          selectedUserIds: selected,
          currentUserId: currentUserId,
          canManageGames: canManageGames,
        ),
      ),
    );
  }

  Future<void> _jumpToTable(
      BuildContext context, ActiveTableSummary table) async {
    try {
      final routeName = 'active-table:${table.id}';
      final currentRouteName = ModalRoute.of(context)?.settings.name;
      if (currentRouteName == routeName) return;

      await persistCurrentTableState(context);
      if (!context.mounted) return;

      if (!ActiveTableRouteRegistry.contains(routeName)) {
        await reopenTableRoute(context, table.id);
        return;
      }

      Navigator.of(context)
          .popUntil((route) => route.settings.name == routeName);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Ширээ солих үед алдаа гарлаа. Дахин оролдоно уу.'),
        ),
      );
    }
  }

  BoxDecoration _tableButtonDecoration(
    ActiveTableSummary table,
    bool isCurrent, {
    bool expanded = false,
  }) {
    final border = Border.all(
      color: isCurrent ? const Color(0xFF111111) : Colors.white,
      width: isCurrent ? 3.6 : 1.5,
    );
    final boxShape = expanded ? BoxShape.rectangle : BoxShape.circle;
    final borderRadius = expanded ? BorderRadius.circular(18) : null;
    final commonHighlightShadow = isCurrent
        ? <BoxShadow>[
            const BoxShadow(
              color: Color(0x55000000),
              blurRadius: 10,
              spreadRadius: 0.5,
              offset: Offset(0, 3),
            ),
            const BoxShadow(
              color: Color(0x55FFFFFF),
              blurRadius: 1.5,
              spreadRadius: 0,
              offset: Offset(0, 0),
            ),
          ]
        : const <BoxShadow>[];

    switch (table.playingFormat) {
      case 'multi':
        return BoxDecoration(
          shape: BoxShape.circle,
          border: border,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFFE53935),
              Color(0xFFFB8C00),
              Color(0xFFFDD835),
              Color(0xFF43A047),
              Color(0xFF1E88E5),
              Color(0xFF8E24AA),
            ],
          ),
          boxShadow: [
            const BoxShadow(
              color: Color(0x33000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
            ...commonHighlightShadow,
          ],
        );
      case 'crazy':
        return BoxDecoration(
          shape: boxShape,
          borderRadius: borderRadius,
          border: border,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFFFFC107),
              Color(0xFFFF7043),
              Color(0xFFE65100),
            ],
          ),
          boxShadow: [
            const BoxShadow(
              color: Color(0x33FF7043),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
            ...commonHighlightShadow,
          ],
        );
      default:
        return BoxDecoration(
          shape: boxShape,
          borderRadius: borderRadius,
          border: border,
          color: const Color(0xFF1E88E5),
          boxShadow: [
            const BoxShadow(
              color: Color(0x33000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
            ...commonHighlightShadow,
          ],
        );
    }
  }

  Widget _tableButton(
    BuildContext context,
    ActiveTableSummary table,
    bool isCurrent,
  ) {
    return Tooltip(
      message: 'Ширээ ${table.tableNumber}: ${table.gameName}',
      child: _HoverExpandableTableButton(
        table: table,
        isCurrent: isCurrent,
        onTap: () async => _jumpToTable(context, table),
        decorationBuilder: ({required bool expanded}) => _tableButtonDecoration(
          table,
          isCurrent,
          expanded: expanded,
        ),
      ),
    );
  }

  Widget _addTableButton(BuildContext context) {
    return Tooltip(
      message: 'Ширээ нэмэх',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _openNewTableSelection(context),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF00A86B),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ActiveTablesRepository();
    return StreamBuilder<List<ActiveTableSummary>>(
      stream: repo.watchActiveTableSummaries(),
      builder: (context, snapshot) {
        final tables = snapshot.data ?? const <ActiveTableSummary>[];
        final currentRouteName = ModalRoute.of(context)?.settings.name;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final table in tables)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _tableButton(
                  context,
                  table,
                  currentRouteName == 'active-table:${table.id}',
                ),
              ),
            _addTableButton(context),
          ],
        );
      },
    );
  }
}

enum _ExitAction {
  close,
  save,
  back,
}

class _HoverExpandableTableButton extends StatefulWidget {
  const _HoverExpandableTableButton({
    required this.table,
    required this.isCurrent,
    required this.onTap,
    required this.decorationBuilder,
  });

  final ActiveTableSummary table;
  final bool isCurrent;
  final VoidCallback onTap;
  final BoxDecoration Function({required bool expanded}) decorationBuilder;

  @override
  State<_HoverExpandableTableButton> createState() =>
      _HoverExpandableTableButtonState();
}

class _HoverExpandableTableButtonState
    extends State<_HoverExpandableTableButton> {
  static const double _collapsedSize = 36;
  static const double _expandedWidth = 128;
  static const Duration _duration = Duration(milliseconds: 180);

  bool _isHovered = false;

  bool get _canExpand => false;
  bool get _isExpanded => _canExpand && _isHovered;

  @override
  Widget build(BuildContext context) {
    final label = '${widget.table.tableNumber}: ${widget.table.gameName}';
    final borderRadius = BorderRadius.circular(_collapsedSize / 2);

    return MouseRegion(
      onEnter: (_) {
        if (_canExpand) {
          setState(() => _isHovered = true);
        }
      },
      onExit: (_) {
        if (_isHovered) {
          setState(() => _isHovered = false);
        }
      },
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: borderRadius),
          onTap: widget.onTap,
          child: AnimatedScale(
            duration: _duration,
            curve: Curves.easeOutCubic,
            scale: widget.isCurrent ? 1.08 : 1,
            child: AnimatedContainer(
              duration: _duration,
              curve: Curves.easeOutCubic,
              width: _isExpanded ? _expandedWidth : _collapsedSize,
              height: _collapsedSize,
              padding: EdgeInsets.symmetric(horizontal: _isExpanded ? 12 : 0),
              alignment: Alignment.center,
              decoration: widget.decorationBuilder(expanded: _isExpanded),
              child: AnimatedSwitcher(
                duration: _duration,
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _isExpanded
                    ? Text(
                        label,
                        key: ValueKey<String>(label),
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: widget.isCurrent ? 13.5 : 13,
                        ),
                      )
                    : Text(
                        '${widget.table.tableNumber}',
                        key: ValueKey<int>(widget.table.tableNumber),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: widget.isCurrent ? 15 : 14,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
