// Every change the user can make to a work order, as pure functions.
// Each one takes an order (never modified) and returns either
//   { ok: true,  order: <changed copy>, ... }   or   { ok: false, errors: [{ code, ... }] }
// The Dart version in app/lib/domain/actions.dart follows this file; both are
// tested on app/test/fixtures/actions.json.
import { toDay, fromDay, generate, evaluate, orderPackages, validateMarkDone, clearImpact, validateOrder } from './engine.mjs';
import { normalizeText } from './insights.mjs';

const clone = (o) => structuredClone(o);
const fail = (...errors) => ({ ok: false, errors });
const isClosed = (order, id) => { const r = (order.steps || {})[id]; return !!(r && (r.done || r.na)); };
const blank = (s) => !s || !String(s).trim();
const maxDate = (a, b) => (!a ? b : !b ? a : toDay(a) >= toDay(b) ? a : b);
const state = (order) => (order.status && order.status.state) || 'open';
const withNote = (order, id, rec) => { const n = ((order.steps || {})[id] || {}).note; return n ? { ...rec, note: n } : rec; };
const holds = (order) => (order.status && order.status.holdPeriods) || [];

function withStatus(order, patch) {
  const o = clone(order);
  o.status = { state: 'open', holdPeriods: [], ...(o.status || {}), ...patch };
  return o;
}

// ---------------- Steps ----------------

/** Mark one step instance done on `date`. */
export function markDone(rules, order, stepId, date, today) {
  if (['cancelled', 'merged'].includes(state(order))) return fail({ code: 'not_active', state: state(order) });
  const errors = validateMarkDone(rules, order, stepId, date, today);
  if (errors.length) return fail(...errors);
  const o = clone(order);
  o.steps = { ...(o.steps || {}), [stepId]: withNote(order, stepId, { done: date }) };
  o.lastChangeDate = maxDate(o.lastChangeDate, date);
  return { ok: true, order: o, completed: evaluate(rules, o, today).status === 'completed' && evaluate(rules, order, today).status !== 'completed' };
}

/** Mark a step Not applicable. A written reason is required; it counts as done. */
export function markNA(rules, order, stepId, reason, today) {
  if (['cancelled', 'merged'].includes(state(order))) return fail({ code: 'not_active', state: state(order) });
  if (!generate(rules, order).some((s) => s.id === stepId)) return fail({ code: 'unknown_step' });
  const errors = [];
  if (isClosed(order, stepId)) errors.push({ code: 'already_closed' });
  if (blank(reason)) errors.push({ code: 'reason_required' });
  if (errors.length) return fail(...errors);
  const o = clone(order);
  o.steps = { ...(o.steps || {}), [stepId]: withNote(order, stepId, { na: true, reason: reason.trim() }) };
  o.lastChangeDate = maxDate(o.lastChangeDate, today);
  return { ok: true, order: o, completed: evaluate(rules, o, today).status === 'completed' && evaluate(rules, order, today).status !== 'completed' };
}

/** What clearing a step would also clear (for the confirmation dialog). */
export function clearPreview(rules, order, stepId) {
  if (!generate(rules, order).some((s) => s.id === stepId)) return fail({ code: 'unknown_step' });
  if (!isClosed(order, stepId)) return fail({ code: 'not_closed' });
  return { ok: true, alsoClears: clearImpact(rules, order, stepId) };
}

/** Clear a done / N/A step and every later step that depended on it. */
export function clearStep(rules, order, stepId) {
  const p = clearPreview(rules, order, stepId);
  if (!p.ok) return p;
  const o = clone(order);
  const steps = { ...(o.steps || {}) };
  const cleared = [stepId, ...p.alsoClears];
  for (const id of cleared) {
    // A note written on the step stays; only the done date or N/A is removed.
    const note = steps[id] && steps[id].note;
    if (note) steps[id] = { note }; else delete steps[id];
  }
  o.steps = steps;
  return { ok: true, order: o, cleared };
}

/**
 * Mark the same step done on many orders at once (from a filtered list).
 * Every open instance of `stepKey` that passes the checks is marked; orders where
 * nothing could be marked are listed in `skipped` with the reason.
 */
