import 'package:flutter/widgets.dart';

import '../i18n/strings.dart';
import 'app_state.dart';

/// Makes the AppState available to every screen and rebuilds them when it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState app, required super.child}) : super(notifier: app);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Without rebuilding when the state changes (for callbacks).
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

extension AppContext on BuildContext {
  AppState get app => AppScope.of(this);
  AppState get appRead => AppScope.read(this);
  Strings get s => AppScope.of(this).s;
  String t(String key, [Map<String, Object?> params = const {}]) => AppScope.of(this).s.t(key, params);
}
