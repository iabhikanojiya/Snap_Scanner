import 'package:flutter/widgets.dart';

/// Root navigator, for opening screens from outside the widget tree
/// (e.g. a PDF opened with Snap Scanner from another app).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
