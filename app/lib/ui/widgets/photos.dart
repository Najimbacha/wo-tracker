// Photos on a step: pick or take them, see them as small pictures under the step,
// tap one to see it big. A photo is never deleted from the device; "remove" only hides it.
import 'dart:io';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart' hide Actions;
import 'package:image_picker/image_picker.dart';

import '../../app/scope.dart';
import '../../data/models.dart';
import '../../data/order_rows.dart';
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

/// Asks where the picture comes from (camera or files; on a PC just files) and attaches it.
Future<void> addPhotosToStep(BuildContext context, OrderInput order, String stepKey, String stepName) async {
  final app = context.appRead;
  final s = app.s;
  final picker = ImagePicker();
  try {
    var files = <XFile>[];
    var fromCamera = false;
    if (_hasCamera) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(s.t('photo.camera')), onTap: () => Navigator.pop(c, 'camera')),
            ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(s.t('photo.gallery')), onTap: () => Navigator.pop(c, 'gallery')),
          ]),
        ),
      );
      if (choice == null) return;
      fromCamera = choice == 'camera';
    }
    if (fromCamera) {
      final f = await picker.pickImage(source: ImageSource.camera, maxWidth: 2400, imageQuality: 85);
      if (f != null) files = [f];
    } else {
      files = await picker.pickMultiImage(maxWidth: 2400, imageQuality: 85);
    }
    if (files.isEmpty) return;
    final label = '${order.woNumber ?? 'WO'}_${stepKey.split('@').first}';
    for (final f in files) {
      await app.repo.addPhoto(order: order, stepKey: stepKey, sourcePath: f.path, label: label);
    }
    app.showToast(s.t('photo.added', {'count': files.length, 'step': stepName}));
  } on Object catch (e) {
    app.showToast(s.t('photo.failed', {'error': e is RepoException ? s.t(e.key, e.params) : '$e'}), error: true);
  }
}

/// Small pictures of a step, tap one to open it big. Draws nothing when there are none.
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({super.key, required this.order, required this.stepKey, required this.canEdit});
  final OrderInput order;
  final String stepKey;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final photos = photosOfStep(context, order, stepKey);
    if (photos.isEmpty) return const SizedBox.shrink();
    final repo = context.app.repo;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (var i = 0; i < photos.length; i++)
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => showPhotoViewer(context, photos: photos, index: i, canDelete: canEdit),
            child: _Thumb(path: repo.photoPath(photos[i])),
          ),
      ]),
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
