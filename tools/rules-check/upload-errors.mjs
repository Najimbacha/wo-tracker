// What to do when the server refuses an upload from the device's sync queue.
//
// PowerSync uploads local changes in order. If one change is refused and simply
// retried, it blocks everything behind it forever. So each refusal is sorted into:
//   retry     - a passing problem (offline, server busy or waking up, a parent row
//               not uploaded yet). Try again later; the change stays queued.
//   sign_in   - the session expired. Refresh the sign-in, then retry.
//   decision  - the server will never accept this change as it is (duplicate number,
//               a rule the database enforces). It moves to the "Needs your decision"
//               list, the queue carries on, and nothing is lost: the change is kept on
//               the device until it is edited and saved again, or undone.
//
// The Dart data layer (app/lib/data/upload_errors.dart) follows this file line by line;
// both are checked against app/test/fixtures/upload_errors.json.
//
// Input: { network: true } for no connection / timeout, otherwise the HTTP status and
// the Postgres / PostgREST error body { code, message, details }. `row` is the local row
// that was being uploaded: with row-level security on, Postgres leaves the duplicate
// value out of the error, so the number shown to the user comes from the row.
// The messages in the test fixture were captured from the real schema.

/** Delay before retry number `attempt` (1, 2, ...), in seconds. */
export const RETRY_DELAYS = [5, 15, 60, 300, 900];
export const retryDelay = (attempt) => RETRY_DELAYS[Math.min(Math.max(attempt, 1), RETRY_DELAYS.length) - 1];

/** A row whose parent is missing is retried this many times (the parent may still be uploading). */
export const MISSING_PARENT_RETRIES = 5;

/** Every code, with the fields its message may use. Messages are under `refused.<code>`. */
export const UPLOAD_CODES = {
  offline: [],
  server_busy: [],
  parent_not_synced: [],
  sign_in: [],
  duplicate_wo: ['value'],
  duplicate_permit: ['value'],
  duplicate_name: ['value'],
  duplicate_row: [],
  future_date: [],
  invalid_value: ['constraint'],
  missing_parent: [],
  not_allowed: [],
  refused_other: ['message'],
};

// Unique index -> code, and the row column holding the value the user typed.
const UNIQUE_CODES = {
  work_orders_number_uq: ['duplicate_wo', 'wo_number'],
  permits_number_uq: ['duplicate_permit', 'permit_number'],
  contractors_name_uq: ['duplicate_name', 'name'],
  districts_name_uq: ['duplicate_name', 'name'],
  cable_sizes_uq: ['duplicate_name', 'size_mm2'],
};

// The last "quoted" name in a message is the constraint ('relation "x" violates check constraint "y"').
const quoted = (s) => { const all = [...(s || '').matchAll(/"([^"]+)"/g)]; return all.length ? all[all.length - 1][1] : null; };
// "Key (owner_id, wo_number)=(…, 441700101) already exists." -> "441700101" (when shown).
const lastKeyValue = (details) => {
  const m = /\)=\((.*)\) already exists/.exec(details || '');
  if (!m) return null;
  const parts = m[1].split(', ');
  return parts[parts.length - 1];
};

export function classifyUploadError(err, attempt = 1, row = null) {
  const retry = (code) => ({ action: 'retry', code, delaySeconds: retryDelay(attempt) });
  const decision = (code, extra = {}) => ({ action: 'decision', code, ...extra });
  if (!err || err.network) return retry('offline');
  const status = err.status || 0;
  const code = String(err.code || '');
  const message = err.message || '';

  if (status === 401 || code === 'PGRST301' || code === 'PGRST303') return { action: 'sign_in', code: 'sign_in' };

  // Postgres error classes (SQLSTATE).
  if (code === '23505') {
    const constraint = quoted(message);
    const mapped = UNIQUE_CODES[constraint];
    if (!mapped) return decision('duplicate_row');
    const typed = row && row[mapped[1]] !== undefined && row[mapped[1]] !== null ? String(row[mapped[1]]).trim() : null;
    return decision(mapped[0], { value: typed ?? lastKeyValue(err.details) });
  }
  if (code === '23514') {
    if (/cannot be in the future/i.test(message)) return decision('future_date');
    return decision('invalid_value', { constraint: quoted(message) });
  }
  if (code === '23503') return attempt < MISSING_PARENT_RETRIES ? retry('parent_not_synced') : decision('missing_parent');
  // Child rows are checked against their order by row-level security, so a row whose
  // order hasn't reached the server yet is refused this way too.
  if (code === '42501' && /row-level security/i.test(message)) {
    return attempt < MISSING_PARENT_RETRIES ? retry('parent_not_synced') : decision('missing_parent');
  }
  if (code === '42501') return decision('not_allowed');
  if (code.startsWith('22') || code === '23502') return decision('invalid_value', { constraint: null });
  if (code === '40001' || code === '40P01' || code.startsWith('08') || code.startsWith('53') || code.startsWith('57')) return retry('server_busy');

  // HTTP only.
  if (status === 403) return decision('not_allowed');
  if (status === 408 || status === 429 || status >= 500 || status === 0) return retry('server_busy');
  return decision('refused_other', { message: message.slice(0, 200) });
}
