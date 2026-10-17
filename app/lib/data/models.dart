// Reference data, settings and sync state shown by the screens. Work orders
// themselves are OrderInput (domain/order_input.dart).

class Contractor {
  final String id;
  final String name;
  final String? phone;
  final bool active;
  final bool deleted;
  const Contractor({required this.id, required this.name, this.phone, this.active = true, this.deleted = false});
  Contractor copyWith({String? name, Object? phone = _keep, bool? active, bool? deleted}) => Contractor(
        id: id,
        name: name ?? this.name,
        phone: identical(phone, _keep) ? this.phone : phone as String?,
        active: active ?? this.active,
        deleted: deleted ?? this.deleted,
      );
}

class District {
  final String id;
  final String name;
  final bool deleted;
  const District({required this.id, required this.name, this.deleted = false});
}

class CableSize {
  final String id;
  final int sizeMm2;
  final bool deleted;
  const CableSize({required this.id, required this.sizeMm2, this.deleted = false});
}

class SavedView {
  final String id;
  final String name;
  final Map<String, dynamic> filter;
  final int sortOrder;
  const SavedView({required this.id, required this.name, required this.filter, this.sortOrder = 0});
}

class FollowUpRecord {
  final String id;
  final String contractorId;
  final DateTime followedAt;
  final String? note;
  const FollowUpRecord({required this.id, required this.contractorId, required this.followedAt, this.note});
}

/// A photo attached to a step. The picture itself is a file on the device that took it
/// (the row, with its name and time, syncs); [driveFileId] is set once it is in Google Drive.
class StepPhoto {
  final String id;
  final String orderId;
  final String? stepRowId; // the steps row it belongs to (see stepRowIdFor)
  final String fileName; // e.g. 402_2602... _excavation_2026-10-16.jpg
  final DateTime takenAt;
  final String? driveFileId;
  const StepPhoto({required this.id, required this.orderId, this.stepRowId, required this.fileName, required this.takenAt, this.driveFileId});

  /// Pictures show as thumbnails; everything else (PDF, Word, Excel...) opens in its own program.
  bool get isImage => isImageName(fileName);
  String get extension {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? '' : fileName.substring(dot + 1).toUpperCase();
  }
}

bool isImageName(String name) => RegExp(r'\.(jpe?g|png|gif|webp|bmp|heic|heif)$', caseSensitive: false).hasMatch(name);

/// The attachments.kind a file gets on the server: photo, sec_pdf or other.
String attachmentKindOf(String name) => isImageName(name) ? 'photo' : (name.toLowerCase().endsWith('.pdf') ? 'sec_pdf' : 'other');

/// "Check tasreeh on Sunday": a note on one order with a day to look at it again.
class Reminder {
  final String id;
  final String orderId;
  final String due; // yyyy-mm-dd
  final String note;
  final bool done;
  const Reminder({required this.id, required this.orderId, required this.due, required this.note, this.done = false});
}

const Object _keep = Object();

/// The account's settings (one row per account, same id on every device).
class AppSettings {
  final Map<String, int> alertOverrides;
  final String preparedBy;
  final String language; // en | ar
  final bool showHijri;
  const AppSettings({this.alertOverrides = const {}, this.preparedBy = 'Engr Najim', this.language = 'en', this.showHijri = true});
  AppSettings copyWith({Map<String, int>? alertOverrides, String? preparedBy, String? language, bool? showHijri}) => AppSettings(
        alertOverrides: alertOverrides ?? this.alertOverrides,
        preparedBy: preparedBy ?? this.preparedBy,
        language: language ?? this.language,
        showHijri: showHijri ?? this.showHijri,
      );
}

/// What the sync indicator and Data health show.
class SyncInfo {
  final bool configured; // Supabase and PowerSync addresses entered
  final bool signedIn;
  final bool connected; // the sync connection is up
  final bool connecting;
  final bool uploading;
  final bool downloading;
  final DateTime? lastSyncedAt;
  final int pendingChanges; // saved on this device, not yet on the server
  final String? error; // last connection error, in plain words
  final String? userEmail;
  const SyncInfo({
    this.configured = false,
    this.signedIn = false,
    this.connected = false,
    this.connecting = false,
    this.uploading = false,
    this.downloading = false,
    this.lastSyncedAt,
    this.pendingChanges = 0,
    this.error,
    this.userEmail,
  });

  /// One word for the header badge.
  String get state {
    if (!configured || !signedIn) return 'local';
    if (connected && pendingChanges == 0 && !uploading) return 'synced';
    if (connected) return 'syncing';
    return 'offline';
  }
}

/// A change the server refused for good (see data/upload_errors.dart). Kept on the
/// device until the user deals with it.
class RefusedChange {
  final String id;
  final String table;
  final String rowId;
  final String op; // PUT | PATCH | DELETE
  final Map<String, dynamic> data;
  final String code; // refused.<code>
  final String? value;
  final String? message;
  final DateTime at;
  final String? workOrderId; // to open the order from the list
  final String? woNumber;
  const RefusedChange({
    required this.id,
    required this.table,
    required this.rowId,
    required this.op,
    required this.data,
    required this.code,
    this.value,
    this.message,
    required this.at,
    this.workOrderId,
    this.woNumber,
  });
}

/// One line of an order's history (from the server's activity_log; needs internet).
class HistoryEntry {
  final DateTime at;
  final String table;
  final String rowId;
  final String action; // insert | update | soft_delete | restore
  final Map<String, dynamic> oldData; // changed columns before (updates)
  final Map<String, dynamic> newData; // changed columns after, or the whole new row
  const HistoryEntry({required this.at, required this.table, required this.rowId, required this.action, this.oldData = const {}, this.newData = const {}});
}
