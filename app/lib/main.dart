import 'package:flutter/material.dart' hide Actions;
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_state.dart';
import 'app/scope.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Boot());
}

/// Loads the rules, texts and local database, then shows the app.
class _Boot extends StatefulWidget {
  const _Boot();
  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  AppState? _app;
  Object? _error;

  @override
  void initState() {
    super.initState();
    AppState.load().then((a) {
      if (mounted) setState(() => _app = a);
    }, onError: (Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    if (app == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme(arabic: false),
        home: Scaffold(
          body: Center(
            child: _error == null
                ? const CircularProgressIndicator(strokeWidth: 2.5)
                : Padding(padding: const EdgeInsets.all(32), child: Text('The app could not start: $_error', textAlign: TextAlign.center)),
          ),
        ),
      );
    }
    return AppScope(app: app, child: const WoTrackerApp());
  }
}

class WoTrackerApp extends StatelessWidget {
  const WoTrackerApp({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final ar = app.rtl;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: app.s.t('app.name'),
      theme: appTheme(arabic: ar),
      locale: Locale(ar ? 'ar' : 'en'),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      scaffoldMessengerKey: app.messengerKey,
      navigatorKey: app.navigatorKey,
      home: const Shell(),
    );
  }
}
