import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:toocoob/firebase_options.dart';
import 'package:toocoob/main.dart' as app;
import 'package:toocoob/screens/member_dashboard.dart';
import 'package:toocoob/screens/13_card_poker.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';

// Run only with firebase.mobile-test.json. All service endpoints below are local.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final host = Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';

  Future<Map<String, dynamic>> request(
      int port, String path, Map<String, dynamic> body,
      {bool patch = false}) async {
    final uri = Uri(scheme: 'http', host: host, port: port, path: path);
    const headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer owner'
    };
    final response = await (patch
            ? http.patch(uri, headers: headers, body: jsonEncode(body))
            : http.post(uri, headers: headers, body: jsonEncode(body)))
        .timeout(const Duration(seconds: 20));
    expect(response.statusCode, 200, reason: response.body);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  testWidgets('emulator login, player selection, poker and saved game',
      (tester) async {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8187);
    FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
    await FirebaseAuth.instance.signOut();
    final repository = SavedGameSessionsRepository();
    final originalSessions =
        (await repository.loadSessions()).map((s) => s.id).toSet();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      try {
        await FirebaseFirestore.instance
            .waitForPendingWrites()
            .timeout(const Duration(seconds: 10));
      } finally {
        // Do not carry emulator cache or queued writes into a normal app run.
        await FirebaseFirestore.instance.terminate();
        await FirebaseFirestore.instance.clearPersistence();
        await FirebaseAuth.instance.signOut();
        for (final session in await repository.loadSessions()) {
          if (!originalSessions.contains(session.id)) {
            await repository.removeById(session.id);
          }
        }
      }
    });

    final email =
        'mobile-${DateTime.now().microsecondsSinceEpoch}@example.invalid';
    const password = 'Local-emulator-only-123!';
    final created = await request(
        9099,
        '/identitytoolkit.googleapis.com/v1/projects/toocoob/accounts',
        {'email': email, 'password': password, 'emailVerified': true});
    final uid = created['localId'] as String;
    await request(9099,
        '/identitytoolkit.googleapis.com/v1/projects/toocoob/accounts:update', {
      'localId': uid,
      'emailVerified': true,
      'customAttributes': jsonEncode({'systemAdmin': true})
    });
    await request(
        8187,
        '/v1/projects/toocoob/databases/(default)/documents/users/$uid',
        {
          'fields': {
            'uid': {'stringValue': uid},
            'email': {'stringValue': email},
            'nickname': {'stringValue': 'Mobile test'},
            'firstName': {'stringValue': 'Mobile'},
            'lastName': {'stringValue': 'Test'},
            'role': {'stringValue': 'user'},
            'canManageGames': {'booleanValue': true},
            'createdAt': {
              'timestampValue': DateTime.now().toUtc().toIso8601String()
            },
          }
        },
        patch: true);

    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsWidgets);
    }

    Future<void> tap(Finder finder) async {
      await waitFor(finder);
      await tester.ensureVisible(finder.first);
      await tester.pumpAndSettle();
      await tester.tap(finder.first);
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(const app.ToocoobApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), password);
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Нэвтрэх'))
            .onPressed,
        isNotNull);
    await tap(find.widgetWithText(ElevatedButton, 'Нэвтрэх'));
    await waitFor(find.byType(MemberDashboard));
    expect(FirebaseAuth.instance.currentUser?.uid, uid);
    await tap(find.text('Яг одоо'));
    await tap(find.text('Шинэ тоглолт эхлүүлэх'));
    await tap(find.byTooltip('Туршилтын 10 тоглогч'));
    for (final name in ['Индиан', 'МС', 'Сыска', 'Шовгор']) {
      await tap(find.text(name));
    }
    await tap(find.text('Ширээнд урих'));
    if (find.text('Шинээр тоглох').evaluate().isNotEmpty) {
      await tap(find.text('Шинээр тоглох'));
    }
    await tap(find.text('Нэг төрлөөр\nтойрох'));
    await tap(find.text('13 модны\nпокер'));
    await waitFor(find.byType(ThirteenCardPokerScreen));
    await tester.pumpAndSettle();
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      for (final name in ['Индиан', 'МС', 'Сыска', 'Шовгор']) {
        await tap(find.descendant(
            of: find.byType(AlertDialog), matching: find.text(name)));
      }
      await tap(find.text('Дараалал хадгалах'));
    }
    final before = (await SavedGameSessionsRepository().loadSessions())
        .map((s) => s.id)
        .toSet();
    final fields = find.byType(TextField);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('poker-score-input-0')), 200,
        scrollable: find
            .descendant(
                of: find.byType(GridView).first,
                matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.ensureVisible(fields.at(i));
      await tester.enterText(fields.at(i), ['0', '2', '4', '5'][i]);
    }
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await tester.pumpAndSettle();
    await tap(find.byTooltip('Хадгалах'));
    final sessions = await SavedGameSessionsRepository().loadSessions();
    final saved = sessions.where((s) => !before.contains(s.id)).single;
    expect(saved.gameKey, '13_card_poker');
    expect(
        (saved.payload['totalScores'] as Map).values, containsAll([2, 4, 5]));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await FirebaseAuth.instance.signOut();
  });
}