export function bulkMarkDone(rules, orders, stepKey, date, today) {
  const updated = [];
  const skipped = [];
  const results = [];
  for (const order of orders) {
    const instances = generate(rules, order).filter((s) => s.key === stepKey);
    if (!instances.length) { skipped.push({ id: order.id, errors: [{ code: 'unknown_step' }] }); results.push(order); continue; }
    const open = instances.filter((s) => !isClosed(order, s.id));
    if (!open.length) { skipped.push({ id: order.id, errors: [{ code: 'already_closed' }] }); results.push(order); continue; }
    let cur = order;
    const marked = [];
    let firstErrors = null;
    for (const s of open) {
      const r = markDone(rules, cur, s.id, date, today);
      if (r.ok) { cur = r.order; marked.push(s.id); } else if (!firstErrors) firstErrors = r.errors;
    }
    if (marked.length) updated.push({ id: order.id, steps: marked });
    else skipped.push({ id: order.id, errors: firstErrors });
    results.push(cur);
  }
  return { ok: true, orders: results, updated, skipped };
}

// ---------------- Status ----------------

/** Put an open order on hold from `from`. Alerts and day counts pause while on hold. */
export function putOnHold(rules, order, from, reason, today, reviewDate = null) {
  const st = evaluate(rules, order, today).status;
  const errors = [];
  if (st === 'on_hold') errors.push({ code: 'already_on_hold' });
  else if (st !== 'open') errors.push({ code: 'not_active', state: st });
  if (blank(reason)) errors.push({ code: 'reason_required' });
  if (toDay(from) > toDay(today)) errors.push({ code: 'future_date' });
  if (order.receivedDate && toDay(from) < toDay(order.receivedDate)) errors.push({ code: 'before_received' });
  const lastEnd = holds(order).filter((h) => h.to).map((h) => toDay(h.to));
  if (lastEnd.length && toDay(from) < Math.max(...lastEnd)) errors.push({ code: 'hold_overlap', date: fromDay(Math.max(...lastEnd)) });
  if (reviewDate && toDay(reviewDate) < toDay(from)) errors.push({ code: 'review_before_hold' });
  if (errors.length) return fail(...errors);
  const period = { from, to: null, reason: reason.trim() };
  if (reviewDate) period.review = reviewDate;
  return { ok: true, order: withStatus(order, { state: 'on_hold', holdPeriods: [...holds(order), period] }) };
}

/** End the current hold on `date`. */
export function resume(rules, order, date, today) {
  if (state(order) !== 'on_hold') return fail({ code: 'not_on_hold' });
  const hp = holds(order).map((h) => ({ ...h }));
  const open = hp.find((h) => !h.to);
  if (!open) return fail({ code: 'not_on_hold' });
  const errors = [];
  if (toDay(date) > toDay(today)) errors.push({ code: 'future_date' });
  if (toDay(date) < toDay(open.from)) errors.push({ code: 'before_hold_start', date: open.from });
  if (errors.length) return fail(...errors);
  open.to = date;
  return { ok: true, order: withStatus(order, { state: 'open', holdPeriods: hp }) };
}

function closeOpenHold(order, date) {
  return holds(order).map((h) => (h.to ? { ...h } : { ...h, to: toDay(date) < toDay(h.from) ? h.from : date }));
}

/** SEC cancelled the order. It stays in reports as Cancelled. */
export function cancel(rules, order, reason, today) {
  const st = evaluate(rules, order, today).status;
  const errors = [];
  if (!['open', 'on_hold'].includes(st)) errors.push({ code: 'not_active', state: st });
  if (blank(reason)) errors.push({ code: 'reason_required' });
  if (errors.length) return fail(...errors);
  return { ok: true, order: withStatus(order, { state: 'cancelled', reason: reason.trim(), date: today, holdPeriods: closeOpenHold(order, today) }) };
}

/**
 * The order was replaced by `target`. With `carry`, finished order-level steps are
 * copied to the target where the target has the same step and hasn't closed it yet.
 * Not copied: segment and meter steps (the new order has its own segments and meters)
 * and close-out paperwork (certificate, documents), which belongs to each order.
 */
