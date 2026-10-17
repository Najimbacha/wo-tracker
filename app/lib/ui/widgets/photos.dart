// Attachments on a step (pictures, PDFs, any file): pick or take them, see them as small pictures under the step,
// tap one to see it big. A photo is never deleted from the device; "remove" only hides it.
import 'dart:io';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart' hide Actions;
import 'package:file_selector/file_selector.dart' as fs;
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';

import '../../app/scope.dart';
import '../../data/models.dart';
import '../../data/order_rows.dart' show stepRowIdFor;
import '../../data/repository.dart';
import '../../domain/order_input.dart';
import '../theme.dart';
import 'dialogs.dart';

bool get _hasCamera => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// The photos of one step of [order].
List<StepPhoto> photosOfStep(BuildContext context, OrderInput order, String stepKey) {
  final app = context.app;
  final id = order.id;
  if (id == null) return const [];
  final row = stepRowIdFor(id, stepKey, app.segmentStepKeys);
  return [for (final a in app.data.attachments) if (a.orderId == id && a.stepRowId == row) a];
}

/// Asks where the file comes from (camera, pictures or any file; on a PC just files) and attaches it.
/// Anything can be attached: pictures show as thumbnails, PDFs and other files open in their own program.
Future<void> addPhotosToStep(BuildContext context, OrderInput order, String stepKey, String stepName) async {
  final app = context.appRead;
  final s = app.s;
  try {
    var choice = 'files';
    if (_hasCamera) {
      final c = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(s.t('photo.camera')), onTap: () => Navigator.pop(c, 'camera')),
            ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(s.t('photo.gallery')), onTap: () => Navigator.pop(c, 'gallery')),
            ListTile(leading: const Icon(Icons.attach_file), title: Text(s.t('photo.file')), onTap: () => Navigator.pop(c, 'files')),
          ]),
        ),
      );
      if (c == null) return;
      choice = c;
    }
    final picked = <({String path, String name})>[];
    if (choice == 'camera') {
      final f = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2400, imageQuality: 85);
      if (f != null) picked.add((path: f.path, name: ''));
    } else if (choice == 'gallery') {
      for (final f in await ImagePicker().pickMultiImage(maxWidth: 2400, imageQuality: 85)) {
        picked.add((path: f.path, name: ''));
      }
    } else {
      for (final f in await fs.openFiles()) {
        picked.add((path: f.path, name: f.name));
      }
    }
    if (picked.isEmpty) return;
    final base = '${order.woNumber ?? 'WO'}_${stepKey.split('@').first}';
    for (final f in picked) {
      // A picture is named after the order and step; any other file keeps its own name too.
      final own = f.name.contains('.') ? f.name.substring(0, f.name.lastIndexOf('.')) : f.name;
      final label = isImageName(f.name.isEmpty ? f.path : f.name) || own.isEmpty ? base : '${base}_$own';
      await app.repo.addPhoto(order: order, stepKey: stepKey, sourcePath: f.path, label: label);
    }
    app.showToast(s.t('photo.added', {'count': picked.length, 'step': stepName}));
  } on Object catch (e) {
    app.showToast(s.t('photo.failed', {'error': e is RepoException ? s.t(e.key, e.params) : '$e'}), error: true);
  }
}

/// Opens a non-picture attachment in the program the system has for it (PDF reader, Word...).
Future<void> openAttachment(BuildContext context, StepPhoto a) async {
  final app = context.appRead;
  final s = app.s;
  final path = app.repo.photoPath(a);
  if (path == null) {
    app.showToast(s.t('photo.otherDevice'), error: true);
    return;
  }
  final r = await OpenFilex.open(path);
  if (r.type != ResultType.done) app.showToast(s.t('photo.openFailed', {'error': r.message}), error: true);
}

