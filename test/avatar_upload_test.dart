import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:toocoob/utils/avatar_upload.dart';

void main() {
  test('uploads with unsigned preset and returns secure avatar URL', () async {
    const url = 'https://res.cloudinary.com/pkrbzrqh/image/upload/v1/avatar.png';
    final client = MockClient((request) async {
      expect(request.url.host, 'api.cloudinary.com');
      expect(request.body, contains('toocoob_avatars'));
      expect(request.body, isNot(contains('api_secret')));
      return http.Response('{"secure_url":"$url"}', 200);
    });
    expect(await uploadAvatar(Uint8List.fromList([1, 2]), client: client), url);
    client.close();
  });
  test('rejects upload failures and unexpected image hosts', () async {
    for (final response in [http.Response('{}', 400),
      http.Response('{"secure_url":"https://example.com/a.png"}', 200)]) {
      final client = MockClient((_) async => response);
      await expectLater(uploadAvatar(Uint8List(0), client: client), throwsException);
      client.close();
    }
  });
}