export function merge(rules, order, target, reason, carry, today) {
  const st = evaluate(rules, order, today).status;
  const errors = [];
  if (!['open', 'on_hold'].includes(st)) errors.push({ code: 'not_active', state: st });
  if (!target) errors.push({ code: 'merge_target_required' });
  else if (target.id === order.id) errors.push({ code: 'merge_into_self' });
  else if (target.deleted || ['cancelled', 'merged'].includes(evaluate(rules, target, today).status)) errors.push({ code: 'merge_target_inactive' });
  if (blank(reason)) errors.push({ code: 'reason_required' });
  if (errors.length) return fail(...errors);

  const from = withStatus(order, { state: 'merged', reason: reason.trim(), mergedInto: target.id, date: today, holdPeriods: closeOpenHold(order, today) });
  let to = clone(target);
  const carried = [];
  const notCarried = [];
  if (carry) {
    const targetIds = new Set(generate(rules, target).map((s) => s.id));
    to.steps = { ...(to.steps || {}) };
    for (const s of generate(rules, order)) {
      if (!isClosed(order, s.id)) continue;
      if (s.instance || s.package === 'closeout' || !targetIds.has(s.id) || isClosed(target, s.id)) { notCarried.push(s.id); continue; }
      to.steps[s.id] = { ...order.steps[s.id] };
      carried.push(s.id);
    }
    if (carried.length) {
      const dates = carried.map((id) => to.steps[id].done).filter(Boolean);
      for (const d of dates) to.lastChangeDate = maxDate(to.lastChangeDate, d);
    }
  }
  return { ok: true, order: from, target: to, carried, notCarried };
}

/** Undo a cancel or merge made by mistake. Steps copied by a merge stay on the target. */
export function reopen(rules, order) {
  if (!['cancelled', 'merged'].includes(state(order))) return fail({ code: 'not_cancelled' });
  const o = withStatus(order, { state: 'open' });
  delete o.status.reason;
  delete o.status.mergedInto;
  delete o.status.date;
  return { ok: true, order: o };
}

// ---------------- Tasreeh ----------------

/**
 * Add (index = null) or change one tasreeh. Fields can arrive one at a time: applied
 * first, then the number and dates once Baladiya approves. When an applied date is
 * entered and the "Tasreeh applied" step is still open, that step is marked done on
 * that date (if the steps before it allow), so the two never disagree.
 * `orders` is every other order, to catch a number already used elsewhere.
 */
export function savePermit(rules, order, index, input, orders, today) {
  if (['cancelled', 'merged'].includes(state(order))) return fail({ code: 'not_active', state: state(order) });
  const p = {};
  for (const k of ['number', 'appliedDate', 'startDate', 'endDate']) {
    const v = k === 'number' ? cleanNumber(input[k]) : input[k];
    if (v !== undefined && v !== null && v !== '') p[k] = v;
  }
  const errors = [];
  if (!p.number && !p.appliedDate && !p.startDate) errors.push({ code: 'permit_empty' });
  if (p.appliedDate && toDay(p.appliedDate) > toDay(today)) errors.push({ code: 'future_date' });
  if (p.appliedDate && order.receivedDate && toDay(p.appliedDate) < toDay(order.receivedDate)) errors.push({ code: 'before_received' });
  const permits = (order.permits || []).map((x) => ({ ...x }));
  if (index !== null && (index < 0 || index >= permits.length)) return fail({ code: 'unknown_permit' });
  if (index === null) permits.push(p); else permits[index] = { ...(permits[index].id ? { id: permits[index].id } : {}), ...p };
  const draft = { ...order, permits };
  for (const e of validateOrder(rules, draft)) if (e.code.startsWith('permit_') || e.code === 'duplicate_permit') errors.push(e);
  if (p.number) {
    const other = findPermitOwner(orders, p.number, order.id);
    if (other) errors.push({ code: other.deleted ? 'duplicate_permit_deleted' : 'duplicate_permit_other', permit: p.number, wo: other.woNumber });
  }
  if (errors.length) return fail(...errors);
  let o = clone(draft);
  if (p.appliedDate) o.lastChangeDate = maxDate(o.lastChangeDate, p.appliedDate);
  let markedApplied = false;
  const hasStep = generate(rules, o).some((s) => s.id === 'tasreeh_applied');
  if (p.appliedDate && hasStep && !isClosed(o, 'tasreeh_applied')) {
    const r = markDone(rules, o, 'tasreeh_applied', p.appliedDate, today);
    if (r.ok) { o = r.order; markedApplied = true; }
  } else if (p.appliedDate && hasStep && index !== null) {
    // The applied date was corrected (e.g. typed late): the "Tasreeh applied" step moves
    // with it when it still carries the old applied date and the steps around it allow.
    const old = (order.permits || [])[index]?.appliedDate;
    const rec = o.steps?.tasreeh_applied;
    if (old && old !== p.appliedDate && rec && rec.done === old && movable(rules, o, 'tasreeh_applied', p.appliedDate)) {
      o.steps = { ...o.steps, tasreeh_applied: { ...rec, done: p.appliedDate } };
      markedApplied = true;
    }
  }
  return { ok: true, order: o, markedApplied };
}

