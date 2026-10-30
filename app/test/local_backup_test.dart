// The local backup: build a .zip of the data folder, read its description back, extract it,
// and refuse files that are not ours. Pure file work, so it runs without a device or account.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wo_tracker/data/local_backup.dart';

void main() {
  late Directory work;
  late Directory data;
  late String zip;
  const photoName = 'photo one.jpg';

  setUp(() {
    work = Directory.systemTemp.createTempSync('wo_backup_test');
    zip = '${work.path}${Platform.pathSeparator}backup.zip';
    data = Directory('${work.path}${Platform.pathSeparator}data')..createSync(recursive: true);
    // A database with recognisable bytes, a settings file and two photos in nested folders.
    File('${data.path}/wo_tracker.db').writeAsBytesSync(List<int>.generate(2048, (i) => i % 251));
    File('${data.path}/shared_preferences.json').writeAsStringSync('{"flutter.demoMode":false}');
    Directory('${data.path}/photos/second').createSync(recursive: true);
    File('${data.path}/photos/first.pdf').writeAsBytesSync(utf8.encode('%PDF-first'));
    File('${data.path}/photos/second/$photoName').writeAsBytesSync(List<int>.filled(900, 7));
    // A file the backup must ignore (it is not part of the data).
    File('${data.path}/boot.log').writeAsStringSync('log line');
  });

  tearDown(() {
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  test('a backup records what it contains and comes back complete', () async {
    final info = await LocalBackup.write(dataDir: data.path, zipPath: zip, orders: 42);
    expect(File(zip).existsSync(), isTrue);
    expect(info.orders, 42);
    expect(info.photos, 2);
    expect(info.dbBytes, 2048);

    // Reading it back without extracting reports the same thing.
    final read = await LocalBackup.inspect(zip);
    expect(read.orders, 42);
    expect(read.photos, 2);
    expect(read.dbBytes, 2048);
    expect(read.format, LocalBackup.format);

    // Extract and compare every file, including the photo in the nested folder.
    final out = '${work.path}${Platform.pathSeparator}out';
    await LocalBackup.extract(zipPath: zip, destDir: out);
    expect(File('$out/wo_tracker.db').readAsBytesSync(), File('${data.path}/wo_tracker.db').readAsBytesSync());
    expect(File('$out/shared_preferences.json').readAsStringSync(), '{"flutter.demoMode":false}');
    expect(File('$out/photos/first.pdf').readAsStringSync(), '%PDF-first');
    expect(File('$out/photos/second/$photoName').readAsBytesSync(), List<int>.filled(900, 7));
    // Logs are not part of the data and must not be in the archive.
    expect(File('$out/boot.log').existsSync(), isFalse);
  });

  test('a second backup replaces the first rather than growing it', () async {
    await LocalBackup.write(dataDir: data.path, zipPath: zip, orders: 1);
    await LocalBackup.write(dataDir: data.path, zipPath: zip, orders: 2);
    expect((await LocalBackup.inspect(zip)).orders, 2);
    // The archive holds one copy of each file, not two: writing again replaced it.
    final input = InputFileStream(zip);
    final archive = ZipDecoder().decodeStream(input);
    final names = archive.files.map((f) => f.name).toList();
    input.closeSync();
    expect(names.where((n) => n == LocalBackup.dbName).length, 1);
    expect(names.where((n) => n == LocalBackup.manifestName).length, 1);
  });

  test('a file that is not a backup is refused, and extraction writes nothing', () async {
    final junk = File('${work.path}${Platform.pathSeparator}junk.zip')..writeAsStringSync('not a zip at all');
    await expectLater(LocalBackup.inspect(junk.path), throwsA(isA<BackupException>()));
    final out = '${work.path}${Platform.pathSeparator}out3';
    await expectLater(LocalBackup.extract(zipPath: junk.path, destDir: out), throwsA(isA<BackupException>()));
    expect(Directory(out).existsSync(), isFalse);
  });

  test('a plain zip with no backup.json is refused (not mistaken for a backup)', () async {
    final archive = Archive()..addFile(ArchiveFile.string('something.txt', 'hello'));
    final path = '${work.path}${Platform.pathSeparator}plain.zip';
    File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    await expectLater(
      LocalBackup.inspect(path),
      throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('not a WO Tracker backup'))),
    );
  });

  test('a backup from a newer app version is refused', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string(
        LocalBackup.manifestName,
        jsonEncode({
          'magic': LocalBackup.magic,
          'format': LocalBackup.format + 1,
          'createdAt': '2030-01-01T00:00:00',
        }),
      ))
      ..addFile(ArchiveFile.bytes(LocalBackup.dbName, List<int>.filled(2048, 1)));
    final path = '${work.path}${Platform.pathSeparator}newer.zip';
    File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    await expectLater(
      LocalBackup.inspect(path),
      throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('newer'))),
    );
  });

  test('a backup with no database inside is refused', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string(
        LocalBackup.manifestName,
        jsonEncode({'magic': LocalBackup.magic, 'format': LocalBackup.format}),
      ));
    final path = '${work.path}${Platform.pathSeparator}nodb.zip';
    File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    await expectLater(
      LocalBackup.inspect(path),
      throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('no database'))),
    );
  });

  test('backing up a folder with no database says so plainly', () async {
    final empty = Directory('${work.path}${Platform.pathSeparator}empty')..createSync();
    await expectLater(LocalBackup.write(dataDir: empty.path, zipPath: zip), throwsA(isA<BackupException>()));
  });

  test('the suggested file name carries the date', () {
    expect(LocalBackup.fileNameFor(DateTime(2026, 10, 30, 14, 20)), 'wo-tracker-backup-2026-10-30.zip');
  });
}
