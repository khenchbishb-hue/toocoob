import 'package:flutter_test/flutter_test.dart';
import 'package:toocoob/utils/new_browser_table_identity.dart';
import 'package:toocoob/utils/browser_table_identity.dart';

void main() {
  test('identity generation works on web and stays stable in this runtime', () {
    final ids = List.generate(20, (_) => newBrowserTableIdentity());
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      expect(id, matches(RegExp(r'^\d+_\d+$')));
    }
    expect(browserTableIdentity, isNotEmpty);
    expect(browserTableIdentity, browserTableIdentity);
  });
}
