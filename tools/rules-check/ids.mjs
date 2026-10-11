// Row ids for steps that are the same on every device.
// A step row is identified by (work order, step, segment, meter), which the database
// keeps unique. If the phone and the PC both mark the same step while offline and each
// made up a random id, the second upload would break that rule and block the sync queue.
// With this id both devices write the SAME row, so the upload becomes an update
// (the later change wins) instead of an error. The Dart data layer must use the same
// function (package:uuid's v5 with this namespace); test/fixtures/ids.json holds values
// computed independently with Python's uuid.uuid5.
import { createHash } from 'node:crypto';

export const STEP_ID_NAMESPACE = 'b9d2a3e4-5f61-4c7a-8e9b-0a1b2c3d4e5f';

/** RFC 4122 version 5 UUID (SHA-1 of namespace + name). */
export function uuidV5(namespace, name) {
  const ns = Buffer.from(namespace.replace(/-/g, ''), 'hex');
  const hash = createHash('sha1').update(Buffer.concat([ns, Buffer.from(name, 'utf8')])).digest();
  const b = Buffer.from(hash.subarray(0, 16));
  b[6] = (b[6] & 0x0f) | 0x50;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = b.toString('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

/** The id of the steps row for one step of one work order (segment / meter ids or null). */
export function stepRowId(workOrderId, stepKey, segmentId = null, meterId = null) {
  return uuidV5(STEP_ID_NAMESPACE, `${workOrderId}|${stepKey}|${segmentId || ''}|${meterId || ''}`);
}
