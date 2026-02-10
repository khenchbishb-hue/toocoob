import 'dart:io';

Future<void> writeDebugFileImpl(String path, String content) async {
  try {
    final file = File(path);
    await file.writeAsString(content);
  } catch (_) {}
}
