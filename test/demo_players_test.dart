import 'package:flutter_test/flutter_test.dart';
import 'package:toocoob/utils/demo_players.dart';
import 'package:toocoob/utils/player_profiles.dart';

void main() {
  test('All ten demo identities load without Firebase initialization',
      () async {
    expect(DemoPlayers.all.map((p) => p.id).toSet(), hasLength(10));
    for (final player in DemoPlayers.all) {
      final profile = await loadPlayerProfile(player.id);
      expect(profile?['displayName'], player.displayName);
      expect(profile?['username'], player.username);
      expect(profile?['fullName'], player.fullName);
    }
  });
  test('Real users are not mistaken for demo identities', () {
    expect(DemoPlayers.profileForId('real-user'), isNull);
    expect(DemoPlayers.profileForId('demo_player_11'), isNull);
  });
  test('Demo profiles do not retain changes between games', () async {
    final profile = await loadPlayerProfile(DemoPlayers.all.first.id);
    profile!['score501'] = 0;
    final fresh = await loadPlayerProfile(DemoPlayers.all.first.id);
    expect(fresh!.containsKey('score501'), isFalse);
  });
}
