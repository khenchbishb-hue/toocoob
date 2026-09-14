import 'package:flutter_test/flutter_test.dart';
import 'package:toocoob/utils/durak_team_command.dart';

void main() {
  test('team assignment requires an explicit valid team number', () {
    expect(parseDurakTeamCommand('баг 1'), 1);
    expect(parseDurakTeamCommand('баг хоёр'), 2);
    expect(parseDurakTeamCommand('Баг 8'), 8);
    expect(parseDurakTeamCommand('баг 0'), isNull);
    expect(parseDurakTeamCommand('баг 9'), isNull);
    expect(parseDurakTeamCommand('хожлоо'), isNull);
    expect(parseDurakTeamCommand('1'), isNull);
  });
}
