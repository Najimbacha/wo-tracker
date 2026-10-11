// Refused uploads: the same cases the JS reference passes.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wo_tracker/data/upload_errors.dart';

void main() {
  final fx = jsonDecode(File('test/fixtures/upload_errors.json').readAsStringSync()) as Map<String, dynamic>;
  final en = jsonDecode(File('assets/i18n/en.json').readAsStringSync()) as Map<String, dynamic>;
  final ar = jsonDecode(File('assets/i18n/ar.json').readAsStringSync()) as Map<String, dynamic>;

  test('retry delays', () => expect(UploadErrors.retryDelays, fx['retryDelays']));

  for (final c in (fx['cases'] as List).cast<Map<String, dynamic>>()) {
    test('refused upload: ${c['name']}', () {
      final v = UploadErrors.classify(
        UploadError.fromJson(Map<String, dynamic>.from(c['error'] as Map)),
        attempt: c['attempt'] as int,
        row: (c['row'] as Map?)?.cast<String, Object?>(),
      );
      expect(v.toJson(), c['expect']);
    });
  }

  test('every code has English and Arabic text', () {
    for (final code in UploadErrors.codes.keys) {
      expect(en['refused.$code'], isNotNull, reason: code);
      expect(ar['refused.$code'], isNotNull, reason: code);
    }
  });
}
