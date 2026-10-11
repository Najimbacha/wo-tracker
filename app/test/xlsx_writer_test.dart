// The Dart Excel writer must produce byte-for-byte the file that the JS writer
// (tools/rules-check/xlsx.mjs, checked with openpyxl and LibreOffice) produces.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wo_tracker/report/xlsx_writer.dart';

void main() {
  Map<String, dynamic> json(String p) => jsonDecode(File(p).readAsStringSync()) as Map<String, dynamic>;
  final fx = json('test/fixtures/export_doc.json');
  final want = json('test/fixtures/xlsx.json');

  test('crc32 and helpers', () {
    expect(crc32(utf8.encode('The quick brown fox jumps over the lazy dog')), 0x414fa339);
    expect(colLetter(27), 'AA');
    expect(excelDate('2026-10-11'), 46306);
  });

  final reports = (fx['report'] as List).cast<Map<String, dynamic>>();
  for (var i = 0; i < reports.length; i++) {
    test('report workbook ${reports[i]['kind']} ${reports[i]['lang']} is the same file', () {
      final bytes = workbookXlsx(reports[i]['workbook'] as Map<String, Object?>);
      final w = (want['report'] as List)[i] as Map<String, dynamic>;
      expect(bytes.length, w['length']);
      expect(crc32(bytes), w['crc32']);
    });
  }

  test('data workbook is the same file', () {
    final bytes = workbookXlsx((fx['data'] as Map<String, dynamic>)['workbook'] as Map<String, Object?>);
    final w = want['data'] as Map<String, dynamic>;
    expect(bytes.length, w['length']);
    expect(crc32(bytes), w['crc32']);
  });
}
