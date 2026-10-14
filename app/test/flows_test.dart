// Does what you do in a working day, with the demo orders, in English and Arabic, and
// redraws every screen after each change: mark steps done and not applicable, clear a
// step, Undo, hold and resume, add and remove a tasreeh, cancel, reopen, merge, delete
// and restore, change settings, and use the order form and dialogs. Lists every error
// it meets (one run shows them all instead of stopping at the first).
// ignore_for_file: unawaited_futures, discarded_futures
import 'package:flutter/material.dart' hide Actions;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wo_tracker/app/app_state.dart';
import 'package:wo_tracker/app/scope.dart';
import 'package:wo_tracker/domain/actions.dart' show ActionResult;
import 'package:wo_tracker/domain/order_input.dart';
import 'package:wo_tracker/main.dart';
import 'package:wo_tracker/ui/screens/order_detail.dart';
import 'package:wo_tracker/ui/screens/order_form.dart';
import 'package:wo_tracker/ui/screens/search_dialog.dart';

void main() {
  for (final lang in const ['en', 'ar']) {
    for (final size in const [Size(1440, 900), Size(390, 844)]) {
      testWidgets('a working day: $lang ${size.width.toInt()}', (tester) async {
        final problems = <String>[];
        final clock = Stopwatch()..start();
        var round = 0;
        var where = 'start';
        final previous = FlutterError.onError;
        FlutterError.onError = (d) {
          final text = d.exceptionAsString().split('\n').take(3).join(' / ');
          if (text.contains('MissingPluginException')) return; // file and PDF plugins: not in tests
          final at = <String>{
            for (final m in RegExp(r'package:wo_tracker/([\w/]+\.dart):(\d+)').allMatches(d.stack?.toString() ?? '')) 'lib/${m.group(1)}:${m.group(2)}',
          }.take(4).join(', ');
          problems.add('[$where] $text  @ $at');
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
          } catch (e, st) {
            final at = RegExp(r'package:wo_tracker/([\w/]+\.dart):(\d+)').firstMatch(st.toString());
            problems.add('[$name] $e${at == null ? '' : '  @ lib/${at.group(1)}:${at.group(2)}'}');
          }
          final ex = tester.takeException();
          if (ex != null) problems.add('[$name] $ex');
        }

        NavigatorState nav() => app.navigatorKey.currentState!;
        BuildContext ctx() => app.navigatorKey.currentContext!;
        Future<void> back() async {
          nav().popUntil((r) => r.isFirst);
          await settle();
        }

        // Saves an action; a refusal is fine (the rules may not allow it for this order),
        // but an exception is a bug.
        Future<void> act(String name, OrderInput o, ActionResult Function(OrderInput o) make) async {
          await step(name, () async {
            final fresh = app.orderById(o.id) ?? o;
            final r = make(fresh);
            await tester.runAsync(() => app.apply(fresh, r, toast: 'toast.stepDone', toastParams: {'step': name}));
          });
          // Look at the order and every screen after the change.
          await step('$name: order page', () async => nav().push(MaterialPageRoute<void>(builder: (_) => OrderPage(orderId: o.id!))));
          await back();
          // One screen after each change, in turn (all seven are drawn at the end), so the
          // run stays short; the order page and Today are looked at every time.
          final d = AppState.destinations[round++ % AppState.destinations.length];
          await step('$name: screen $d', () async => app.go(d));
          await step('$name: today', () async => app.go('today'));
          // ignore: avoid_print
          print('[${lang}${size.width.toInt()}] $name done (${clock.elapsed.inSeconds}s)');
        }

        final open = app.orders.where((o) => app.evaluate(o).status == 'open').toList();
        expect(open.length, greaterThan(4), reason: 'demo data should have open orders');
        final a = open[0], b = open[1], c = open[2], d = open[3];
        final today = app.today;
        // The next step to do, or the first step if nothing is waiting.
        String next(OrderInput o) {
          final ev = app.evaluate(o);
          return ev.next.isNotEmpty ? ev.next.first : ev.steps.first.id;
        }

        // Steps.
        await act('mark next step done', a, (o) => app.actions.markDone(o, next(o), today, today));
        await step('undo from the toast', () async {
          final undo = find.byType(SnackBarAction);
          if (undo.evaluate().isNotEmpty) {
            await tester.tap(undo.first);
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          }
        });
        await act('mark next step not applicable', a, (o) => app.actions.markNA(o, next(o), 'test', today));
        await act('mark done again', a, (o) => app.actions.markDone(o, next(o), today, today));
        await act('clear a done step', a, (o) {
          final done = app.evaluate(o).steps.where((s) => s.state == 'done').toList();
          return app.actions.clearStep(o, done.isEmpty ? next(o) : done.last.id);
        });

        // Hold and resume.
        await act('put on hold', b, (o) => app.actions.putOnHold(o, today, 'waiting', today));
        await act('resume', b, (o) => app.actions.resume(o, today, today));

        // Tasreeh.
        await act('add a tasreeh', c, (o) => app.actions.savePermit(o, null, Permit(number: 'TS-9${o.woNumber}', appliedDate: today), app.orders, today));
        await act('remove the last tasreeh', c, (o) => o.permits.isEmpty ? app.actions.reopen(o) : app.actions.removePermit(o, o.permits.length - 1));

        // Cancel, reopen, merge, delete, restore.
        await act('cancel', d, (o) => app.actions.cancel(o, 'test', today));
        await act('reopen', d, (o) => app.actions.reopen(o));
        await act('merge into another order', d, (o) => app.actions.merge(o, app.orderById(c.id), 'duplicate', true, today));
        await act('delete', b, (o) => app.actions.deleteOrder(o, 'test'));
        await act('restore', b, (o) => app.actions.restoreOrder(o, app.orders));

        // The order form: empty save shows what is missing, edits save.
        await step('new order: save empty', () async {
          nav().push(MaterialPageRoute<void>(builder: (_) => const OrderFormPage()));
          await settle();
          final save = find.byType(FilledButton);
          if (save.evaluate().isNotEmpty) await tester.tap(save.last);
        });
        await step('new order: type a number and save', () async {
          final fields = find.byType(TextField);
          if (fields.evaluate().isNotEmpty) await tester.enterText(fields.first, '4417000${lang == 'en' ? 1 : 2}');
          await settle();
          final save = find.byType(FilledButton);
          if (save.evaluate().isNotEmpty) await tester.tap(save.last);
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        });
        await back();
        await step('edit an order and save', () async {
          nav().push(MaterialPageRoute<void>(builder: (_) => OrderFormPage(editing: app.orderById(a.id))));
          await settle();
          final save = find.byType(FilledButton);
          if (save.evaluate().isNotEmpty) await tester.tap(save.last);
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        });
        await back();

        // Search.
        await step('search', () async {
          showSearchDialog(ctx());
          await settle();
          final f = find.byType(TextField);
          if (f.evaluate().isNotEmpty) await tester.enterText(f.last, a.woNumber?.substring(0, 4) ?? '44');
        });
        await back();

        // Settings and lists.
        await step('settings changes', () async {
          await tester.runAsync(() async {
            final con = await app.repo.addContractor('Test Contracting');
            await app.repo.updateContractor(con);
            final dis = await app.repo.addDistrict('Al Test');
            await app.repo.renameDistrict(dis.id, 'Al Test 2');
            await app.repo.addCableSize(240);
            final sizes = app.data.cableSizes.where((x) => x.sizeMm2 == 240).toList();
            if (sizes.isNotEmpty) await app.repo.removeCableSize(sizes.first.id);
            await app.repo.saveSettings(app.data.settings.copyWith(alertOverrides: {...app.data.settings.alertOverrides, 'open_trench': 3}));
            if (con.id.isNotEmpty) await app.repo.markFollowedUp(con.id);
          });
          app.go('settings');
        });
        for (final dd in AppState.destinations) {
          await step('after settings: screen $dd', () async => app.go(dd));
        }
        await step('switch language', () async {
          await tester.runAsync(() => app.setLanguage(lang == 'en' ? 'ar' : 'en'));
        });
        for (final dd in AppState.destinations) {
          await step('other language: screen $dd', () async => app.go(dd));
        }

        // Clean up.
        where = 'cleanup';
        await tester.pumpWidget(const SizedBox());
        app.dispose();
        await tester.pump(const Duration(seconds: 10));
        FlutterError.onError = previous;

        if (problems.isNotEmpty) {
          // ignore: avoid_print
          print('PROBLEMS ($lang ${size.width.toInt()}):\n${problems.toSet().join('\n')}');
          fail('${problems.toSet().length} problem(s); see the list above');
        }
      }, timeout: const Timeout(Duration(minutes: 10)));
    }
  }
}
