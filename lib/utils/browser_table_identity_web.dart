// ignore: deprecated_member_use
import 'dart:html' as html;
import 'new_browser_table_identity.dart';

final String browserTableIdentity = _loadIdentity();
String _loadIdentity() {
  const key = 'toocoob.table_tab.v1';
  final existing = html.window.sessionStorage[key];
  if (existing != null) return existing;
  final id = newBrowserTableIdentity();
  html.window.sessionStorage[key] = id;
  return id;
}