/** True when the done step [id] can take [date]: not before the steps it waits for, and
 *  not after any finished step that waits for it. */
function movable(rules, o, id, date) {
  const steps = generate(rules, o);
  const s = steps.find((x) => x.id === id);
  if (!s) return false;
  const d = toDay(date);
  for (const dep of s.deps) {
    const done = o.steps?.[dep]?.done;
    if (done && toDay(done) > d) return false;
  }
  for (const x of steps) {
    if (!x.deps.includes(id)) continue;
    const done = o.steps?.[x.id]?.done;
    if (done && toDay(done) < d) return false;
  }
  return true;
}

/** Remove one tasreeh (e.g. typed on the wrong order). The step dates stay as they are. */
export function removePermit(rules, order, index) {
  const permits = order.permits || [];
  if (index < 0 || index >= permits.length) return fail({ code: 'unknown_permit' });
  const o = clone(order);
  o.permits = permits.filter((_, i) => i !== index).map((x) => ({ ...x }));
  return { ok: true, order: o, removed: permits[index] };
}

// ---------------- Delete and restore ----------------

/** Move an order to Deleted orders. Nothing is erased; it can be restored any time. */
export function deleteOrder(order, reason) {
  if (order.deleted) return fail({ code: 'already_deleted' });
  if (blank(reason)) return fail({ code: 'reason_required' });
  return { ok: true, order: { ...clone(order), deleted: true, deletedReason: reason.trim() } };
}

/**
 * Bring a deleted order back. Refused while another active order uses its work order
 * number or one of its tasreeh numbers (that order would have to be dealt with first).
 */
export function restoreOrder(order, orders) {
  if (!order.deleted) return fail({ code: 'not_deleted' });
  const errors = [];
  const active = orders.filter((o) => !o.deleted && o.id !== order.id);
  const dup = findDuplicate(active, order.woNumber, order.id);
  if (dup) errors.push({ code: 'duplicate_wo', id: dup.id, date: dup.date, district: dup.district });
  for (const p of order.permits || []) {
    const other = findPermitOwner(active, p.number, order.id);
    if (other) errors.push({ code: 'duplicate_permit_other', permit: p.number, wo: other.woNumber });
  }
  if (errors.length) return fail(...errors);
  const o = clone(order);
  delete o.deleted;
  delete o.deletedReason;
  return { ok: true, order: o };
}

// ---------------- Editing ----------------

/**
 * Finished steps that would no longer be part of the order after an edit
 * (type changed, excavation switched off, a segment or meter removed).
 * Their records are kept, so undoing the edit brings them back.
 */
export function editImpact(rules, before, after) {
  const afterIds = new Set(generate(rules, after).map((s) => s.id));
  return generate(rules, before).filter((s) => isClosed(before, s.id) && !afterIds.has(s.id)).map((s) => s.id);
}

/** Which parts of the New order / Edit form apply to this type. */
export function formSpec(rules, draft) {
  const type = rules.types[draft.type];
  const cat = rules.categories[draft.category];
  if (!type) return { type: false };
  const pkgs = orderPackages(rules, draft);
  return {
    type: true,
    excavationSwitch: !!type.optionalExcavation,
    tasreeh: pkgs.includes('tasreeh'),
    segments: pkgs.includes('restoration'),
    cableRuns: pkgs.includes('civil'),
    meters: pkgs.some((p) => rules.packages[p].scope === 'meter'),
    oldMeterNumber: pkgs.includes('meter_change') || pkgs.includes('meter_relocate'),
    woNumberPattern: cat ? cat.woNumberPattern : null,
    workBeforeTasreeh: !!(cat && cat.fieldWorkBeforeTasreeh),
  };
}

