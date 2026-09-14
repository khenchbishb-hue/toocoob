import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toocoob/utils/live_game_state.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';

class SaveProbe extends StatefulWidget {
  const SaveProbe({super.key});

  @override
  State<SaveProbe> createState() => SaveProbeState();
}

class SaveProbeState extends State<SaveProbe> with LiveGameState<SaveProbe> {
  int saves = 0;
  @override
  final liveRepository = LiveGameSessionsRepository();
  @override
  String? get liveRegistrar => null;
  @override
  Future<void> saveLiveProgress() async {
    saves++;
    await liveRepository.saveOrUpdate(
        gameKey: 'probe', gameLabel: 'Probe', selectedUserIds: ['owner'],
        payload: {'score': saves});
  }
  @override
  Future<void> restoreLiveProgress(SavedGameSession saved) async {}
  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: saveLiveProgress,
        child: const Text('Save'),
      );
  @override
  void dispose() {
    stopLiveGame();
    super.dispose();
  }
}

void main() {
  testWidgets('live checkpoints run on startup, idle, inactivity and exit',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final key = GlobalKey<SaveProbeState>();
    await tester.pumpWidget(MaterialApp(home: SaveProbe(key: key)));
    await tester.pumpAndSettle();
    final state = key.currentState!;
    await tester.pump(const Duration(seconds: 2));
    expect(state.saves, greaterThan(1));
    expect(await SavedGameSessionsRepository().loadSessions(), isEmpty);
    var before = state.saves;
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(state.saves, before + 1);
    final saved = (await SavedGameSessionsRepository().loadSessions()).single;
    before = state.saves;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 2));
    expect(state.saves, greaterThan(before));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    before = state.saves;
    await tester.pumpWidget(const SizedBox());
    expect(state.saves, before + 1);
    await tester.pumpAndSettle();
    expect((await SavedGameSessionsRepository().findById(saved.id))!.payload['score'], state.saves);
  });
}
