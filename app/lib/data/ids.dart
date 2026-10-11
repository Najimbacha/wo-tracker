// Row ids for steps that are the same on every device.
//
// A step row is identified by (work order, step, segment, meter), which the database
// keeps unique. If the phone and the PC both mark the same step while offline and each
// made up a random id, the second upload would break that rule and block the sync queue.
// With this id both devices write the SAME row, so the upload becomes an update
// (the later change wins) instead of an error.
//
// Plain Dart, no package: SHA-1 and UUID version 5 (RFC 4122). It follows
// tools/rules-check/ids.mjs line by line; that copy is checked against node:crypto,
// and test/fixtures/ids.json holds values computed with Python's uuid.uuid5.
import 'dart:convert' show utf8;
import 'dart:typed_data';

class StepIds {
  StepIds._();

  static const namespace = 'b9d2a3e4-5f61-4c7a-8e9b-0a1b2c3d4e5f';

  /// The id of the steps row for one step of one work order.
  static String stepRowId(String workOrderId, String stepKey, {String? segmentId, String? meterId}) =>
      uuidV5(namespace, '$workOrderId|$stepKey|${segmentId ?? ''}|${meterId ?? ''}');

  /// The account's one settings row: the same id on every device.
  static String settingsRowId(String userId) => uuidV5(namespace, 'settings|$userId');

  /// RFC 4122 version 5 UUID (SHA-1 of namespace bytes + UTF-8 name).
  static String uuidV5(String ns, String name) {
    final hex = ns.replaceAll('-', '');
    final bytes = <int>[
      for (var i = 0; i < 32; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
      ...utf8.encode(name),
    ];
    final hash = sha1(Uint8List.fromList(bytes));
    final b = List<int>.from(hash.sublist(0, 16));
    b[6] = (b[6] & 0x0f) | 0x50;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static const _mask = 0xffffffff;
  static int _rotl(int x, int n) => ((x << n) | (x >> (32 - n))) & _mask;

  /// SHA-1 of [bytes], as 20 bytes.
  static Uint8List sha1(Uint8List bytes) {
    final ml = bytes.length;
    final withPad = ((ml + 8) >> 6) * 64 + 64; // room for 0x80 + 8-byte length
    final msg = Uint8List(withPad)..setRange(0, ml, bytes);
    msg[ml] = 0x80;
    final bitLen = ml * 8;
    final hi = (bitLen >> 32) & _mask;
    final lo = bitLen & _mask;
    for (var i = 0; i < 4; i++) {
      msg[withPad - 8 + i] = (hi >> (24 - 8 * i)) & 0xff;
      msg[withPad - 4 + i] = (lo >> (24 - 8 * i)) & 0xff;
    }
    var h0 = 0x67452301, h1 = 0xefcdab89, h2 = 0x98badcfe, h3 = 0x10325476, h4 = 0xc3d2e1f0;
    final w = List<int>.filled(80, 0);
    for (var off = 0; off < withPad; off += 64) {
      for (var i = 0; i < 16; i++) {
        w[i] = (msg[off + 4 * i] << 24) | (msg[off + 4 * i + 1] << 16) | (msg[off + 4 * i + 2] << 8) | msg[off + 4 * i + 3];
      }
      for (var i = 16; i < 80; i++) {
        w[i] = _rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
      }
      var a = h0, b = h1, c = h2, d = h3, e = h4;
      for (var i = 0; i < 80; i++) {
        int f, k;
        if (i < 20) {
          f = (b & c) | ((~b & _mask) & d);
          k = 0x5a827999;
        } else if (i < 40) {
          f = b ^ c ^ d;
          k = 0x6ed9eba1;
        } else if (i < 60) {
          f = (b & c) | (b & d) | (c & d);
          k = 0x8f1bbcdc;
        } else {
          f = b ^ c ^ d;
          k = 0xca62c1d6;
        }
        final t = (_rotl(a, 5) + f + e + k + w[i]) & _mask;
        e = d;
        d = c;
        c = _rotl(b, 30);
        b = a;
        a = t;
      }
      h0 = (h0 + a) & _mask;
      h1 = (h1 + b) & _mask;
      h2 = (h2 + c) & _mask;
      h3 = (h3 + d) & _mask;
      h4 = (h4 + e) & _mask;
    }
    final out = Uint8List(20);
    final hs = [h0, h1, h2, h3, h4];
    for (var j = 0; j < 5; j++) {
      for (var i = 0; i < 4; i++) {
        out[4 * j + i] = (hs[j] >> (24 - 8 * i)) & 0xff;
      }
    }
    return out;
  }
}
