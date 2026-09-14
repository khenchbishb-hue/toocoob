import 'package:firebase_auth_web/firebase_auth_web.dart';
import 'package:cloud_functions_web/cloud_functions_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// The generated web registrant can become stale after adding a plugin during
/// an incremental web build. Register Auth before Firebase is initialized so
/// web never falls back to a MethodChannel implementation.
void registerFirebaseAuthWebPlugin() {
  FirebaseAuthWeb.registerWith(webPluginRegistrar);
  FirebaseFunctionsWeb.registerWith(webPluginRegistrar);
}
