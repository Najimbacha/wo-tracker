// A local backup: the whole device folder (database, settings and photos) written to one
// .zip file that the user keeps where they like, and read back to restore everything.
//
// This is separate from the nightly cloud backup in .github/workflows. It needs no account,
// no internet and no Postgres: it is a copy of what this computer already holds.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

/// Thrown when a file is not a WO Tracker backup, or is from a newer version.
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What a backup file says about itself.
class BackupInfo {
  const BackupInfo({
    required this.createdAt,
    required this.format,
    required this.orders,
    required this.photos,
    required this.dbBytes,
  });

  /// When the backup was taken (ISO 8601, local time).
  final String createdAt;
  final int format;

  /// How many orders the app had when it was taken, when the writer recorded it.
  final int? orders;
  final int photos;
  final int dbBytes;

  static const empty = BackupInfo(createdAt: '', format: 0, orders: null, photos: 0, dbBytes: 0);
}

class LocalBackup {
  static const magic = 'wo-tracker-local-backup';
  static const format = 1;
  static const manifestName = 'backup.json';
  static const dbName = 'wo_tracker.db';
  static const walName = 'wo_tracker.db-wal';
  static const prefsName = 'shared_preferences.json';
  static const photosName = 'photos';

  static final String _sep = Platform.pathSeparator;

  /// Suggested file name, e.g. `wo-tracker-backup-2026-10-30.zip`.
  static String fileNameFor(DateTime now) {
    final d = now.toIso8601String().substring(0, 10);
    return 'wo-tracker-backup-$d.zip';
  }

  /// Writes [dataDir] (database, settings and the photos folder) into [zipPath].
  ///
  /// The existing files are read only; nothing in [dataDir] is changed or locked. The archive
  /// is built beside [zipPath] and only moved into place when complete, so an interrupted run
  /// never leaves a half-written backup under the real name.
  static Future<BackupInfo> write({
    required String dataDir,
    required String zipPath,
    int? orders,
    DateTime? now,
  }) async {
    final db = File('$dataDir$_sep$dbName');
    if (!await db.exists()) {
      throw const BackupException('There is no database to back up yet.');
    }
    final wal = File('$dataDir$_sep$walName');
    final prefs = File('$dataDir$_sep$prefsName');
    final photos = <File>[];
    final photosDir = Directory('$dataDir$_sep$photosName');
    if (await photosDir.exists()) {
      await for (final e in photosDir.list(recursive: true, followLinks: false)) {
        if (e is File) photos.add(e);
      }
      photos.sort((a, b) => a.path.compareTo(b.path));
    }

    final info = BackupInfo(
      createdAt: (now ?? DateTime.now()).toIso8601String(),
      format: format,
      orders: orders,
      photos: photos.length,
      dbBytes: await db.length(),
    );

    final manifest = File('$zipPath.manifest');
    final part = File('$zipPath.part');
    await part.parent.create(recursive: true);
    await manifest.writeAsString(
      jsonEncode(<String, Object?>{
        'magic': magic,
        'format': format,
        'createdAt': info.createdAt,
        'orders': info.orders,
        'photos': info.photos,
        'dbBytes': info.dbBytes,
      }),
      flush: true,
    );

    final encoder = ZipFileEncoder();
    try {
      encoder.create(part.path);
      await encoder.addFile(manifest, manifestName);
      await encoder.addFile(db, dbName);
      // The write-ahead log holds writes not yet in the .db file. Copy it too when it has
      // content, so a backup taken while the app is running still has everything.
      if (await wal.exists() && await wal.length() > 0) {
        await encoder.addFile(wal, walName);
      }
      if (await prefs.exists()) {
        await encoder.addFile(prefs, prefsName);
      }
      for (final f in photos) {
        final rel = f.path.substring(dataDir.length + 1).replaceAll(r'\', '/');
        await encoder.addFile(f, rel);
      }
    } finally {
      await encoder.close();
      await manifest.delete();
    }

    if (await File(zipPath).exists()) await File(zipPath).delete();
    await part.rename(zipPath);
    return info;
  }

  /// Reads a backup's description without extracting it. Throws [BackupException] when the
  /// file is not a WO Tracker backup or was written by a newer format.
  static Future<BackupInfo> inspect(String zipPath) async {
    if (!await File(zipPath).exists()) {
      throw const BackupException('That file does not exist.');
    }
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      try {
        return _info(archive);
      } finally {
        archive.clearSync();
      }
    } finally {
      // Leaving this open keeps the .zip locked on Windows: the user then cannot delete,
      // move or overwrite their own backup file.
      input.closeSync();
    }
  }

  static BackupInfo _info(Archive archive) {
    final entry = archive.findFile(manifestName);
    if (entry == null) {
      throw const BackupException('That file is not a WO Tracker backup (no backup.json inside).');
    }
    Map<String, dynamic> map;
    try {
      map = jsonDecode(utf8.decode(entry.readBytes() ?? const [])) as Map<String, dynamic>;
    } catch (_) {
      throw const BackupException('That backup file is damaged (its description cannot be read).');
    }
    if (map['magic'] != magic) {
      throw const BackupException('That file is not a WO Tracker backup.');
    }
    final f = (map['format'] as num?)?.toInt() ?? 0;
    if (f > format) {
      throw BackupException('That backup was made by a newer version of the app (format $f).');
    }
    final db = archive.findFile(dbName);
    if (db == null) {
      throw const BackupException('That backup has no database inside it.');
    }
    return BackupInfo(
      createdAt: (map['createdAt'] as String?) ?? '',
      format: f,
      orders: (map['orders'] as num?)?.toInt(),
      photos: (map['photos'] as num?)?.toInt() ?? 0,
      dbBytes: db.size,
    );
  }

  /// Extracts the whole backup into [destDir] (created if needed).
  static Future<void> extract({required String zipPath, required String destDir}) async {
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      try {
        // Validate before writing anything, so a wrong file cannot half-fill a folder.
        _info(archive);
        Directory(destDir).createSync(recursive: true);
        await extractArchiveToDisk(archive, destDir);
      } finally {
        archive.clearSync();
      }
    } finally {
      input.closeSync();
    }
  }
}