const westernDigits = (s) => s
  .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660)) // Arabic-Indic
  .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0)); // Persian / Urdu
const cleanNumber = (s) => (s === null || s === undefined ? s : westernDigits(String(s)).trim());

/**
 * Cleans what was typed before checking and saving: Arabic digits become 0-9 and
 * spaces around numbers are removed, in the work order, tasreeh and meter numbers.
 * With the rules, an excavation flag left over from another type is switched off.
 */
export function normalizeDraft(draft, rules = null) {
  const d = clone(draft);
  // The excavation switch only exists on some types (409). If the type was changed
  // to one without it, a leftover "on" would add steps the form no longer shows,
  // and the database would refuse the order.
  const type = rules && rules.types[d.type];
  if (type && d.needsExcavation && !type.optionalExcavation) d.needsExcavation = false;
  d.woNumber = cleanNumber(d.woNumber);
  d.permits = (d.permits || []).map((p) => ({ ...p, number: cleanNumber(p.number) }));
  d.meters = (d.meters || []).map((m) => {
    const c = { ...m };
    if ('number' in c) c.number = cleanNumber(c.number);
    if ('oldNumber' in c) c.oldNumber = cleanNumber(c.oldNumber);
    return c;
  });
  if (d.networkRef) d.networkRef = cleanNumber(d.networkRef);
  return d;
}

/** Checks before saving a new or edited order (on top of validateOrder). Run normalizeDraft first. */
export function validateDraft(rules, input, orders, today) {
  const draft = normalizeDraft(input, rules);
  const errors = [];
  if (blank(draft.woNumber)) errors.push({ code: 'wo_number_required' });
  if (!draft.receivedDate) errors.push({ code: 'received_required' });
  else if (toDay(draft.receivedDate) > toDay(today)) errors.push({ code: 'future_date' });
  for (const e of validateOrder(rules, draft)) if (!(e.code === 'bad_wo_number' && blank(draft.woNumber))) errors.push(e);
  // Meter steps are recorded per meter; an order without one would lose them when it is added.
  if (rules.types[draft.type] && formSpec(rules, draft).meters && !(draft.meters || []).length) errors.push({ code: 'meter_required' });
  if (!blank(draft.woNumber)) {
    const dup = findDuplicate(orders, draft.woNumber, draft.id);
    if (dup) errors.push({ code: dup.deleted ? 'duplicate_wo_deleted' : 'duplicate_wo', id: dup.id, date: dup.date, district: dup.district });
  }
  for (const p of draft.permits || []) {
    const other = findPermitOwner(orders, p.number, draft.id);
    if (other) errors.push({ code: other.deleted ? 'duplicate_permit_deleted' : 'duplicate_permit_other', permit: p.number, wo: other.woNumber });
  }
  return errors;
}

const normNumber = (s) => normalizeText(String(s || '')).replace(/[\s-]/g, '').toUpperCase();

/** An existing order (deleted ones too, so they can be restored) with the same number. */
export function findDuplicate(orders, woNumber, exceptId = null) {
  const n = normNumber(woNumber);
  if (!n) return null;
  const hits = orders.filter((o) => o.id !== exceptId && normNumber(o.woNumber) === n);
  if (!hits.length) return null;
  const o = hits.find((h) => !h.deleted) || hits[0];
  return { id: o.id, wo: o.woNumber, date: o.receivedDate, district: o.district || '', deleted: !!o.deleted };
}

/**
 * Another order that already uses this tasreeh number. Deleted orders count too: the
 * database keeps their numbers so that restoring them can never clash.
 */
export function findPermitOwner(orders, number, exceptId = null) {
  const n = normNumber(number);
  if (!n) return null;
  const hits = orders.filter((o) => o.id !== exceptId && (o.permits || []).some((p) => normNumber(p.number) === n));
  return hits.find((o) => !o.deleted) || hits[0] || null;
}
