import 'package:flutter/widgets.dart';

/// Lets tab screens refresh when the user returns from a pushed tool screen
/// (e.g. after a PDF was created), without reloading on every tab switch.
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
