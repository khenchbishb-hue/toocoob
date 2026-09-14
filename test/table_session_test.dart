import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toocoob/utils/table_session.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cleanup only claims previous runs of the same tab and owner', () {
    final current = TableSession();
    final old = <String, dynamic>{'status': 'active', 'ownerUserId': 'owner',
      'browserTabId': 'tab', 'browserRunId': 'previous'};
    expect(current.isPreviousRun(old, 'tab', 'owner'), isTrue);
    expect(current.isPreviousRun(old, 'other-tab', 'owner'), isFalse);
    expect(current.isPreviousRun(old, 'tab', 'other-owner'), isFalse);
    expect(current.isPreviousRun({...old, 'browserRunId': current.runId}, 'tab', 'owner'), isFalse);
    expect(current.isPreviousRun({...old, 'status': 'archived'}, 'tab', 'owner'), isFalse);
    expect(current.isPreviousRun({'status': 'active', 'ownerUserId': 'owner'}, 'tab', 'owner'), isFalse);
  });
  test('refresh hides previous tables and starts at 1 without clearing saves', () async {
    SharedPreferences.setMockInitialValues({});
    final saves = SavedGameSessionsRepository();
    final id = await saves.saveOrUpdate(gameKey: 'muushig', gameLabel: 'Муушиг',
        selectedUserIds: ['a', 'b'], payload: {'score': 9});
    final previous = TableSession();
    expect(previous.reserveNumber(), 1);
    previous.register('old-table');
    expect(previous.reserveNumber(), 2);
    final refreshed = TableSession();
    expect(refreshed.contains('old-table'), isFalse);
    expect(refreshed.reserveNumber(), 1);
    refreshed.register('resumed-or-new-table');
    expect(refreshed.contains('resumed-or-new-table'), isTrue);
    expect(refreshed.reserveNumber(), 2);
    expect((await saves.findById(id))!.payload['score'], 9);
  });
}
