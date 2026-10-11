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

/**
 * The id of the account's one settings row. Two devices that start offline would
 * otherwise each create a settings row and the second upload would be refused.
 */
export function settingsRowId(userId) {
  return uuidV5(STEP_ID_NAMESPACE, `settings|${userId}`);
}

/** The id of the steps row for one step of one work order (segment / meter ids or null). */
export function stepRowId(workOrderId, stepKey, segmentId = null, meterId = null) {
  return uuidV5(STEP_ID_NAMESPACE, `${workOrderId}|${stepKey}|${segmentId || ''}|${meterId || ''}`);
}

// ---- Plain SHA-1, written exactly like the Dart version (app/lib/data/ids.dart) ----
// The app cannot use node:crypto, so the Dart code carries its own SHA-1. This copy
// is checked against node:crypto on many inputs, which checks the algorithm the Dart
// file follows line by line.
const rotl = (x, n) => ((x << n) | (x >>> (32 - n))) >>> 0;

/** SHA-1 of a byte array, as 20 bytes. */
export function sha1Plain(bytes) {
  const ml = bytes.length;
  const withPad = ((ml + 8) >> 6) * 64 + 64; // room for 0x80 + 8-byte length
  const msg = new Uint8Array(withPad);
  msg.set(bytes);
  msg[ml] = 0x80;
  const bitLen = ml * 8;
  // Length in bits, big-endian, in the last 8 bytes (high word only matters above 512 MB).
  const hi = Math.floor(bitLen / 0x100000000);
  const lo = bitLen >>> 0;
  for (let i = 0; i < 4; i++) {
    msg[withPad - 8 + i] = (hi >>> (24 - 8 * i)) & 0xff;
    msg[withPad - 4 + i] = (lo >>> (24 - 8 * i)) & 0xff;
  }
  let h0 = 0x67452301, h1 = 0xefcdab89, h2 = 0x98badcfe, h3 = 0x10325476, h4 = 0xc3d2e1f0;
  const w = new Array(80).fill(0);
  for (let off = 0; off < withPad; off += 64) {
    for (let i = 0; i < 16; i++) {
      w[i] = ((msg[off + 4 * i] << 24) | (msg[off + 4 * i + 1] << 16) | (msg[off + 4 * i + 2] << 8) | msg[off + 4 * i + 3]) >>> 0;
    }
    for (let i = 16; i < 80; i++) w[i] = rotl((w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]) >>> 0, 1);
    let a = h0, b = h1, c = h2, d = h3, e = h4;
    for (let i = 0; i < 80; i++) {
      let f, k;
      if (i < 20) { f = ((b & c) | (~b & d)) >>> 0; k = 0x5a827999; }
      else if (i < 40) { f = (b ^ c ^ d) >>> 0; k = 0x6ed9eba1; }
      else if (i < 60) { f = ((b & c) | (b & d) | (c & d)) >>> 0; k = 0x8f1bbcdc; }
      else { f = (b ^ c ^ d) >>> 0; k = 0xca62c1d6; }
      const t = (rotl(a, 5) + f + e + k + w[i]) >>> 0;
      e = d; d = c; c = rotl(b, 30); b = a; a = t;
    }
    h0 = (h0 + a) >>> 0; h1 = (h1 + b) >>> 0; h2 = (h2 + c) >>> 0; h3 = (h3 + d) >>> 0; h4 = (h4 + e) >>> 0;
  }
  const out = new Uint8Array(20);
  [h0, h1, h2, h3, h4].forEach((h, j) => { for (let i = 0; i < 4; i++) out[4 * j + i] = (h >>> (24 - 8 * i)) & 0xff; });
  return out;
}

/** Version 5 UUID using sha1Plain (same steps as the Dart code). */
export function uuidV5Plain(namespace, name) {
  const hex = namespace.replace(/-/g, '');
  const ns = [];
  for (let i = 0; i < 32; i += 2) ns.push(parseInt(hex.slice(i, i + 2), 16));
  const hash = sha1Plain(new Uint8Array([...ns, ...new TextEncoder().encode(name)]));
  const b = Array.from(hash.slice(0, 16));
  b[6] = (b[6] & 0x0f) | 0x50;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = b.map((x) => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
