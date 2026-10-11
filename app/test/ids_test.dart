// Step row ids must be identical to the ones every other device and the JS
// reference compute. Values come from Python (hashlib / uuid.uuid5).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wo_tracker/data/ids.dart';

void main() {
  final fx = jsonDecode(File('test/fixtures/ids.json').readAsStringSync()) as Map<String, dynamic>;
  String hex(Uint8List b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  test('SHA-1 matches Python on lengths around the block edges', () {
    for (final v in (fx['sha1'] as List).cast<Map<String, dynamic>>()) {
      final text = v['text'] as String;
      expect(hex(StepIds.sha1(Uint8List.fromList(utf8.encode(text)))), v['sha1'], reason: 'length ${text.length}');
    }
  });

  test('version 5 ids match the standard', () {
    final r = fx['rfcCheck'] as Map<String, dynamic>;
    expect(StepIds.uuidV5(r['namespace'] as String, r['name'] as String), r['id']);
    expect(StepIds.namespace, fx['namespace']);
  });

  test('step row ids match the independently computed values', () {
    for (final c in (fx['cases'] as List).cast<Map<String, dynamic>>()) {
      expect(
        StepIds.stepRowId(c['workOrderId'] as String, c['stepKey'] as String,
            segmentId: c['segmentId'] as String?, meterId: c['meterId'] as String?),
        c['id'],
        reason: c['stepKey'] as String,
      );
    }
  });

  test('same step gives the same id, different steps different ids', () {
    final a = StepIds.stepRowId('w1', 'meter_on', meterId: 'm1');
    expect(StepIds.stepRowId('w1', 'meter_on', meterId: 'm1'), a);
    expect(StepIds.stepRowId('w1', 'meter_on', meterId: 'm2'), isNot(a));
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(a), isTrue);
  });
}
