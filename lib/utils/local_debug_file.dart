import 'local_debug_file_io.dart'
    if (dart.library.html) 'local_debug_file_web.dart';

Future<void> writeDebugFile(String path, String content) {
  return writeDebugFileImpl(path, content);
}
