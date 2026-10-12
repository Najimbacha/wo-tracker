// Saving and sharing files: on Windows a Save dialog, on Android the share sheet
// (Files, WhatsApp, email...).
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class SavedFile {
  final String path;
  final bool shared; // went to the share sheet instead of a chosen folder
  const SavedFile(this.path, {this.shared = false});
}

String _mime(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.xlsx')) return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  if (n.endsWith('.png')) return 'image/png';
  return 'application/octet-stream';
}

/// Asks where to save (desktop) or opens the share sheet (phone). Returns null when
/// the user cancelled. Throws FileSystemException when writing fails (disk full...).
Future<SavedFile?> saveOrShare(Uint8List bytes, String fileName) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$fileName';
    await File(path).writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: _mime(fileName))], fileNameOverrides: [fileName]));
    return SavedFile(path, shared: true);
  }
  final ext = fileName.split('.').last;
  final loc = await fs.getSaveLocation(
    suggestedName: fileName,
    acceptedTypeGroups: [fs.XTypeGroup(label: ext.toUpperCase(), extensions: [ext])],
  );
  if (loc == null) return null;
  var path = loc.path;
  if (!path.toLowerCase().endsWith('.$ext')) path = '$path.$ext';
  await File(path).writeAsBytes(bytes, flush: true);
  return SavedFile(path);
}

/// Why saving a file failed, in plain words when it is the usual Windows case: the file
/// is open in another program (Excel, a PDF viewer) or the folder can't be written to.
String fileErrorReason(Object e, String Function(String key) t) =>
    e is FileSystemException ? t('toast.fileBusy') : '$e';

/// Shares plain text (follow-up messages to contractors).
Future<void> shareText(String text) => SharePlus.instance.share(ShareParams(text: text));

/// Opens a saved file with the computer's default app.
Future<void> openFile(String path) async {
  if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', path]);
  }
}

/// Several files at once (report pages as images): one Save dialog for the first,
/// the rest go next to it; on a phone they share together.
Future<SavedFile?> saveOrShareMany(List<(Uint8List, String)> files) async {
  if (files.isEmpty) return null;
  if (files.length == 1) return saveOrShare(files.first.$1, files.first.$2);
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final xs = <XFile>[];
    for (final (bytes, name) in files) {
      final path = '${dir.path}/$name';
      await File(path).writeAsBytes(bytes, flush: true);
      xs.add(XFile(path, mimeType: _mime(name)));
    }
    await SharePlus.instance.share(ShareParams(files: xs));
    return SavedFile(xs.first.path, shared: true);
  }
  final first = await saveOrShare(files.first.$1, files.first.$2);
  if (first == null) return null;
  final sep = Platform.pathSeparator;
  final folder = first.path.substring(0, first.path.lastIndexOf(sep));
  final stem = first.path.substring(first.path.lastIndexOf(sep) + 1).replaceAll(RegExp(r'\.png$', caseSensitive: false), '');
  for (var i = 1; i < files.length; i++) {
    await File('$folder$sep$stem-${i + 1}.png').writeAsBytes(files[i].$1, flush: true);
  }
  return first;
}
