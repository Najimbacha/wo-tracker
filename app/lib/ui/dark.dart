// Dark mode: the colours come from the palette in theme.dart (class C), which switches
// between the light and the dark set. This says whether dark is on right now.
import 'package:flutter/material.dart';

import '../app/scope.dart';

/// The user's choice ('system', 'light' or 'dark') as dark or not, for this moment.
bool isDark(BuildContext context) {
  final mode = AppScope.of(context).themeMode;
  return mode == 'dark' || (mode == 'system' && MediaQuery.platformBrightnessOf(context) == Brightness.dark);
}
