import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;

/// Center-crop before upload so large originals are never stored as avatars.
Future<Uint8List> prepareAvatar(Uint8List bytes) async {
  if (bytes.length > 20 * 1024 * 1024) {
    throw Exception('20 MB-аас бага зураг сонгоно уу.');
  }
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 512);
  final frame = await codec.getNextFrame();
  codec.dispose();
  final source = frame.image;
  final side = source.width < source.height ? source.width : source.height;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(source,
      ui.Rect.fromLTWH((source.width - side) / 2, (source.height - side) / 2,
          side.toDouble(), side.toDouble()),
      const ui.Rect.fromLTWH(0, 0, 512, 512), ui.Paint());
  final picture = recorder.endRecording();
  final result = await picture.toImage(512, 512);
  final data = await result.toByteData(format: ui.ImageByteFormat.png);
  result.dispose();
  picture.dispose();
  source.dispose();
  if (data == null) throw Exception('Зургийг боловсруулах боломжгүй байна.');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<String> uploadAvatar(Uint8List bytes, {http.Client? client}) async {
  final connection = client ?? http.Client();
  try {
    final request = http.MultipartRequest('POST', Uri.parse(
        'https://api.cloudinary.com/v1_1/pkrbzrqh/image/upload'))
      ..fields['upload_preset'] = 'toocoob_avatars'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'avatar.png'));
    final response = await http.Response.fromStream(
        await connection.send(request).timeout(const Duration(seconds: 45)))
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw Exception('Зураг илгээж чадсангүй. Дахин оролдоно уу.');
    }
    final url = (jsonDecode(response.body) as Map<String, dynamic>)['secure_url'];
    if (url is! String || !url.startsWith(
        'https://res.cloudinary.com/pkrbzrqh/image/upload/')) {
      throw Exception('Зургийн холбоос буруу байна.');
    }
    return url;
  } finally {
    if (client == null) connection.close();
  }
}
