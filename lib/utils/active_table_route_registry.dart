class ActiveTableRouteRegistry {
  ActiveTableRouteRegistry._();

  static final Set<String> _routeNames = <String>{};

  static void register(String routeName) {
    if (routeName.trim().isEmpty) return;
    _routeNames.add(routeName);
  }

  static void unregister(String routeName) {
    if (routeName.trim().isEmpty) return;
    _routeNames.remove(routeName);
  }

  static bool contains(String routeName) {
    return _routeNames.contains(routeName);
  }
}
