// Dark mode. The screens are drawn in the light palette and one colour filter turns the whole
// app dark (lightness flipped, hues kept: blue stays blue, red stays red). Pictures, the camera
// and the paper preview of a report undo the filter so they look like the real thing.
import 'package:flutter/material.dart';

import '../app/scope.dart';

/// Light palette -> dark: white becomes near-black grey, dark text becomes light grey.
const darkFilter = ColorFilter.matrix(<double>[
  0.4764, -1.1869, -0.1195, 0, 237.15, //
  -0.3536, -0.3569, -0.1195, 0, 237.15, //
  -0.3536, -1.1869, 0.7105, 0, 237.15, //
  0, 0, 0, 1, 0,
]);

/// The exact opposite of [darkFilter], for things that must keep their own colours.
const undoDarkFilter = ColorFilter.matrix(<double>[
  0.6916, -1.7229, -0.1735, 0, 285.72, //
  -0.5133, -0.5181, -0.1735, 0, 285.72, //
  -0.5133, -1.7229, 1.0313, 0, 285.72, //
  0, 0, 0, 1, 0,
]);

/// 'system', 'light' or 'dark' (the user's choice) as dark or not, for this moment.
bool isDark(BuildContext context) {
  final mode = AppScope.of(context).themeMode;
  return mode == 'dark' || (mode == 'system' && MediaQuery.platformBrightnessOf(context) == Brightness.dark);
}

/// Shows [child] in its own colours even in dark mode (photos, camera, report paper).
class UndoDark extends StatelessWidget {
  const UndoDark({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => isDark(context) ? ColorFiltered(colorFilter: undoDarkFilter, child: child) : child;
}
