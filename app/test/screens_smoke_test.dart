// Opens every screen, order, form and dialog with the demo orders, in English and
// Arabic, at PC, small-window and phone sizes, and lists every error and layout
// overflow it meets (one run shows them all instead of stopping at the first).
import 'package:flutter/material.dart' hide Actions;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wo_tracker/app/app_state.dart';
import 'package:wo_tracker/app/scope.dart';
import 'package:wo_tracker/main.dart';
import 'package:wo_tracker/ui/screens/data_health_screen.dart';
import 'package:wo_tracker/ui/screens/history_sheet.dart';
import 'package:wo_tracker/ui/screens/order_detail.dart';
import 'package:wo_tracker/ui/screens/order_form.dart';
import 'package:wo_tracker/ui/screens/permit_dialog.dart';
import 'package:wo_tracker/ui/screens/search_dialog.dart';
import 'package:wo_tracker/ui/screens/status_dialog.dart';

void main() {
  const sizes = [Size(1440, 900), Size(1000, 760), Size(390, 844)];
  for (final lang in const ['en', 'ar']) {
    for (final size in sizes) {
      testWidgets('every screen draws: $lang ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        final problems = <String>[];
        var where = 'start';
        final previous = FlutterError.onError;
        FlutterError.onError = (d) {
          final text = d.exceptionAsString().split('\n').take(3).join(' / ');
          if (text.contains('MissingPluginException')) return; // PDF preview plugin: not in tests
          problems.add('[$where] $text');
        };
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        SharedPreferences.setMockInitialValues({'demoMode': true, 'language': lang});
        final app = (await tester.runAsync(AppState.load))!;
        await tester.pumpWidget(AppScope(app: app, child: const WoTrackerApp()));

        Future<void> settle() async {
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 200));
          }
        }

        Future<void> step(String name, Future<void> Function() f) async {
          where = name;
          try {
            await f();
            await settle();
          } catch (e) {
            problems.add('[$name] $e');
          }
          final ex = tester.takeException();
          if (ex != null) problems.add('[$name] $ex');
        }

        NavigatorState nav() => app.navigatorKey.currentState!;
        BuildContext ctx() => app.navigatorKey.currentContext!;
        Future<void> back() async {
          if (nav().canPop()) nav().pop();
          await settle();
        }

        // Main screens.
        for (final d in AppState.destinations) {
          await step('screen $d', () async => app.go(d));
        }
        await step('back to today', () async => app.go('today'));

        // Orders: a spread of types and states.
        final orders = app.orders;
        final picked = <String>{};
        final sample = [
          for (final o in orders)
            if (picked.add('${o.type}|${o.state}|${o.permits.isNotEmpty}|${o.segments.isNotEmpty}')) o,
        ].take(14).toList();
        for (final o in sample) {
          await step('order ${o.woNumber} (${o.type}, ${o.state})', () async {
            nav().push(MaterialPageRoute<void>(builder: (_) => OrderPage(orderId: o.id!)));
          });
          await back();
          await step('edit ${o.woNumber}', () async {
            nav().push(MaterialPageRoute<void>(builder: (_) => OrderFormPage(editing: o)));
          });
          await back();
        }
        if (sample.isNotEmpty) {
          final o = sample.first;
          await step('wide-screen detail pane', () async => app.select(o.id));
        }

        // Forms and dialogs.
        await step('new order form', () async {
          nav().push(MaterialPageRoute<void>(builder: (_) => const OrderFormPage()));
        });
        await back();
        final active = orders.where((o) => o.state == 'open').toList();
        if (active.isNotEmpty) {
          await step('status dialog', () async => showStatusDialog(ctx(), active.first));
          await back();
        }
        final withPermit = orders.where((o) => o.permits.isNotEmpty).toList();
        if (withPermit.isNotEmpty) {
          await step('tasreeh dialog (edit)', () async => showPermitDialog(ctx(), withPermit.first, 0));
          await back();
          await step('tasreeh dialog (add)', () async => showPermitDialog(ctx(), withPermit.first, null));
          await back();
        }
        await step('search dialog', () async => showSearchDialog(ctx()));
        await back();
        if (orders.isNotEmpty) {
          await step('history sheet', () async => showHistorySheet(ctx(), orders.first));
          await back();
        }
        await step('data health', () async {
          nav().push(MaterialPageRoute<void>(builder: (_) => const DataHealthScreen()));
        });
        await back();

        // A real change, its toast and Undo.
        if (active.isNotEmpty) {
          await step('mark a step done', () async {
            final o = active.first;
            final ev = app.evaluate(o);
            if (ev.next.isNotEmpty) await app.apply(o, app.actions.markDone(o, ev.next.first, app.today, app.today), toast: 'toast.stepDone', toastParams: {'step': 'x'});
          });
        }

        // Clean up: close the app and let toasts and timers run out.
        where = 'cleanup';
        await tester.pumpWidget(const SizedBox());
        app.dispose();
        await tester.pump(const Duration(seconds: 10));
        FlutterError.onError = previous;

        if (problems.isNotEmpty) {
          // ignore: avoid_print
          print('PROBLEMS ($lang ${size.width.toInt()}x${size.height.toInt()}):\n${problems.toSet().join('\n')}');
          fail('${problems.toSet().length} problem(s); see the list above');
        }
      });
    }
  }
}
