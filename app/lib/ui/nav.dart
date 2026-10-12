// Opening orders, forms and pages from anywhere.
import 'package:flutter/material.dart' hide Actions;

import '../app/scope.dart';
import '../domain/order_input.dart';
import 'screens/data_health_screen.dart';
import 'screens/order_detail.dart';
import 'screens/order_form.dart';
import 'widgets/common.dart';

/// On a wide screen showing Today, the order opens in the right-hand pane;
/// everywhere else it opens as its own page.
void openOrder(BuildContext context, String? id) {
  if (id == null) return;
  final app = context.appRead;
  if (isWide(context) && app.screen == 'today') {
    app.select(id);
    return;
  }
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OrderPage(orderId: id)));
}

Future<void> newOrder(BuildContext context) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const OrderFormPage()));
}

Future<void> editOrder(BuildContext context, OrderInput order) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => OrderFormPage(editing: order)));
}

void openDataHealth(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DataHealthScreen()));
}
