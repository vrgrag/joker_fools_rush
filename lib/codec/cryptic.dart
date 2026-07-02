import 'dart:typed_data';

// ============================================================
// CRYPTIC — obfuscation shim for sensitive strings
// ============================================================
// A different implementation from AdventureRoad's simple XOR:
// here we combine an LCG-derived key with a per-index feistel-like
// rotation. Same encode/decode symmetry, but a distinct fingerprint.
//
// Seed phrase is unique for this app: "rpjkrfr".
// If you change the seed, ALL encoded arrays must be regenerated.
// ============================================================

const List<int> _seedBytes = <int>[
  0x72, 0x70, 0x6A, 0x6B, 0x72, 0x66, 0x72, // rpjkrfr
];

Uint8List _buildStream(int length) {
  int accumulator = 0x9E3779B9;
  for (final int b in _seedBytes) {
    accumulator = ((accumulator ^ b) * 0x01000193) & 0x7FFFFFFF;
  }
  final Uint8List out = Uint8List(length);
  int state = accumulator;
  for (int i = 0; i < length; i++) {
    state = (state * 214013 + 2531011) & 0x7FFFFFFF;
    final int rot = (state >> 16) & 0x7;
    final int byte = ((state >> 8) & 0xFF) ^ ((state & 0xFF) << rot) & 0xFF;
    out[i] = byte;
  }
  return out;
}

/// Deobfuscate an encoded byte list back to a UTF-8 string.
/// Encoded arrays are produced by [scramble] with the same seed.
String reveal(List<int> data) {
  if (data.isEmpty) return '';
  final Uint8List stream = _buildStream(data.length);
  final Uint8List out = Uint8List(data.length);
  for (int i = 0; i < data.length; i++) {
    out[i] = data[i] ^ stream[i] ^ (i & 0x3F);
  }
  return String.fromCharCodes(out);
}

/// Inverse of [reveal]. Kept exposed so encoded arrays can be produced
/// at development time via a small dart script — never call in prod.
List<int> scramble(String plain) {
  final List<int> bytes = plain.codeUnits;
  final Uint8List stream = _buildStream(bytes.length);
  final List<int> out = List<int>.filled(bytes.length, 0);
  for (int i = 0; i < bytes.length; i++) {
    out[i] = bytes[i] ^ stream[i] ^ (i & 0x3F);
  }
  return out;
}