/// Small pictures and file tiles of a step. Draws nothing when there are none.
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({super.key, required this.order, required this.stepKey, required this.canEdit});
  final OrderInput order;
  final String stepKey;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final all = photosOfStep(context, order, stepKey);
    if (all.isEmpty) return const SizedBox.shrink();
    final repo = context.app.repo;
    final images = [for (final a in all) if (a.isImage) a];
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final a in all)
          if (a.isImage)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => showPhotoViewer(context, photos: images, index: images.indexOf(a), canDelete: canEdit),
              child: _Thumb(path: repo.photoPath(a)),
            )
          else
            _FileTile(file: a, canRemove: canEdit),
      ]),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.file, required this.canRemove});
  final StepPhoto file;
  final bool canRemove;

  Future<void> _remove(BuildContext context) async {
    final app = context.appRead;
    final s = app.s;
    final ok = await confirmDialog(context, title: s.t('photo.removeTitle'), body: s.t('photo.removeBody'), confirm: s.t('photo.remove'), danger: true);
    if (ok) await app.repo.removePhoto(file.id);
  }

  @override
  Widget build(BuildContext context) {
    final pdf = file.extension == 'PDF';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 230),
      child: Material(
        color: C.chip,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: C.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => openAttachment(context, file),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 8, end: 2, top: 4, bottom: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(pdf ? Icons.picture_as_pdf_outlined : Icons.insert_drive_file_outlined, size: 22, color: pdf ? C.critical : C.muted),
              const SizedBox(width: 8),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(file.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                  if (file.extension.isNotEmpty) Text(file.extension, style: const TextStyle(fontSize: 11, color: C.faint)),
                ]),
              ),
              if (canRemove)
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(padding: EdgeInsets.zero, iconSize: 16, tooltip: context.s.t('photo.remove'), onPressed: () => _remove(context), icon: const Icon(Icons.close)),
                )
              else
                const SizedBox(width: 8),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path});
  final String? path;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: C.chip, border: Border.all(color: C.line), borderRadius: BorderRadius.circular(6)),
          child: path == null
              ? const Icon(Icons.cloud_outlined, size: 20, color: C.locked)
              : Image.file(File(path!), fit: BoxFit.cover, cacheWidth: 160, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 20, color: C.locked)),
        ),
      );
}

Future<void> showPhotoViewer(BuildContext context, {required List<StepPhoto> photos, required int index, required bool canDelete}) =>
    showDialog<void>(context: context, barrierColor: Colors.black87, builder: (_) => _PhotoViewer(photos: photos, index: index, canDelete: canDelete));

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.photos, required this.index, required this.canDelete});
  final List<StepPhoto> photos;
  final int index;
  final bool canDelete;
  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _page = PageController(initialPage: widget.index);
  late final List<StepPhoto> _list = [...widget.photos];
  late int _at = widget.index;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _go(int to) => _page.animateToPage(to, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);

  Future<void> _remove() async {
    final app = context.appRead;
    final s = app.s;
    final a = _list[_at];
    final ok = await confirmDialog(context, title: s.t('photo.removeTitle'), body: s.t('photo.removeBody'), confirm: s.t('photo.remove'), danger: true);
    if (!ok || !mounted) return;
    await app.repo.removePhoto(a.id);
    if (!mounted) return;
    if (_list.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _list.removeAt(_at);
      if (_at >= _list.length) _at = _list.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final a = _list[_at];
    final t = a.takenAt.toLocal();
    final when = '${app.dateShort(t.toIso8601String().substring(0, 10))}  ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(children: [
        PageView.builder(
          controller: _page,
          itemCount: _list.length,
          onPageChanged: (i) => setState(() => _at = i),
          itemBuilder: (_, i) {
            final path = app.repo.photoPath(_list[i]);
            if (path == null) {
              return Center(child: Text(s.t('photo.otherDevice'), style: const TextStyle(color: Colors.white70)));
            }
            return InteractiveViewer(maxScale: 6, child: Center(child: Image.file(File(path), fit: BoxFit.contain)));
          },
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: SafeArea(
              bottom: false,
              child: Row(children: [
                IconButton(tooltip: s.t('common.close'), onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close, color: Colors.white)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
                    Text('$when  ·  ${_at + 1} / ${_list.length}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ),
                if (widget.canDelete) IconButton(tooltip: s.t('photo.remove'), onPressed: _remove, icon: const Icon(Icons.delete_outline, color: Colors.white)),
              ]),
            ),
          ),
        ),
        if (_at > 0)
          Align(alignment: Alignment.centerLeft, child: IconButton(onPressed: () => _go(_at - 1), icon: const Icon(Icons.chevron_left, color: Colors.white, size: 36))),
        if (_at < _list.length - 1)
          Align(alignment: Alignment.centerRight, child: IconButton(onPressed: () => _go(_at + 1), icon: const Icon(Icons.chevron_right, color: Colors.white, size: 36))),
      ]),
    );
  }
}
