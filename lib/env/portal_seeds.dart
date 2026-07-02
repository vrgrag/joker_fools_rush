import '../codec/cryptic.dart';

// ============================================================
// PORTAL SEEDS — encoded config endpoint
// ============================================================
// The endpoint is split across host + path arrays so the full URL
// never appears as a contiguous string in static analysis.
// Regenerate via `dart run tool/seed_scramble.dart` after changing
// the cryptic seed.
// ============================================================

const List<int> _kConfigHost = <int>[
  0xd5, 0xdb, 0xe8, 0x28, 0x1a, 0x54, 0xfd, 0xde, 0xb3, 0x43, 0x5b, 0x47,
  0x3a, 0x8f, 0xa8, 0x79, 0xf6, 0x98, 0xd5, 0x0a, 0x04, 0x53,
];

const List<int> _kConfigPath = <int>[
  0x92, 0xcc, 0xf3, 0x36, 0x0f, 0x07, 0xb5, 0xdf, 0xa5, 0x44, 0x44,
];

String unlockPortalEndpoint() {
  final String host = reveal(_kConfigHost);
  if (host.isEmpty) return '';
  return '$host${reveal(_kConfigPath)}';
}
