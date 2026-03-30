import 'package:flutter/material.dart';
import 'package:toocoob/utils/active_table_route_registry.dart';

class ActiveTableRouteScope extends StatefulWidget {
  const ActiveTableRouteScope({
    super.key,
    required this.routeName,
    required this.child,
  });

  final String routeName;
  final Widget child;

  @override
  State<ActiveTableRouteScope> createState() => _ActiveTableRouteScopeState();
}

class _ActiveTableRouteScopeState extends State<ActiveTableRouteScope> {
  @override
  void initState() {
    super.initState();
    ActiveTableRouteRegistry.register(widget.routeName);
  }

  @override
  void dispose() {
    ActiveTableRouteRegistry.unregister(widget.routeName);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
