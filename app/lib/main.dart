import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart' hide Actions;
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_state.dart';
import 'app/scope.dart';
import 'ui/shell.dart';
import 'ui/dark.dart';
import 'ui/theme.dart';

/// The running app, once loaded (for reporting unexpected errors).
AppState? _running;
DateTime _lastReport = DateTime(2000);

/// Shows an unexpected error as a toast: after the current frame (never while a screen
/// is being drawn, which would cause a new error) and at most once every 5 seconds.
void _report(Object error) {
  final app = _running;
  if (app == null) return;
  final now = DateTime.now();
  if (now.difference(_lastReport) < const Duration(seconds: 5)) return;
  _lastReport = now;
  WidgetsBinding.instance.addPostFrameCallback((_) => app.showToast('${app.s.t('toast.unexpected')} $error', error: true));
  WidgetsBinding.instance.scheduleFrame();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A part of a screen that fails to draw shows a short message instead of a grey or
  // red box; the rest of the screen keeps working.
  ErrorWidget.builder = (details) => Directionality(
        // May be drawn above the app's own text direction, so it sets one itself.
        textDirection: TextDirection.ltr,
        child: Material(
          color: const Color(0xFFFBECEA),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('This part could not be shown: ${details.exceptionAsString()}',
                style: const TextStyle(color: Color(0xFF8C1D17), fontSize: 12.5)),
          ),
        ),
      );
  // Errors nobody caught (a failed background step) are shown, not silently lost.
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    previous?.call(details);
    _report(details.exceptionAsString());
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    _report(error);
    return true;
  };
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
    _start();
  }

  void _start() {
    AppState.load().then((a) {
      _running = a;
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
                : Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline, color: Color(0xFFB3261E), size: 36),
                      const SizedBox(height: 12),
                      Text('The app could not start.\n$_error\n\nYour data on this device is safe.', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => setState(() {
                          _error = null;
                          _start();
                        }),
                        child: const Text('Try again'),
                      ),
                    ]),
                  ),
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
    final dark = isDark(context);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: app.s.t('app.name'),
      theme: appTheme(arabic: ar, dark: dark),
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
      // A PC screen gets text about 7% larger (phones and small windows stay as they are),
      // on top of any size the user set in Windows.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        var page = child!;
        if (mq.size.width >= 1280) {
          page = MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(14) / 14 * 1.07)), child: page);
        }
        return dark ? ColorFiltered(colorFilter: darkFilter, child: page) : page;
      },
    );
  }
}

