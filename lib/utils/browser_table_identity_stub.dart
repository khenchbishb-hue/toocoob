import 'new_browser_table_identity.dart';

// Non-web instances do not claim another instance's tables.
final String browserTableIdentity = newBrowserTableIdentity();
