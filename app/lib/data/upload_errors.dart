// What to do when the server refuses an upload from the device's sync queue.
//
// Follows tools/rules-check/upload-errors.mjs line by line; both are checked against
// test/fixtures/upload_errors.json (messages captured from the real schema).
//
//   retry     - a passing problem; the change stays queued and is tried again later.
//   sign_in   - the session expired; refresh the sign-in, then retry.
//   decision  - the server will never accept this change as it is. It moves to the
//               "Needs your decision" list (text: refused.<code>), the queue carries
//               on, and the change is kept on the device until it is edited and saved
//               again, or undone.

class UploadVerdict {
  final String action; // retry | sign_in | decision
  final String code; // see UploadErrors.codes; message key refused.<code>
  final int? delaySeconds; // for retry
  final String? value; // the duplicate number or name
  final String? constraint; // for invalid_value
  final String? message; // for refused_other
  final bool _hasConstraint;
  const UploadVerdict(this.action, this.code, {this.delaySeconds, this.value, this.constraint, this.message, bool hasConstraint = false})
      : _hasConstraint = hasConstraint;

  /// Same shape as the JS result, for the shared fixture.
  Map<String, Object?> toJson() => {
        'action': action,
        'code': code,
        if (action == 'retry') 'delaySeconds': delaySeconds,
        if (code == 'duplicate_wo' || code == 'duplicate_permit' || code == 'duplicate_name') 'value': value,
        if (_hasConstraint) 'constraint': constraint,
        if (code == 'refused_other') 'message': message,
      };
}

/// A refusal as reported by the sync client.
class UploadError {
  final bool network; // no connection / timeout
  final int? status; // HTTP status
  final String? code; // SQLSTATE or PGRSTxxx
  final String? message;
  final String? details;
  const UploadError({this.network = false, this.status, this.code, this.message, this.details});

  factory UploadError.fromJson(Map<String, dynamic> j) => UploadError(
        network: j['network'] == true,
        status: j['status'] as int?,
        code: j['code'] as String?,
        message: j['message'] as String?,
        details: j['details'] as String?,
      );
}

class UploadErrors {
  UploadErrors._();

  static const retryDelays = [5, 15, 60, 300, 900];
  static int retryDelay(int attempt) => retryDelays[(attempt < 1 ? 1 : (attempt > retryDelays.length ? retryDelays.length : attempt)) - 1];

  /// A row whose parent is missing is retried this many times.
  static const missingParentRetries = 5;

  /// Every code, with the fields its message may use.
  static const codes = <String, List<String>>{
    'offline': [],
    'server_busy': [],
    'parent_not_synced': [],
    'sign_in': [],
    'duplicate_wo': ['value'],
    'duplicate_permit': ['value'],
    'duplicate_name': ['value'],
    'duplicate_row': [],
    'future_date': [],
    'invalid_value': ['constraint'],
    'missing_parent': [],
    'not_allowed': [],
    'refused_other': ['message'],
  };

  // Unique index -> code, and the row column holding the value the user typed.
  static const _uniqueCodes = <String, List<String>>{
    'work_orders_number_uq': ['duplicate_wo', 'wo_number'],
    'permits_number_uq': ['duplicate_permit', 'permit_number'],
    'contractors_name_uq': ['duplicate_name', 'name'],
    'districts_name_uq': ['duplicate_name', 'name'],
    'cable_sizes_uq': ['duplicate_name', 'size_mm2'],
  };

  // The last "quoted" name in a message is the constraint.
  static String? _quoted(String? s) {
    final all = RegExp(r'"([^"]+)"').allMatches(s ?? '').toList();
    return all.isEmpty ? null : all.last.group(1);
  }

  static String? _lastKeyValue(String? details) {
    final m = RegExp(r'\)=\((.*)\) already exists').firstMatch(details ?? '');
    if (m == null) return null;
    final parts = m.group(1)!.split(', ');
    return parts.last;
  }

  /// [row] is the local row being uploaded (Postgres leaves the duplicate value out
  /// of the error when row-level security is on).
  static UploadVerdict classify(UploadError? err, {int attempt = 1, Map<String, Object?>? row}) {
    UploadVerdict retry(String code) => UploadVerdict('retry', code, delaySeconds: retryDelay(attempt));
    if (err == null || err.network) return retry('offline');
    final status = err.status ?? 0;
    final code = err.code ?? '';
    final message = err.message ?? '';

    if (status == 401 || code == 'PGRST301' || code == 'PGRST303') return const UploadVerdict('sign_in', 'sign_in');

    if (code == '23505') {
      final mapped = _uniqueCodes[_quoted(message)];
      if (mapped == null) return const UploadVerdict('decision', 'duplicate_row');
      final raw = row?[mapped[1]];
      final typed = raw == null ? null : raw.toString().trim();
      return UploadVerdict('decision', mapped[0], value: typed ?? _lastKeyValue(err.details));
    }
    if (code == '23514') {
      if (RegExp('cannot be in the future', caseSensitive: false).hasMatch(message)) return const UploadVerdict('decision', 'future_date');
      return UploadVerdict('decision', 'invalid_value', constraint: _quoted(message), hasConstraint: true);
    }
    if (code == '23503') {
      return attempt < missingParentRetries ? retry('parent_not_synced') : const UploadVerdict('decision', 'missing_parent');
    }
    // Child rows are checked against their order by row-level security, so a row whose
    // order hasn't reached the server yet is refused this way too.
    if (code == '42501' && RegExp('row-level security', caseSensitive: false).hasMatch(message)) {
      return attempt < missingParentRetries ? retry('parent_not_synced') : const UploadVerdict('decision', 'missing_parent');
    }
    if (code == '42501') return const UploadVerdict('decision', 'not_allowed');
    if (code.startsWith('22') || code == '23502') return const UploadVerdict('decision', 'invalid_value', hasConstraint: true);
    if (code == '40001' || code == '40P01' || code.startsWith('08') || code.startsWith('53') || code.startsWith('57')) {
      return retry('server_busy');
    }

    if (status == 403) return const UploadVerdict('decision', 'not_allowed');
    if (status == 408 || status == 429 || status >= 500 || status == 0) return retry('server_busy');
    return UploadVerdict('decision', 'refused_other', message: message.length > 200 ? message.substring(0, 200) : message);
  }
}
