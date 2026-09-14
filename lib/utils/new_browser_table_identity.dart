import 'dart:math';

String newBrowserTableIdentity() =>
    '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(0x100000000)}';
