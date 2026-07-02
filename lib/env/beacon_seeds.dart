import '../codec/cryptic.dart';

// ============================================================
// BEACON SEEDS — encoded AppsFlyer key + Firebase project + GCD endpoint
// ============================================================
// The AppsFlyer and Firebase credentials will be supplied later by
// the ops team. Until they're encoded, the arrays are empty and the
// service simply degrades to a no-op — pushService init() catches
// the missing token silently.
//
// After receiving the plaintext values:
//   1. Add them to tool/seed_scramble.dart under distinct labels
//   2. `dart run tool/seed_scramble.dart`
//   3. Paste the printed byte arrays here.
// ============================================================

const List<int> _kAnalyticsKey = <int>[
  0xe4, 0xca, 0xeb, 0x3a, 0x01, 0x5b, 0x9e, 0xbf, 0xbc, 0x61, 0x66, 0x7e,
  0x3d, 0xb7, 0x89, 0x67, 0xe0, 0x97, 0xb8, 0x11, 0x28, 0x7f,
];

const List<int> _kMessagingProject = <int>[
  0x88, 0x9d, 0xa4, 0x69, 0x50, 0x56, 0xe2, 0xc4, 0xe0, 0x1c, 0x00,
];

const List<int> _kGcdHost = <int>[
  0xd5, 0xdb, 0xe8, 0x28, 0x1a, 0x54, 0xfd, 0xde, 0xb2, 0x4f, 0x50, 0x58,
  0x2d, 0x96, 0xf3, 0x6b, 0xf5, 0x80, 0x88, 0x0f, 0x07, 0x47, 0x1e, 0x17,
  0xf6, 0x38, 0x2d, 0x85,
];

const List<int> _kGcdPath = <int>[
  0x92, 0xc6, 0xf2, 0x2b, 0x1d, 0x0f, 0xbe, 0x9d, 0x8a, 0x48, 0x55, 0x5f,
  0x28, 0xd2, 0xab, 0x3e, 0xab, 0xc0, 0xd4,
];

String unlockAnalyticsKey() {
  if (_kAnalyticsKey.isEmpty) return '';
  return reveal(_kAnalyticsKey);
}

String unlockMessagingProject() {
  if (_kMessagingProject.isEmpty) return '';
  return reveal(_kMessagingProject);
}

/// Builds the GCD (Get Conversion Data) endpoint used to reconcile
/// false-organic attribution on returning launches.
String composeGcdEndpoint(String appId, String deviceId) {
  final String host = reveal(_kGcdHost);
  if (host.isEmpty) return '';
  final String path = reveal(_kGcdPath);
  return '$host$path$appId?device_id=$deviceId';
}
